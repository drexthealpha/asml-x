/**
 * The persistent exit bar, task 9.5.
 *
 * WHY THIS IS A SEPARATE BAR AND NOT A PANEL. The task says the controls must be "visible on every
 * screen of the personal view", and its PASS condition says "in the DOM and visible at every ROUTE".
 * Those two readings differ, and the stricter one is the one worth building: a user who has money in
 * the vault and is reading the Risk tab should not have to navigate anywhere to get out. So Pause and
 * Withdraw live in the chrome, above the view switch, and every route inherits them.
 *
 * THINKING: #22 inversion (the user's first fear is not "will it make money", it is "can I get my
 * money back"), #29 margin-of-safety, #53 phenomenological.
 *
 * PATTERNS APPLIED (evidence/ui-study.md):
 * - `config/layout.ts:32-40` chrome heights are Tailwind classes held as constants with the combined
 *   offset precomputed in a comment, never recomputed inline. `EXIT_BAR_CLASS` follows that, and
 *   `CHROME_REM` in App.tsx is updated by the same arithmetic rather than by guessing.
 * - `orderbook-panel.tsx:121-137` controls live in the labels they affect. The withdraw button
 *   carries the exact amount it will return, so the label IS the disclosure.
 * - `orderbook-row.tsx:34` 12px `tabular-nums` for the amount, so it reads as a figure.
 *
 * IT RENDERS NOTHING WHEN THERE IS NOTHING TO EXIT. A bar that is always present but usually
 * disabled trains people to ignore it, and it would occupy chrome height on the landing screen where
 * task 9.2 measures the primary action's position. Absent when there is no position, present the
 * moment there is.
 */

import { useCallback, useEffect, useState } from "react";
import { EXIT_BAR_CLASS } from "../config/layout";
import { loadManifest, pickAddress } from "../lib/manifest";
import { type FriendlyError, friendlyError } from "../lib/revert";
import { X_LAYER_TESTNET, readConnection, watchWallet } from "../lib/wallet";
import type { WalletState } from "../lib/wallet";
import { type VaultAddresses, type VaultPosition, encode, formatWei } from "../lib/vault";
import {
  configurePosition,
  refreshPosition,
  subscribePosition,
} from "../lib/position-store";


export function ExitBar({ onVisible }: { onVisible?: (v: boolean) => void }) {
  const [wallet, setWallet] = useState<WalletState | null>(null);
  const [addresses, setAddresses] = useState<VaultAddresses | null>(null);
  const [rpcUrl, setRpcUrl] = useState<string>(X_LAYER_TESTNET.rpcUrls[0]);
  const [pos, setPos] = useState<VaultPosition | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<FriendlyError | null>(null);

  useEffect(() => {
    void loadManifest()
      .then((m) => {
        const agentVault = pickAddress(m, "AgentVault");
        const tQUOTE = pickAddress(m, "MockERC20 tQUOTE");
        const feeCollector = pickAddress(m, "FeeCollector");
        if (agentVault && tQUOTE && feeCollector) {
          setAddresses({ agentVault, tQUOTE, feeCollector });
        }
        if (m.rpc_url) setRpcUrl(m.rpc_url);
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    let live = true;
    void readConnection(X_LAYER_TESTNET).then((s) => live && setWallet(s));
    const stop = watchWallet(X_LAYER_TESTNET, (s) => live && setWallet(s));
    return () => {
      live = false;
      stop();
    };
  }, []);

  // ONE shared poll for the whole page. This component used to run its own, and two independent
  // seven-call polls at five-second intervals got the public RPC to refuse connections. Because a
  // failed read is swallowed, the symptom was this bar silently never appearing.
  useEffect(() => {
    configurePosition(
      wallet?.onExpectedChain ? wallet.address : null,
      addresses,
      addresses ? rpcUrl : null,
    );
  }, [wallet, addresses, rpcUrl]);

  // The error is tracked as well as the position. Keeping the controls during an outage is
  // deliberate; keeping them WITHOUT saying the data is stale is not.
  const [stale, setStale] = useState<string | null>(null);
  useEffect(
    () =>
      subscribePosition((s) => {
        setPos(s.position);
        setStale(s.error);
      }),
    [],
  );

  const refresh = useCallback(() => refreshPosition(), []);

  const run = useCallback(
    async (label: string, data: string) => {
      if (!addresses) return;
      setBusy(label);
      setError(null);
      try {
        const p = window.ethereum as {
          request(a: { method: string; params?: unknown[] }): Promise<unknown>;
        };
        await p.request({
          method: "eth_sendTransaction",
          params: [{ to: addresses.agentVault, data }],
        });
        await refresh();
      } catch (e) {
        setError(friendlyError(e));
      } finally {
        setBusy(null);
      }
    },
    [addresses, refresh],
  );

  const visible = pos !== null && pos.balanceWei > 0n;

  // Reported UPWARD rather than measured by App from a ref: this component already knows, and a ref
  // measurement would race the very render that produced the element.
  useEffect(() => {
    onVisible?.(visible);
  }, [visible, onVisible]);

  // Nothing to exit, nothing to render.
  if (!visible || !pos) return null;

  return (
    // `overflow-hidden` below is a BACKSTOP, not the fix. The causes were removed above (the label
    // and balance are hidden under 640px, and the buttons cannot wrap). This only ensures a future
    // label cannot silently push content out of the bar and into the tab strip again.
    <div
      data-testid="exit-bar"
      className={`${EXIT_BAR_CLASS} shrink-0 flex items-center gap-2 px-2 border-b hairline bg-[var(--bg-raised)] overflow-hidden`}
    >
      {/* Label and balance are hidden below 640px: both are duplicated in the personal view,
          and at 390px they pushed the CONTROLS into the tab strip above. The controls are
          what task 9.5 requires everywhere; the commentary is not. */}
      <span className="hidden sm:inline text-3xs uppercase tracking-wider text-[var(--text-weak)]">
        Your money
      </span>
      <span className="hidden sm:inline num text-2xs" data-testid="exit-balance">
        {formatWei(pos.balanceWei)} tQUOTE
      </span>

      <div className="flex-1" />

      {error ? (
        <span
          data-testid="exit-error"
          data-error-name={error.errorName ?? "unknown"}
          className="text-3xs truncate max-w-[24rem]"
          style={{ color: "var(--status-short)" }}
          title={`${error.message} ${error.action}`}
        >
          {error.message} {error.action}
        </span>
      ) : null}

      {/* STALE DATA IS SAID OUT LOUD. The controls and the figure stay, because removing them during
          an outage takes the exit away at the worst moment. But a number that has quietly stopped
          updating invites a decision on stale data, so the warning names the cause and the action. */}
      {stale && !error ? (
        <span
          data-testid="stale-warning"
          className="text-3xs truncate max-w-[20rem]"
          style={{ color: "var(--status-short)" }}
          title={stale}
        >
          Not updating: cannot reach the chain. The figure below is the last confirmed one. Check your
          connection; it will refresh by itself.
        </span>
      ) : null}

      {/* The exact amount is on the control BEFORE it is pressed. No confirmation dialog: the task
          asks for one click each and no confirmation maze, and the amount in the label is the
          disclosure a confirmation step would otherwise carry. */}
      <button
        type="button"
        data-testid="exit-withdraw"
        disabled={busy !== null || pos.withdrawableWei === 0n}
        onClick={() => void run("withdraw", encode.withdrawAll())}
        className="px-2 py-0.5 text-2xs leading-none whitespace-nowrap border hairline hover:bg-[var(--fill-hover)] disabled:opacity-60"
        style={{ color: "var(--text-strong)" }}
      >
        {busy === "withdraw" ? "Withdrawing..." : `Withdraw ${formatWei(pos.withdrawableWei, 2)}`}
      </button>

      <button
        type="button"
        data-testid="exit-pause"
        disabled={busy !== null}
        onClick={() => void run("pause", encode.setPaused(!pos.paused))}
        className="px-2 py-0.5 text-2xs leading-none whitespace-nowrap border hairline hover:bg-[var(--fill-hover)] disabled:opacity-60"
        style={{ color: pos.paused ? "var(--status-info)" : "var(--text-strong)" }}
      >
        {busy === "pause" ? "..." : pos.paused ? "Resume" : "Pause"}
      </button>
    </div>
  );
}
