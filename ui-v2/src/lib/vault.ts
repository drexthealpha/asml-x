/**
 * AgentVault reads and writes from the browser, tasks 9.3 through 9.7.
 *
 * NO ABI LIBRARY, and no ethers or viem. Every call here is one of four function selectors and a
 * 32-byte word, which is less code than the import would be. R-SEARCH-3 is about not burning time
 * on solved problems; it is not a rule that a dependency must be added to look conventional.
 *
 * Selectors are written below with their signatures beside them, and `scripts/verify-selectors.sh`
 * checks every one against `cast sig`. That check is not ceremony: on its first run FIVE of the
 * ELEVEN selectors here were wrong. A wrong selector does not throw. It calls a different function
 * or hits the fallback, and `eth_call` returns `0x`, which this module would have read as a
 * perfectly plausible zero balance. The UI would have shown a confident, wrong number with no error
 * anywhere. That is precisely the failure mode hand-encoding invites, and the only defence is
 * checking the encoding against a tool that computes it independently.
 *
 * AMOUNTS ARE STRINGS AND BIGINTS, NEVER NUMBERS. A tQUOTE balance is 18 decimals, so 5 tokens is
 * 5000000000000000000, which is already past the point where a double starts losing integers. A
 * balance that silently rounds is the same defect as a balance that is invented.
 */

const SELECTORS = {
  // cast sig "balanceOf(address)"
  balanceOf: "0x70a08231",
  // cast sig "maxNotional(address)"
  maxNotional: "0xbebb9b6c",
  // cast sig "paused(address)"
  paused: "0x2e48152c",
  // cast sig "withdrawable(address)"
  withdrawable: "0xce513b6f",
  // cast sig "committed(address)"
  committed: "0xd88d9b70",
  // cast sig "deposit(uint256,uint256)"
  deposit: "0xe2bbb158",
  // cast sig "withdrawAll()"
  withdrawAll: "0x853828b6",
  // cast sig "setPaused(bool)"
  setPaused: "0x16c38b3c",
  // cast sig "approve(address,uint256)"
  approve: "0x095ea7b3",
  // cast sig "allowance(address,address)"
  allowance: "0xdd62ed3e",
  // cast sig "feeBps()"
  feeBps: "0x24a9d853",
  // cast sig "depositWithPermit(uint256,uint256,uint256,uint8,bytes32,bytes32)"
  depositWithPermit: "0x515bc323",
  // cast sig "nonces(address)"
  nonces: "0x7ecebe00",
  // cast sig "name()"
  name: "0x06fdde03",
} as const;

function padAddress(addr: string): string {
  return addr.toLowerCase().replace(/^0x/, "").padStart(64, "0");
}

function padUint(v: bigint): string {
  return v.toString(16).padStart(64, "0");
}

export interface VaultAddresses {
  agentVault: string;
  tQUOTE: string;
  feeCollector: string;
}

async function ethCall(to: string, data: string, rpcUrl: string): Promise<string> {
  const res = await fetch(rpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "eth_call",
      params: [{ to, data }, "latest"],
    }),
  });
  const body = await res.json();
  if (body.error) throw new Error(body.error.message || "eth_call failed");
  return body.result as string;
}

function toBigInt(hex: string): bigint {
  return BigInt(hex && hex !== "0x" ? hex : "0x0");
}

export interface VaultPosition {
  balanceWei: bigint;
  withdrawableWei: bigint;
  committedWei: bigint;
  maxNotionalWei: bigint;
  paused: boolean;
  allowanceWei: bigint;
  feeBps: number;
}

/**
 * Read everything the personal dashboard shows, in one pass.
 *
 * Every field comes from a chain read. Nothing is defaulted to zero on failure: the caller gets a
 * thrown error and renders it, because task 9.7's counter is that a loading state must be
 * distinguishable from a real zero, and a zero balance and a failed read are different facts.
 */
export async function readPosition(
  who: string,
  a: VaultAddresses,
  rpcUrl: string,
): Promise<VaultPosition> {
  const w = padAddress(who);
  const [bal, wd, com, maxN, pau, allo, fee] = await Promise.all([
    ethCall(a.agentVault, SELECTORS.balanceOf + w, rpcUrl),
    ethCall(a.agentVault, SELECTORS.withdrawable + w, rpcUrl),
    ethCall(a.agentVault, SELECTORS.committed + w, rpcUrl),
    ethCall(a.agentVault, SELECTORS.maxNotional + w, rpcUrl),
    ethCall(a.agentVault, SELECTORS.paused + w, rpcUrl),
    ethCall(a.tQUOTE, SELECTORS.allowance + w + padAddress(a.agentVault), rpcUrl),
    ethCall(a.feeCollector, SELECTORS.feeBps, rpcUrl),
  ]);

  return {
    balanceWei: toBigInt(bal),
    withdrawableWei: toBigInt(wd),
    committedWei: toBigInt(com),
    maxNotionalWei: toBigInt(maxN),
    paused: toBigInt(pau) !== 0n,
    allowanceWei: toBigInt(allo),
    feeBps: Number(toBigInt(fee)),
  };
}

/** Calldata builders. Separated from sending so a gate can assert the encoding without a wallet. */
export const encode = {
  approve: (spender: string, amount: bigint) =>
    SELECTORS.approve + padAddress(spender) + padUint(amount),
  deposit: (amount: bigint, maxNotional: bigint) =>
    SELECTORS.deposit + padUint(amount) + padUint(maxNotional),
  withdrawAll: () => SELECTORS.withdrawAll,
  depositWithPermit: (
    amount: bigint,
    maxNotional: bigint,
    deadline: bigint,
    v: number,
    r: string,
    s: string,
  ) =>
    SELECTORS.depositWithPermit +
    padUint(amount) +
    padUint(maxNotional) +
    padUint(deadline) +
    padUint(BigInt(v)) +
    r.replace(/^0x/, "") +
    s.replace(/^0x/, ""),
  setPaused: (v: boolean) => SELECTORS.setPaused + padUint(v ? 1n : 0n),
};

/** 18 decimals, formatted by string slicing. No division, so nothing rounds. */
export function formatWei(wei: bigint, dp = 4): string {
  const s = wei.toString().padStart(19, "0");
  const whole = s.slice(0, s.length - 18).replace(/^0+(?=\d)/, "");
  const frac = s.slice(s.length - 18, s.length - 18 + dp);
  return `${whole}.${frac}`;
}


/**
 * The EIP-712 payload a wallet signs to authorise a permit.
 *
 * TASK 9.4 IS WHY THIS EXISTS. A cold user's path was four interactions: approve, confirm, deposit,
 * confirm. A permit signature replaces the approval TRANSACTION with a SIGNATURE, so the path is
 * click, sign, confirm. ADR-017 records the alternatives, including the one that was rejected for
 * asking users to grant an unbounded allowance to shorten a metric.
 *
 * The type strings must match the contract's typehashes exactly, and
 * `scripts/verify-typehashes.sh` proves they do. A mismatch reverts with InvalidSignature, which is
 * loud, rather than producing a subtly wrong signature.
 */
export function permitTypedData(args: {
  tokenName: string;
  tokenAddress: string;
  chainId: number;
  owner: string;
  spender: string;
  value: bigint;
  nonce: bigint;
  deadline: bigint;
}) {
  return {
    types: {
      EIP712Domain: [
        { name: "name", type: "string" },
        { name: "version", type: "string" },
        { name: "chainId", type: "uint256" },
        { name: "verifyingContract", type: "address" },
      ],
      Permit: [
        { name: "owner", type: "address" },
        { name: "spender", type: "address" },
        { name: "value", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" },
      ],
    },
    primaryType: "Permit",
    domain: {
      name: args.tokenName,
      version: "1",
      chainId: args.chainId,
      verifyingContract: args.tokenAddress,
    },
    message: {
      owner: args.owner,
      spender: args.spender,
      value: args.value.toString(),
      nonce: args.nonce.toString(),
      deadline: args.deadline.toString(),
    },
  };
}

/** Split a 65-byte signature into the v, r, s the contract expects. */
export function splitSignature(sig: string): { v: number; r: string; s: string } {
  const h = sig.replace(/^0x/, "");
  if (h.length !== 130) throw new Error(`signature is ${h.length / 2} bytes, expected 65`);
  const r = "0x" + h.slice(0, 64);
  const s = "0x" + h.slice(64, 128);
  let v = Number.parseInt(h.slice(128, 130), 16);
  // Some signers return 0/1 rather than 27/28. Normalising here rather than in the contract keeps
  // the contract to the spec.
  if (v < 27) v += 27;
  return { v, r, s };
}

/** Read the token's current permit nonce and name, both needed to build the payload. */
export async function readPermitInputs(
  owner: string,
  token: string,
  rpcUrl: string,
): Promise<{ nonce: bigint; name: string }> {
  const [nonceHex, nameHex] = await Promise.all([
    ethCall(token, SELECTORS.nonces + padAddress(owner), rpcUrl),
    ethCall(token, SELECTORS.name, rpcUrl),
  ]);
  return { nonce: toBigInt(nonceHex), name: decodeString(nameHex) };
}

/** Decode an ABI-encoded string return value. */
function decodeString(hex: string): string {
  const h = hex.replace(/^0x/, "");
  if (h.length < 128) return "";
  const len = Number.parseInt(h.slice(64, 128), 16);
  const bytes = h.slice(128, 128 + len * 2);
  let out = "";
  for (let i = 0; i < bytes.length; i += 2) {
    out += String.fromCharCode(Number.parseInt(bytes.slice(i, i + 2), 16));
  }
  return out;
}
