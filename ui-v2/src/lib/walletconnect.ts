/**
 * WalletConnect. The only way most people can use this.
 *
 * WHY IT IS NOT OPTIONAL. The injected-provider path requires a browser extension, and browser
 * extensions do not exist on phones. Without this, every mobile visitor reaches a dead end that
 * reads "install a wallet and reload", which is not an instruction they can follow. That is the
 * majority of anyone who opens a link.
 *
 * WHAT IT RETURNS. An EIP-1193 provider, the same interface an extension exposes, so every read
 * and write in `wallet.ts` works against it unchanged. That is the entire reason for choosing
 * WalletConnect over a bespoke mobile flow: one interface, one code path, no second implementation
 * of the money functions to keep in sync.
 *
 * LOADED ON DEMAND. The library is heavy and most desktop visitors never need it, so it is a
 * dynamic import behind the button rather than part of the initial bundle.
 *
 * THE PROJECT ID IS PUBLIC BY DESIGN. WalletConnect project ids are client-side identifiers shipped
 * in every dapp bundle; they authorise nothing and hold no funds. It is read from
 * `VITE_WALLETCONNECT_PROJECT_ID` when set so a fork can use its own.
 */

import type { Eip1193 } from "./wallet";
import { X_LAYER } from "./wallet";

const PROJECT_ID =
  (import.meta.env.VITE_WALLETCONNECT_PROJECT_ID as string | undefined) ??
  "b90895a5b6e33e248e0e868aa029c108";

let cached: Eip1193 | null = null;

/**
 * Open the QR / deep-link flow and return a connected provider.
 *
 * Throws with the wallet's own message. The caller distinguishes "the user closed the modal" from
 * a real failure, because a cancelled connection is a choice and must not be reported as a fault.
 */
export async function connectWalletConnect(): Promise<Eip1193> {
  if (cached) return cached;

  const { EthereumProvider } = await import("@walletconnect/ethereum-provider");

  const provider = await EthereumProvider.init({
    projectId: PROJECT_ID,
    // X Layer only. Listing chains this app cannot serve would let someone connect on a network
    // where every contract address is meaningless.
    chains: [X_LAYER.chainIdDecimal],
    optionalChains: [X_LAYER.chainIdDecimal],
    rpcMap: { [X_LAYER.chainIdDecimal]: X_LAYER.rpcUrls[0] },
    showQrModal: true,
    metadata: {
      name: "ASML-X",
      description: "Trade real tokens on X Layer with an agent that cannot exceed your limit.",
      url: window.location.origin,
      icons: [`${window.location.origin}/favicon.svg`],
    },
  });

  await provider.connect();
  cached = provider as unknown as Eip1193;
  return cached;
}

/** Forget the session so a later Connect starts fresh rather than reusing a stale one. */
export async function disconnectWalletConnect(): Promise<void> {
  const p = cached as unknown as { disconnect?: () => Promise<void> } | null;
  try {
    await p?.disconnect?.();
  } finally {
    cached = null;
  }
}
