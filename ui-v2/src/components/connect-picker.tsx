/**
 * The wallet picker. OKX Wallet first, because this is an X Layer app.
 *
 * WHAT THIS REPLACES. Connect went straight to WalletConnect's generic modal, which leads with
 * Phantom and MetaMask. On a chain where OKB is the gas token and OKX operates the network, that
 * is the app announcing it does not know where it is. Worse, MetaMask needs X Layer added by hand
 * before anything works, so the default option was also the one most likely to fail.
 *
 * INSTALLED WALLETS ARE DETECTED, NOT LISTED. EIP-6963 asks every injected provider to announce
 * itself with a name and an icon, so two extensions can coexist. `window.ethereum` alone is
 * ambiguous the moment someone has both: whichever loaded last wins, which is how a person clicks
 * "OKX Wallet" and MetaMask opens.
 *
 * NOTHING IS OFFERED THAT IS NOT THERE. A wallet that is not installed appears under a separate
 * heading with an install link, never as a button that fails when pressed.
 */

import { useEffect, useState } from "react";
import { ExternalLink, Loader2, QrCode, Wallet as WalletIcon } from "lucide-react";
import { INSTALL_LINKS, discoverInjected, isOkx, rank, type Discovered } from "../lib/wallets";
import { cn } from "./ui";

export function ConnectPicker({
  onPick,
  onWalletConnect,
  busy,
}: {
  onPick: (w: Discovered) => void;
  onWalletConnect: () => void;
  busy: string | null;
}) {
  const [found, setFound] = useState<Discovered[] | null>(null);

  useEffect(() => {
    void discoverInjected().then((w) => setFound(rank(w)));
  }, []);

  if (found === null) {
    return (
      <div className="flex items-center gap-2 px-1 py-3 text-sm text-ink-faint">
        <Loader2 size={14} className="animate-spin" />
        Looking for wallets
      </div>
    );
  }

  return (
    <div className="grid gap-2">
      {found.map((w) => (
        <button
          key={w.id}
          type="button"
          onClick={() => onPick(w)}
          disabled={busy !== null}
          className={cn(
            "flex items-center gap-3 px-3 py-2.5 rounded border hair text-left",
            "hover:bg-raised disabled:opacity-50",
            // OKX first AND visually primary: it is the one that works here without setup.
            isOkx(w) && "bg-approved/10 border-approved/30",
          )}
        >
          {w.icon ? (
            <img src={w.icon} alt="" width={20} height={20} className="rounded shrink-0" />
          ) : (
            <WalletIcon size={18} className="text-ink-faint shrink-0" />
          )}
          <span className="text-sm text-ink flex-1">{w.name}</span>
          {isOkx(w) ? (
            <span className="text-xs text-approved shrink-0">works with X Layer</span>
          ) : (
            <span className="text-xs text-ink-faint shrink-0">installed</span>
          )}
          {busy === w.id ? <Loader2 size={13} className="animate-spin text-ink-faint" /> : null}
        </button>
      ))}

      <button
        type="button"
        onClick={onWalletConnect}
        disabled={busy !== null}
        className="flex items-center gap-3 px-3 py-2.5 rounded border hair text-left hover:bg-raised disabled:opacity-50"
      >
        <QrCode size={18} className="text-ink-faint shrink-0" />
        <span className="text-sm text-ink flex-1">Use a phone wallet</span>
        <span className="text-xs text-ink-faint shrink-0">scan a code</span>
        {busy === "walletconnect" ? (
          <Loader2 size={13} className="animate-spin text-ink-faint" />
        ) : null}
      </button>

      {found.length === 0 ? (
        <div className="mt-2 pt-3 border-t hair">
          <p className="text-xs text-ink-faint leading-relaxed">
            No wallet found in this browser. Scan with your phone above, or install one:
          </p>
          <div className="mt-2 grid gap-1.5">
            {INSTALL_LINKS.map((l) => (
              <a
                key={l.name}
                href={l.url}
                target="_blank"
                rel="noreferrer noopener"
                className="text-xs text-telemetry hover:underline inline-flex items-center gap-1"
              >
                {l.name}
                <ExternalLink size={10} />
                <span className="text-ink-faint">— {l.note}</span>
              </a>
            ))}
          </div>
        </div>
      ) : null}
    </div>
  );
}
