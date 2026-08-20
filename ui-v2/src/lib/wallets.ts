/**
 * Which wallets this app offers, and in what order.
 *
 * WHY THIS FILE EXISTS. Pressing Connect opened WalletConnect's generic modal, which leads with
 * Phantom and MetaMask. This is an X Layer product: OKB is the gas token, the chain is operated by
 * OKX, and OKX Wallet is the one most users here already have. Handing them a Solana wallet first
 * is the app telling them it does not know what chain it is on.
 *
 * DETECTED, NOT ASSUMED. Each entry knows how to find its own provider. An installed wallet is
 * offered as a one-click connect; one that is not installed is offered as a QR code through
 * WalletConnect, or as a link to install. Nothing is listed as available when it is not.
 *
 * EIP-6963 FIRST. The modern discovery standard announces every injected provider with its name
 * and icon, so several extensions can coexist. `window.ethereum` alone is ambiguous the moment a
 * user has two wallets: whichever loaded last wins, which is how someone clicks "OKX Wallet" and
 * MetaMask opens.
 */

import type { Eip1193 } from "./wallet";

export interface Discovered {
  id: string;
  name: string;
  icon?: string;
  provider: Eip1193;
}

interface Eip6963Detail {
  info: { uuid: string; name: string; icon: string; rdns: string };
  provider: Eip1193;
}

/**
 * Ask every injected wallet to announce itself, per EIP-6963.
 *
 * Resolves after a short window: the standard is an event exchange with no completion signal, so
 * a deadline is the only way to know the announcements have stopped.
 */
export function discoverInjected(timeoutMs = 350): Promise<Discovered[]> {
  return new Promise((resolve) => {
    if (typeof window === "undefined") return resolve([]);

    const found = new Map<string, Discovered>();
    const onAnnounce = (e: Event) => {
      const d = (e as CustomEvent<Eip6963Detail>).detail;
      if (!d?.info || !d.provider) return;
      found.set(d.info.rdns, {
        id: d.info.rdns,
        name: d.info.name,
        icon: d.info.icon,
        provider: d.provider,
      });
    };

    window.addEventListener("eip6963:announceProvider", onAnnounce);
    window.dispatchEvent(new Event("eip6963:requestProvider"));

    setTimeout(() => {
      window.removeEventListener("eip6963:announceProvider", onAnnounce);

      // FALLBACK for wallets that predate EIP-6963. OKX injects `window.okxwallet`, which is
      // unambiguous in a way `window.ethereum` is not.
      const w = window as unknown as {
        okxwallet?: Eip1193;
        ethereum?: Eip1193 & { isOkxWallet?: boolean; isMetaMask?: boolean };
      };
      if (w.okxwallet && !found.has("com.okex.wallet")) {
        found.set("com.okex.wallet", {
          id: "com.okex.wallet",
          name: "OKX Wallet",
          provider: w.okxwallet,
        });
      }
      if (w.ethereum && found.size === 0) {
        found.set("injected", {
          id: "injected",
          name: w.ethereum.isOkxWallet
            ? "OKX Wallet"
            : w.ethereum.isMetaMask
              ? "MetaMask"
              : "Browser wallet",
          provider: w.ethereum,
        });
      }

      resolve([...found.values()]);
    }, timeoutMs);
  });
}

/**
 * The order wallets are shown in.
 *
 * OKX first, deliberately and for a reason a user would agree with: this is an X Layer app, OKX
 * Wallet has X Layer configured out of the box, and every other wallet needs the network added
 * manually before anything works. Ordering by what actually works here is not favouritism.
 */
const PREFERRED = ["com.okex.wallet", "io.metamask", "com.trustwallet.app", "com.bitget.web3"];

/**
 * Is this OKX Wallet?
 *
 * MATCHED ON NAME OR rdns, NOT ON A GUESSED CONSTANT. The first version tested `id ===
 * "com.okex.wallet"`, a string written from memory. If OKX announces anything else, the check
 * silently fails: OKX drops to the bottom of the list with a generic label, which is exactly the
 * behaviour being fixed. A guessed identifier that produces a wrong ORDER rather than an error is
 * the same class of bug as the guessed API paths.
 *
 * The wallet's own announced name is the reliable signal, and the rdns is kept as a second route.
 */
export function isOkx(w: Discovered): boolean {
  return /okx|okex/i.test(w.name) || /okx|okex/i.test(w.id);
}

export function rank(wallets: Discovered[]): Discovered[] {
  return [...wallets].sort((a, b) => {
    // OKX first however it identifies itself, then the rest of the preference list.
    if (isOkx(a) !== isOkx(b)) return isOkx(a) ? -1 : 1;
    const ai = PREFERRED.indexOf(a.id);
    const bi = PREFERRED.indexOf(b.id);
    const av = ai === -1 ? PREFERRED.length : ai;
    const bv = bi === -1 ? PREFERRED.length : bi;
    return av - bv || a.name.localeCompare(b.name);
  });
}

/** Where to send someone who has no wallet at all. Official sources only. */
export const INSTALL_LINKS = [
  { name: "OKX Wallet", url: "https://www.okx.com/web3", note: "X Layer works out of the box" },
  { name: "MetaMask", url: "https://metamask.io/download/", note: "you will add X Layer manually" },
] as const;
