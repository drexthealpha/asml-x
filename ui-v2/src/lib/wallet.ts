/**
 * The wallet, and the four things a person actually does with money here.
 *
 * NOTHING IS OPTIMISTIC. Every value below is read back from the chain after the transaction it
 * describes. A balance that updates locally on a button press is a lie that survives until the
 * next reload, and it is the exact failure mode this product exists to argue against.
 *
 * ADDRESSES COME FROM THE MANIFEST. Not one is typed in this file. The manifest is written by the
 * deploy scripts from the deployment that actually happened.
 */

const X_LAYER = {
  chainIdHex: "0xc4",
  chainIdDecimal: 196,
  chainName: "X Layer",
  rpcUrls: ["https://rpc.xlayer.tech"],
  nativeCurrency: { name: "OKB", symbol: "OKB", decimals: 18 },
  blockExplorerUrls: ["https://www.oklink.com/x-layer"],
} as const;

export interface Eip1193 {
  request(a: { method: string; params?: unknown[] }): Promise<unknown>;
  on?(e: string, h: (...a: unknown[]) => void): void;
  removeListener?(e: string, h: (...a: unknown[]) => void): void;
}

export interface Wallet {
  address: string;
  chainId: number;
  onXLayer: boolean;
}

/** A failure a person can act on. `next` is required: a dead end is not an error message. */
export interface WalletError {
  message: string;
  next: string;
}

/**
 * The active provider: an injected extension, or a WalletConnect session.
 *
 * ONE ACCESSOR, so every read and write below is agnostic about which it is. A WalletConnect
 * session is registered here rather than being given its own set of balance and deposit functions;
 * a second implementation of the money path is a second place for it to be wrong.
 *
 * The override is checked FIRST: if someone connected by QR while an extension is also installed,
 * they chose the QR.
 */
let override: Eip1193 | null = null;

export function setProvider(p: Eip1193 | null): void {
  override = p;
}

export function provider(): Eip1193 | null {
  if (override) return override;
  const w = window as unknown as { ethereum?: Eip1193 };
  return w.ethereum ?? null;
}

/** True when a wallet can be reached at all, by either route. */
export function walletReachable(): boolean {
  return provider() !== null;
}


/** Read an existing connection WITHOUT prompting. A page that opens a wallet popup on load is rude. */
export async function readWallet(): Promise<Wallet | null> {
  const p = provider();
  if (!p) return null;
  try {
    const accounts = (await p.request({ method: "eth_accounts" })) as string[];
    if (!accounts?.length) return null;
    const chainId = Number.parseInt((await p.request({ method: "eth_chainId" })) as string, 16);
    return { address: accounts[0], chainId, onXLayer: chainId === X_LAYER.chainIdDecimal };
  } catch {
    return null;
  }
}

export async function connect(): Promise<{ ok: true; wallet: Wallet } | { ok: false; error: WalletError }> {
  const p = provider();
  if (!p) {
    return {
      ok: false,
      error: {
        message: "No wallet found in this browser.",
        next: "Install OKX Wallet or MetaMask, then reload this page.",
      },
    };
  }
  try {
    const accounts = (await p.request({ method: "eth_requestAccounts" })) as string[];
    const chainId = Number.parseInt((await p.request({ method: "eth_chainId" })) as string, 16);
    return {
      ok: true,
      wallet: { address: accounts[0], chainId, onXLayer: chainId === X_LAYER.chainIdDecimal },
    };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    // Closing the popup is a choice, not a fault, and must not be reported as one.
    return {
      ok: false,
      error: /reject|denied|cancel/i.test(msg)
        ? { message: "Connection cancelled.", next: "Press Connect again when you are ready." }
        : { message: msg, next: "Try again." },
    };
  }
}

export async function switchToXLayer(): Promise<boolean> {
  const p = provider();
  if (!p) return false;
  try {
    await p.request({ method: "wallet_switchEthereumChain", params: [{ chainId: X_LAYER.chainIdHex }] });
    return true;
  } catch {
    try {
      // 4902: the wallet does not know this chain yet. Adding it is the correct recovery.
      await p.request({ method: "wallet_addEthereumChain", params: [X_LAYER] });
      return true;
    } catch {
      return false;
    }
  }
}

// ------------------------------------------------------------------ reads

async function call(to: string, data: string): Promise<string> {
  const p = provider();
  if (!p) throw new Error("no wallet");
  return (await p.request({ method: "eth_call", params: [{ to, data }, "latest"] })) as string;
}

/**
 * Function selectors, COMPUTED not guessed. Regenerate with `bash scripts/220-selectors.sh`.
 *
 * Two of these were wrong when written from memory: `deposit` and `maxNotional`. A wrong selector
 * does not throw. `eth_call` returns `0x`, which parses as zero, so the screen would have shown a
 * confident "0.00" balance and a "0" limit for someone holding real money, and `deposit` would
 * have reverted with no clue why. This is the second time an invented selector has cost this
 * project real time, which is why they now come out of `cast sig` and the script is committed.
 */
const SELECTORS = {
  balanceOf: "0x70a08231",
  decimals: "0x313ce567",
  allowance: "0xdd62ed3e",
  approve: "0x095ea7b3",
  // AgentVault
  vaultBalanceOf: "0x70a08231",
  maxNotional: "0xbebb9b6c",
  deposit: "0xe2bbb158",
  withdraw: "0x2e1a7d4d",
  withdrawAll: "0x853828b6",
  paused: "0x5c975abb",
} as const;

const pad = (s: string) => s.replace(/^0x/, "").padStart(64, "0");
const addrArg = (a: string) => pad(a.toLowerCase());
const uintArg = (v: bigint) => pad(v.toString(16));

export async function tokenBalance(token: string, owner: string): Promise<bigint> {
  const r = await call(token, SELECTORS.balanceOf + addrArg(owner));
  return BigInt(r === "0x" ? 0 : r);
}

export async function tokenDecimals(token: string): Promise<number> {
  const r = await call(token, SELECTORS.decimals);
  return r === "0x" ? 18 : Number(BigInt(r));
}

export async function allowance(token: string, owner: string, spender: string): Promise<bigint> {
  const r = await call(token, SELECTORS.allowance + addrArg(owner) + addrArg(spender));
  return BigInt(r === "0x" ? 0 : r);
}

export async function vaultPosition(vault: string, who: string) {
  const [bal, limit] = await Promise.all([
    call(vault, SELECTORS.vaultBalanceOf + addrArg(who)),
    call(vault, SELECTORS.maxNotional + addrArg(who)),
  ]);
  return {
    balance: BigInt(bal === "0x" ? 0 : bal),
    maxNotional: BigInt(limit === "0x" ? 0 : limit),
  };
}

export async function vaultPaused(vault: string): Promise<boolean> {
  try {
    const r = await call(vault, SELECTORS.paused);
    return BigInt(r === "0x" ? 0 : r) === 1n;
  } catch {
    return false;
  }
}

// ------------------------------------------------------------------ writes

async function send(from: string, to: string, data: string): Promise<string> {
  const p = provider();
  if (!p) throw new Error("no wallet");
  return (await p.request({ method: "eth_sendTransaction", params: [{ from, to, data }] })) as string;
}

export const approve = (from: string, token: string, spender: string, amount: bigint) =>
  send(from, token, SELECTORS.approve + addrArg(spender) + uintArg(amount));

/**
 * Deposit, and set the ceiling in the same transaction.
 *
 * The limit is not a separate step by design: there is no window in which funds sit in the vault
 * with no ceiling attached to them.
 */
export const deposit = (from: string, vault: string, amount: bigint, maxNotional: bigint) =>
  send(from, vault, SELECTORS.deposit + uintArg(amount) + uintArg(maxNotional));

export const withdraw = (from: string, vault: string, amount: bigint) =>
  send(from, vault, SELECTORS.withdraw + uintArg(amount));

/** Decimal string to base units, by integer arithmetic. Never a float. */
export function toUnits(value: string, decimals: number): bigint {
  const [i, f = ""] = value.trim().split(".");
  const frac = (f + "0".repeat(decimals)).slice(0, decimals);
  return BigInt(i || "0") * 10n ** BigInt(decimals) + BigInt(frac || "0");
}

/** Base units to a readable decimal string. Trims trailing zeros, never rounds to nothing. */
export function fromUnits(v: bigint, decimals: number, places = 4): string {
  const base = 10n ** BigInt(decimals);
  const whole = v / base;
  const frac = v % base;
  if (frac === 0n) return whole.toString();
  const s = frac.toString().padStart(decimals, "0").slice(0, places).replace(/0+$/, "");
  return s ? `${whole}.${s}` : whole.toString();
}

export const EXPLORER_TX = "https://www.oklink.com/x-layer/evm/tx/";
export { X_LAYER };
