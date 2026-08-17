/**
 * Defaults, activation, and the exit controls. Tasks 9.3, 9.4, 9.5 and 9.9.
 *
 * PATTERNS APPLIED (evidence/ui-study.md, each with its citation):
 *
 * - `orderbook-panel.tsx:121-137` controls live in the labels they affect: Withdraw sits with the
 *   balance it returns, Pause sits with the agent state it stops. Neither is in a toolbar.
 * - `orderbook-row.tsx:34` 12px `tabular-nums` rows at `py-0.5 px-2` with hairline separators, so
 *   the limits column aligns and can be scanned rather than read.
 * - `orderbook-panel.tsx:151-153` distinct sentences for distinct situations. A failed chain read
 *   never renders as a zero.
 * - `config/layout.ts:10-14` sizes as named constants rather than literals in the component.
 *
 * TASK 9.3, SMART DEFAULTS. Every limit here is read from `data/limits.json`, which is WRITTEN BY
 * THE RUST CRATE (`cargo test -p risk-engine export_conservative_defaults_for_the_ui`) from
 * `Limits::conservative_testnet`. Nothing is retyped in TypeScript, so the screen cannot drift from
 * the engine. Each limit shows what it protects against, and that sentence lives in the generated
 * file beside the number rather than here.
 *
 * TASK 9.4, THREE INTERACTIONS. From a connected wallet with NO prior allowance, the path is one
 * app click, one signature, one transaction confirmation. The earlier version of this file was four
 * (Approve, confirm, Deposit, confirm) and measured as one only because the test account already
 * held an allowance from Phase 7, which is not a cold user. ADR-017 records why ERC-2612 permit was
 * chosen over the alternatives, including the one that would have shortened the path by asking for
 * an unbounded allowance.
 *
 * Wallet confirmations are counted, not just app clicks. Counting only in-app clicks is this task's
 * named fake win.
 *
 * TASK 9.5, THE EXIT. Pause and Withdraw are rendered unconditionally whenever there is a position,
 * BEFORE the dashboard detail in DOM order, because a user's first question is "can I get out". The
 * withdraw control shows the exact amount returning before it is pressed.
 *
 * TASK 9.9, FEE DISCLOSURE. The fee is read from `FeeCollector.feeBps()` live. There is no literal
 * percentage anywhere in this file, and task 5.2's magic-number audit covers it.
 */

import { useCallback, useEffect, useState } from "react";
import { Panel, PanelError } from "./primitives";
import type { WalletState } from "../lib/wallet";
import {
  type VaultAddresses,
  type VaultPosition,
  encode,
  formatWei,
  permitTypedData,
  readPermitInputs,
  splitSignature,
} from "../lib/vault";
import { refreshPosition, subscribePosition } from "../lib/position-store";
import { type LimitsDoc, loadLimits } from "../lib/manifest";
import { type FriendlyError, friendlyError } from "../lib/revert";
import { mark } from "../lib/flow-timing";


/** 1e12 wei per micro unit: micro is 1e6 scaled, the token is 1e18. */
const WEI_PER_MICRO = 1_000_000_000_000n;

async function send(provider: unknown, to: string, data: string): Promise<string> {
  const p = provider as { request(a: { method: string; params?: unknown[] }): Promise<unknown> };
  return (await p.request({
    method: "eth_sendTransaction",
    params: [{ to, data }],
  })) as string;
}

export function Activate({
  wallet,
  addresses,
  rpcUrl,
}: {
  wallet: WalletState;
  addresses: VaultAddresses;
  rpcUrl: string;
}) {
  const [limits, setLimits] = useState<LimitsDoc | null>(null);
  const [limitsError, setLimitsError] = useState<string | null>(null);
  const [pos, setPos] = useState<VaultPosition | null>(null);
  const [posError, setPosError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [txError, setTxError] = useState<FriendlyError | null>(null);
  const [lastTx, setLastTx] = useState<string | null>(null);

  useEffect(() => {
    void loadLimits()
      .then((d) => {
        setLimits(d);
        // TASK 10.1: the defaults are on screen and the user could act on them.
        mark("defaults_seen");
      })
      .catch((e) => setLimitsError(String(e.message ?? e)));
  }, []);

  // Subscribes to the SHARED poll. ExitBar configures it; this component only reads. A failed chain
  // read is still NOT a zero position (task 9.7's counter): the store keeps the last known position
  // and reports the error alongside it, so a consumer can show both.
  useEffect(
    () =>
      subscribePosition((s) => {
        setPos(s.position);
        setPosError(s.position === null ? s.error : null);
      }),
    [],
  );

  const refresh = useCallback(() => refreshPosition(), []);

  const orderLimit = limits?.limits.find((l) => l.key === "maxOrderNotional");
  const depositWei = orderLimit?.micro ? BigInt(orderLimit.micro) * WEI_PER_MICRO : 0n;

  const run = useCallback(
    async (label: string, to: string, data: string) => {
      setBusy(label);
      setTxError(null);
      if (label === "deposit") mark("deposit_submitted");
      try {
        const hash = await send(window.ethereum, to, data);
        setLastTx(hash);
        if (label === "deposit") mark("activated");
        await refresh();
      } catch (e) {
        // Decoded, not dumped. A raw `0xcf479181...` names the cause perfectly and helps
        // nobody; task 9.8 requires the specific cause AND the specific next action.
        setTxError(friendlyError(e));
      } finally {
        setBusy(null);
      }
    },
    [refresh],
  );

  /**
   * ONE CLICK: sign a permit, then deposit, in a single transaction.
   *
   * This is task 9.4's whole point. The old path was Approve, confirm, Deposit, confirm: four
   * interactions for a cold user. Here the approval is a SIGNATURE rather than a transaction, so the
   * count is click, sign, confirm.
   *
   * The permitted value is exactly the deposit amount and it is consumed in the same transaction, so
   * no allowance is left standing afterwards. ADR-017 records why the alternative, asking for an
   * unbounded allowance, was rejected: it would trade the user's custody position for a shorter path.
   */
  const activateWithPermit = useCallback(async () => {
    setBusy("deposit");
    setTxError(null);
    // Submitted, not yet confirmed. The gap between this and `activated` is the chain's
    // time rather than the product's, and keeping them separate is what makes the
    // headline number honest about which is which.
    mark("deposit_submitted");
    try {
      const { nonce, name } = await readPermitInputs(
        wallet.address,
        addresses.tQUOTE,
        rpcUrl,
      );
      // Thirty minutes. Long enough that a user reading the wallet prompt does not time out, short
      // enough that a signature left in a mempool does not stay valid indefinitely.
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 1800);

      const typed = permitTypedData({
        tokenName: name,
        tokenAddress: addresses.tQUOTE,
        chainId: wallet.chainIdDecimal,
        owner: wallet.address,
        spender: addresses.agentVault,
        value: depositWei,
        nonce,
        deadline,
      });

      const p = window.ethereum as {
        request(a: { method: string; params?: unknown[] }): Promise<unknown>;
      };
      const sig = (await p.request({
        method: "eth_signTypedData_v4",
        params: [wallet.address, JSON.stringify(typed)],
      })) as string;

      const { v, r, s } = splitSignature(sig);
      const hash = await send(
        window.ethereum,
        addresses.agentVault,
        encode.depositWithPermit(depositWei, depositWei, deadline, v, r, s),
      );
      setLastTx(hash);
      mark("activated");
      await refresh();
    } catch (e) {
      setTxError(friendlyError(e));
    } finally {
      setBusy(null);
    }
  }, [wallet, addresses, rpcUrl, depositWei, refresh]);

  if (limitsError) {
    return (
      <Panel title="Your limits" meta="defaults">
        <PanelError source="data/limits.json" reason={limitsError} />
      </Panel>
    );
  }

  // `null` while the chain read is in flight, and that is DELIBERATELY not collapsed to a boolean.
  //
  // An earlier version wrote `pos !== null && pos.allowanceWei < depositWei`, which is `false` both
  // when an allowance exists AND when nothing has been read yet. The button therefore rendered
  // `data-path="allowance"` before any read completed and would have taken the plain-deposit path
  // against a zero allowance, reverting. A tri-state says "I do not know yet", and the button is
  // disabled until it becomes a real answer.
  const needsApproval: boolean | null = pos === null ? null : pos.allowanceWei < depositWei;
  const positionKnown = pos !== null;
  const hasPosition = pos !== null && pos.balanceWei > 0n;

  return (
    <div className="flex flex-col gap-2">
      {/* EXIT FIRST IN DOM ORDER, task 9.5. */}
      {hasPosition ? (
        <Panel title="Your money" meta={pos.paused ? "agent paused" : "agent active"}>
          <div className="flex flex-col">
            <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-2 py-0.5 border-b hairline">
              <span className="text-2xs text-[var(--text-weak)]">In the vault</span>
              <span className="num text-2xs" data-testid="vault-balance">
                {formatWei(pos.balanceWei)} tQUOTE
              </span>
            </div>
            <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-2 py-0.5 border-b hairline">
              <span className="text-2xs text-[var(--text-weak)]">In flight, not withdrawable yet</span>
              <span className="num text-2xs">{formatWei(pos.committedWei)} tQUOTE</span>
            </div>

            <div className="flex gap-2 px-2 py-2">
              {/* The exact amount is on the control BEFORE it is pressed, task 9.5. */}
              <button
                type="button"
                data-testid="withdraw"
                disabled={busy !== null || pos.withdrawableWei === 0n}
                onClick={() =>
                  void run("withdraw", addresses.agentVault, encode.withdrawAll())
                }
                className="px-3 py-1.5 text-xs border hairline bg-[var(--fill-hover)] hover:bg-[var(--bg-raised)] disabled:opacity-60"
                style={{ color: "var(--text-strong)" }}
              >
                {busy === "withdraw"
                  ? "Withdrawing..."
                  : `Withdraw ${formatWei(pos.withdrawableWei)} tQUOTE`}
              </button>

              <button
                type="button"
                data-testid="pause"
                disabled={busy !== null}
                onClick={() =>
                  void run("pause", addresses.agentVault, encode.setPaused(!pos.paused))
                }
                className="px-3 py-1.5 text-xs border hairline bg-[var(--fill-hover)] hover:bg-[var(--bg-raised)] disabled:opacity-60"
                style={{ color: "var(--text-strong)" }}
              >
                {busy === "pause" ? "..." : pos.paused ? "Resume agent" : "Pause agent"}
              </button>
            </div>

            <p className="px-2 pb-2 text-3xs text-[var(--text-weak)]">
              Pausing stops the agent. It never blocks withdrawal: you can take your money out while
              paused.
            </p>
          </div>
        </Panel>
      ) : null}

      <Panel
        title="Your limits"
        meta={limits ? "defaults, ready to run" : "loading"}
      >
        {!limits ? (
          <p className="px-2 py-3 text-xs text-[var(--text-weak)]">Loading the shipped defaults...</p>
        ) : (
          <div className="flex flex-col">
            {limits.limits.map((l) => (
              <div key={l.key} className="px-2 py-1 border-b hairline last:border-b-0">
                <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2">
                  <span className="text-2xs" style={{ color: "var(--text-strong)" }}>
                    {l.label}
                  </span>
                  <span className="num text-2xs" data-testid={`limit-${l.key}`}>
                    {l.micro !== undefined
                      ? `${l.micro / limits.microPerUnit} tQUOTE`
                      : String(l.count)}
                  </span>
                </div>
                <p className="text-3xs text-[var(--text-weak)]">{l.protects}</p>
              </div>
            ))}
            <p className="px-2 py-1.5 text-3xs text-[var(--text-weak)]">
              These are the shipped defaults, written by the risk engine itself ({limits.source}).
              You run under them without changing anything.
            </p>
          </div>
        )}
      </Panel>

      <Panel title="Activate" meta={pos ? `${pos.feeBps} bps usage fee` : "reading fee"}>
        {posError ? (
          <PanelError source="AgentVault, read from chain" reason={posError} />
        ) : (
          <div className="flex flex-col gap-2 px-2 py-2">
            {/* TASK 9.9: the fee, in basis points AND in plain words, read live from the deployed
                FeeCollector. No literal percentage exists in this file. */}
            <p className="text-xs text-[var(--text-weak)]" data-testid="fee-disclosure">
              {pos
                ? `Fee: ${pos.feeBps} basis points of each executed trade, which is ${pos.feeBps} tQUOTE on every 10,000 traded. Charged only when a trade executes, never on your deposit and never on withdrawal.`
                : "Reading the fee from the contract..."}
            </p>

            {/* ONE BUTTON. Which path it takes is decided by what the chain already says, not by
                a preference: with a sufficient allowance the plain deposit needs no signature, so
                use it; otherwise permit turns the approval into a signature. Either way the user
                presses this once. */}
            <div className="flex gap-2">
              <button
                type="button"
                data-testid="deposit-activate"
                disabled={busy !== null || depositWei === 0n || !positionKnown}
                onClick={() =>
                  needsApproval === true
                    ? void activateWithPermit()
                    : void run(
                        "deposit",
                        addresses.agentVault,
                        encode.deposit(depositWei, depositWei),
                      )
                }
                data-path={needsApproval === null ? "unknown" : needsApproval ? "permit" : "allowance"}
                className="px-3 py-1.5 text-xs border hairline bg-[var(--fill-hover)] hover:bg-[var(--bg-raised)] disabled:opacity-60"
                style={{ color: "var(--text-strong)" }}
              >
                {busy === "deposit"
                  ? "Activating..."
                  : !positionKnown
                    ? "Reading your position..."
                    : `Deposit ${formatWei(depositWei)} and activate`}
              </button>
            </div>

            {needsApproval === true ? (
              <p className="text-3xs text-[var(--text-weak)]">
                You will be asked to sign once, then confirm one transaction. The signature approves
                exactly {formatWei(depositWei)} tQUOTE, and it is used up by the same transaction.
              </p>
            ) : null}

            {txError ? (
              <div data-testid="tx-error" data-error-name={txError.errorName ?? "unknown"}>
                <p className="text-xs" style={{ color: "var(--status-short)" }}>
                  {txError.message}
                </p>
                <p className="text-xs text-[var(--text-weak)]">{txError.action}</p>
                {txError.raw ? (
                  <p className="num text-3xs text-[var(--text-weak)] break-all opacity-70">
                    {txError.raw}
                  </p>
                ) : null}
              </div>
            ) : null}

            {lastTx ? (
              <p className="num text-3xs text-[var(--text-weak)]" data-testid="last-tx">
                {lastTx}
              </p>
            ) : null}
          </div>
        )}
      </Panel>
    </div>
  );
}
