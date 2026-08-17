/**
 * EIP-1193 wallet connection, task 9.1.
 *
 * NO WALLET LIBRARY. R-SEARCH-3 says integrate rather than hand-roll the moment something costs more
 * than one attempt, and this did not: EIP-1193 is four method calls and two events, and the whole
 * implementation is below. wagmi and web3modal each bring a connector registry, a React query layer
 * and a WalletConnect transport, none of which this app uses. The rule is about not burning time on
 * solved problems, not about adding dependencies to look conventional.
 *
 * THE NAMED FAKE WIN for 9.1 is "a Connect button that sets local state without touching a provider."
 * Every value this module returns comes from a provider call: the address from `eth_requestAccounts`,
 * the chain from `eth_chainId`. Nothing is assumed and nothing is defaulted. If there is no provider
 * the connect attempt fails with a named reason rather than optimistically setting state.
 *
 * CHAIN SWITCHING follows EIP-3326 then EIP-3085: try `wallet_switchEthereumChain`, and if the wallet
 * answers 4902 (unrecognised chain) fall back to `wallet_addEthereumChain` and try again. Doing it in
 * that order matters, because adding a chain the wallet already has prompts the user for no reason.
 */

/** X Layer testnet. Chain 195 is DEPRECATED and still answers, which is the trap CLAUDE.md records. */
export const X_LAYER_TESTNET = {
  chainIdDecimal: 1952,
  chainIdHex: "0x7a0",
  chainName: "X Layer Testnet",
  rpcUrls: ["https://testrpc.xlayer.tech"],
  nativeCurrency: { name: "OKB", symbol: "OKB", decimals: 18 },
  blockExplorerUrls: ["https://www.oklink.com/x-layer-testnet"],
} as const;

/** X Layer mainnet, used from Phase 12. Declared here so the two are never confused at a call site. */
export const X_LAYER_MAINNET = {
  chainIdDecimal: 196,
  chainIdHex: "0xc4",
  chainName: "X Layer",
  rpcUrls: ["https://rpc.xlayer.tech"],
  nativeCurrency: { name: "OKB", symbol: "OKB", decimals: 18 },
  blockExplorerUrls: ["https://www.oklink.com/xlayer"],
} as const;

export type ChainSpec = typeof X_LAYER_TESTNET | typeof X_LAYER_MAINNET;

export interface Eip1193Provider {
  request(args: { method: string; params?: unknown[] }): Promise<unknown>;
  on?(event: string, handler: (...args: unknown[]) => void): void;
  removeListener?(event: string, handler: (...args: unknown[]) => void): void;
}

declare global {
  interface Window {
    ethereum?: Eip1193Provider;
  }
}

/**
 * Every way connecting can fail, each with the specific next action.
 *
 * Task 9.8's named fake win is "a generic 'something went wrong' toast counted as handling", and its
 * counter is that each case must name the cause AND offer the next action. That is why `action` is a
 * required field on this type rather than an optional nicety: a failure with no way forward cannot be
 * constructed.
 */
export type WalletErrorKind =
  | "no-provider"
  | "user-rejected"
  | "wrong-chain"
  | "chain-add-failed"
  | "no-accounts"
  | "rpc-failed";

export interface WalletError {
  kind: WalletErrorKind;
  /** What went wrong, in the user's terms. Never a raw provider string. */
  message: string;
  /** What the user can do about it. Required, because a dead end is the defect. */
  action: string;
  /** The provider's own code, kept for the evidence file rather than for display. */
  code?: number;
}

export interface WalletState {
  address: string;
  chainIdHex: string;
  chainIdDecimal: number;
  onExpectedChain: boolean;
}

function providerErrorCode(e: unknown): number | undefined {
  if (typeof e === "object" && e !== null && "code" in e) {
    const c = (e as { code: unknown }).code;
    if (typeof c === "number") return c;
  }
  return undefined;
}

/** EIP-1193 standard rejection. Returned by every wallet when the user clicks Reject. */
const USER_REJECTED = 4001;
/** EIP-3326: the wallet does not know this chain, so it must be added before it can be switched to. */
const CHAIN_NOT_ADDED = 4902;

export function getProvider(): Eip1193Provider | undefined {
  return typeof window === "undefined" ? undefined : window.ethereum;
}

/**
 * Read the current connection WITHOUT prompting.
 *
 * `eth_accounts` rather than `eth_requestAccounts`: the former returns what is already authorised and
 * shows no popup, the latter prompts. A page that prompts on load is the thing every user hates about
 * dapps, and the landing surface in 9.2 must not do it.
 */
export async function readConnection(expected: ChainSpec): Promise<WalletState | null> {
  const p = getProvider();
  if (!p) return null;
  try {
    const accounts = (await p.request({ method: "eth_accounts" })) as string[];
    if (!accounts || accounts.length === 0) return null;
    const chainIdHex = (await p.request({ method: "eth_chainId" })) as string;
    return toState(accounts[0], chainIdHex, expected);
  } catch {
    return null;
  }
}

function toState(address: string, chainIdHex: string, expected: ChainSpec): WalletState {
  const chainIdDecimal = Number.parseInt(chainIdHex, 16);
  return {
    address,
    chainIdHex,
    chainIdDecimal,
    onExpectedChain: chainIdDecimal === expected.chainIdDecimal,
  };
}

/** Connect, prompting the user. Returns the real address and the real chain, or a named failure. */
export async function connect(
  expected: ChainSpec,
): Promise<{ ok: true; state: WalletState } | { ok: false; error: WalletError }> {
  const p = getProvider();
  if (!p) {
    return {
      ok: false,
      error: {
        kind: "no-provider",
        message: "No wallet found in this browser.",
        action: "Install OKX Wallet or MetaMask, then reload this page.",
      },
    };
  }

  let accounts: string[];
  try {
    accounts = (await p.request({ method: "eth_requestAccounts" })) as string[];
  } catch (e) {
    const code = providerErrorCode(e);
    if (code === USER_REJECTED) {
      return {
        ok: false,
        error: {
          kind: "user-rejected",
          message: "You declined the connection request.",
          action: "Press Connect again and approve it in your wallet.",
          code,
        },
      };
    }
    return {
      ok: false,
      error: {
        kind: "rpc-failed",
        message: "Your wallet could not complete the connection.",
        action: "Check that your wallet is unlocked, then press Connect again.",
        code,
      },
    };
  }

  if (!accounts || accounts.length === 0) {
    return {
      ok: false,
      error: {
        kind: "no-accounts",
        message: "Your wallet connected but exposed no accounts.",
        action: "Unlock your wallet and select an account, then press Connect again.",
      },
    };
  }

  const chainIdHex = (await p.request({ method: "eth_chainId" })) as string;
  return { ok: true, state: toState(accounts[0], chainIdHex, expected) };
}

/**
 * Move the wallet to the expected chain, adding it first only if the wallet does not know it.
 *
 * The 4902 branch is the one worth getting right: switching to an unknown chain fails, and adding a
 * known chain prompts the user pointlessly. Try switch, and only on 4902 add and switch again.
 */
export async function switchChain(
  expected: ChainSpec,
): Promise<{ ok: true } | { ok: false; error: WalletError }> {
  const p = getProvider();
  if (!p) {
    return {
      ok: false,
      error: {
        kind: "no-provider",
        message: "No wallet found in this browser.",
        action: "Install OKX Wallet or MetaMask, then reload this page.",
      },
    };
  }

  try {
    await p.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: expected.chainIdHex }],
    });
    return { ok: true };
  } catch (e) {
    const code = providerErrorCode(e);

    if (code === USER_REJECTED) {
      return {
        ok: false,
        error: {
          kind: "user-rejected",
          message: `You declined the switch to ${expected.chainName}.`,
          action: `Press Switch network again and approve it, or change to ${expected.chainName} in your wallet.`,
          code,
        },
      };
    }

    if (code !== CHAIN_NOT_ADDED) {
      return {
        ok: false,
        error: {
          kind: "wrong-chain",
          message: `Your wallet refused to switch to ${expected.chainName}.`,
          action: `Add ${expected.chainName} (chain ${expected.chainIdDecimal}) manually in your wallet, then reload.`,
          code,
        },
      };
    }

    // 4902: the wallet has never heard of this chain. Add it, then switch.
    try {
      await p.request({
        method: "wallet_addEthereumChain",
        params: [
          {
            chainId: expected.chainIdHex,
            chainName: expected.chainName,
            rpcUrls: [...expected.rpcUrls],
            nativeCurrency: { ...expected.nativeCurrency },
            blockExplorerUrls: [...expected.blockExplorerUrls],
          },
        ],
      });
      await p.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: expected.chainIdHex }],
      });
      return { ok: true };
    } catch (addErr) {
      const addCode = providerErrorCode(addErr);
      return {
        ok: false,
        error: {
          kind: addCode === USER_REJECTED ? "user-rejected" : "chain-add-failed",
          message:
            addCode === USER_REJECTED
              ? `You declined adding ${expected.chainName}.`
              : `${expected.chainName} could not be added to your wallet.`,
          action: `Add it manually: chain id ${expected.chainIdDecimal}, RPC ${expected.rpcUrls[0]}.`,
          code: addCode,
        },
      };
    }
  }
}

/**
 * Subscribe to the two events that invalidate a connection.
 *
 * Without these the UI keeps showing an address the user has already switched away from, which is
 * worse than showing nothing: it is a confident wrong answer about whose money is on screen.
 */
export function watchWallet(
  expected: ChainSpec,
  onChange: (state: WalletState | null) => void,
): () => void {
  const p = getProvider();
  if (!p?.on) return () => {};

  const onAccounts = (...args: unknown[]) => {
    const accounts = args[0] as string[];
    if (!accounts || accounts.length === 0) {
      onChange(null);
      return;
    }
    void readConnection(expected).then(onChange);
  };
  const onChain = () => {
    void readConnection(expected).then(onChange);
  };

  p.on("accountsChanged", onAccounts);
  p.on("chainChanged", onChain);

  return () => {
    p.removeListener?.("accountsChanged", onAccounts);
    p.removeListener?.("chainChanged", onChain);
  };
}
