/**
 * Wallet connection surface, task 9.1.
 *
 * PATTERNS APPLIED (evidence/ui-study.md, with the citation each one comes from):
 *
 * - `orderbook-panel.tsx:151-153` two different sentences for two different situations, placed in
 *   the panel body where the data would have been. Every failure below renders its own specific
 *   sentence plus its own next action; there is no shared "something went wrong". That citation is
 *   also why the disconnected state is a sentence and not a spinner.
 * - `orderbook-panel.tsx:121-137` controls live in the labels they affect. The chain warning carries
 *   its own Switch button rather than sending the user to a settings panel.
 * - `config/layout.ts:10-14` `positions.disconnectedMinHeightPx: 180`, the constant this study
 *   singled out as the detail worth stealing: a region reserves LESS height when there is nothing to
 *   show. `CONNECT_MIN_HEIGHT_PX` below is the same idea, and it is a constant in `config/layout.ts`
 *   rather than a literal here, per task 5.2's magic-number audit.
 * - `orderbook-row.tsx:34` 12px `tabular-nums` rows at `py-0.5 px-2`, used for the address readout so
 *   a hex string is scannable rather than proportional.
 *
 * THE NAMED FAKE WIN for this task: "a Connect button that sets local state without touching a
 * provider." Every piece of state this component holds arrives from `lib/wallet.ts`, which gets it
 * from `eth_requestAccounts` and `eth_chainId`. There is no optimistic local set anywhere in the
 * file, and the gate greps for one.
 */

import { useCallback, useEffect, useState } from "react";
import {
  type ChainSpec,
  type WalletError,
  type WalletState,
  X_LAYER_TESTNET,
  connect as walletConnect,
  getProvider,
  readConnection,
  switchChain,
  watchWallet,
} from "../lib/wallet";
import { CONNECT_MIN_HEIGHT_PX } from "../config/layout";
import { mark } from "../lib/flow-timing";

function short(addr: string): string {
  return addr.length > 12 ? `${addr.slice(0, 6)}...${addr.slice(-4)}` : addr;
}

/** One button style, so the primary action looks the same wherever it appears. */
function Action({
  children,
  onClick,
  busy,
  testId,
}: {
  children: React.ReactNode;
  onClick: () => void;
  busy?: boolean;
  testId: string;
}) {
  return (
    <button
      type="button"
      data-testid={testId}
      onClick={onClick}
      disabled={busy}
      className="px-3 py-1.5 text-xs border hairline bg-[var(--fill-hover)] hover:bg-[var(--bg-raised)] disabled:opacity-60"
      style={{ color: "var(--text-strong)" }}
    >
      {busy ? "Waiting for your wallet..." : children}
    </button>
  );
}

/**
 * A failure with its cause AND its next action, never one without the other.
 * `WalletError.action` is a required field precisely so this component cannot render a dead end.
 */
function Failure({ error, retry }: { error: WalletError; retry: () => void }) {
  return (
    <div className="flex flex-col gap-1.5" data-testid="wallet-error" data-error-kind={error.kind}>
      <p className="text-xs" style={{ color: "var(--status-short)" }}>
        {error.message}
      </p>
      <p className="text-xs text-[var(--text-weak)]">{error.action}</p>
      {error.kind !== "no-provider" ? (
        <div>
          <Action testId="wallet-retry" onClick={retry}>
            Try again
          </Action>
        </div>
      ) : null}
    </div>
  );
}

export function Connect({
  expected = X_LAYER_TESTNET,
  onConnected,
}: {
  expected?: ChainSpec;
  onConnected?: (state: WalletState | null) => void;
}) {
  const [state, setState] = useState<WalletState | null>(null);
  const [error, setError] = useState<WalletError | null>(null);
  const [busy, setBusy] = useState(false);
  const [checked, setChecked] = useState(false);

  const publish = useCallback(
    (s: WalletState | null) => {
      setState(s);
      // TASK 10.1. Only a connection ON THE EXPECTED CHAIN counts: a wallet connected to the wrong
      // network cannot do anything here, and stamping it would credit the flow with a step the user
      // has not actually completed.
      if (s?.onExpectedChain) mark("connected");
      onConnected?.(s);
    },
    [onConnected],
  );

  // Read the EXISTING authorisation without prompting. `eth_accounts`, not `eth_requestAccounts`:
  // a page that opens a wallet popup on load is the behaviour 9.2's landing surface must not have.
  useEffect(() => {
    let live = true;
    void readConnection(expected).then((s) => {
      if (!live) return;
      publish(s);
      setChecked(true);
    });
    const stop = watchWallet(expected, (s) => {
      if (live) publish(s);
    });
    return () => {
      live = false;
      stop();
    };
  }, [expected, publish]);

  const doConnect = useCallback(async () => {
    setBusy(true);
    setError(null);
    const r = await walletConnect(expected);
    setBusy(false);
    if (r.ok) publish(r.state);
    else setError(r.error);
  }, [expected, publish]);

  const doSwitch = useCallback(async () => {
    setBusy(true);
    setError(null);
    const r = await switchChain(expected);
    setBusy(false);
    if (!r.ok) {
      setError(r.error);
      return;
    }
    publish(await readConnection(expected));
  }, [expected, publish]);

  const body = () => {
    if (error) return <Failure error={error} retry={error.kind === "wrong-chain" ? doSwitch : doConnect} />;

    if (!checked) {
      // Distinguishable from "not connected", per task 4.7's rule that a loading state must never be
      // confusable with a real answer.
      return <p className="text-xs text-[var(--text-weak)]">Checking for a wallet...</p>;
    }

    if (!getProvider()) {
      return (
        <Failure
          error={{
            kind: "no-provider",
            message: "No wallet found in this browser.",
            action: "Install OKX Wallet or MetaMask, then reload this page.",
          }}
          retry={doConnect}
        />
      );
    }

    if (!state) {
      return (
        <div className="flex flex-col gap-1.5">
          <Action testId="wallet-connect" onClick={() => void doConnect()} busy={busy}>
            Connect wallet
          </Action>
          <p className="text-xs text-[var(--text-weak)]">
            Read-only until you deposit. You can withdraw at any time.
          </p>
        </div>
      );
    }

    if (!state.onExpectedChain) {
      return (
        <div className="flex flex-col gap-1.5" data-testid="wrong-chain">
          <p className="num text-2xs text-[var(--text-weak)]">{short(state.address)}</p>
          <p className="text-xs" style={{ color: "var(--status-short)" }}>
            Wrong network: your wallet is on chain {state.chainIdDecimal}.
          </p>
          <p className="text-xs text-[var(--text-weak)]">
            {expected.chainName} is chain {expected.chainIdDecimal}.
          </p>
          <div>
            <Action testId="wallet-switch" onClick={() => void doSwitch()} busy={busy}>
              Switch to {expected.chainName}
            </Action>
          </div>
        </div>
      );
    }

    return (
      <div className="flex flex-col gap-1" data-testid="wallet-connected">
        <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-2 py-0.5 border-b hairline">
          <span className="text-2xs text-[var(--text-weak)]">Address</span>
          <span className="num text-2xs" data-testid="wallet-address" data-address={state.address}>
            {short(state.address)}
          </span>
        </div>
        <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-2 py-0.5">
          <span className="text-2xs text-[var(--text-weak)]">Network</span>
          <span className="num text-2xs" data-testid="wallet-chain" data-chain={state.chainIdDecimal}>
            {expected.chainName} ({state.chainIdDecimal})
          </span>
        </div>
      </div>
    );
  };

  return (
    <div
      className="flex flex-col justify-center px-2 py-2"
      style={{ minHeight: `${CONNECT_MIN_HEIGHT_PX}px` }}
      data-testid="connect-surface"
    >
      {body()}
    </div>
  );
}
