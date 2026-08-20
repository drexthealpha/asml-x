/**
 * THE LIMIT CONTROL. Task 1, and the reason this product exists.
 *
 * WHAT WAS WRONG. Setting a limit was a text field buried in the deposit form, in the sidebar of
 * the Trade tab, visible only after connecting a wallet. The single promise the whole system makes
 * was a half-visible input behind a connection step. The promise is the reason to connect, so it
 * has to come first.
 *
 * WHAT THIS DOES, all against the deployed AgentVault on chain 196:
 *   reads   maxNotional(you)  balanceOf(you)  committed(you)  paused(you)
 *   writes  setMaxNotional(uint256)   setPaused(bool)
 *
 * TIGHTEN ONLY, ENFORCED BEFORE THE SIGNATURE. The slider cannot travel above the current cap and
 * the submit path refuses a raise with a reason. Letting someone pay gas to discover a rule is a
 * worse way to teach it than saying so.
 *
 * PAUSE IS PER DEPOSITOR AND DOES NOT BLOCK WITHDRAWAL. `AgentVault.sol:218` states withdrawal is
 * deliberately not gated on `paused`. The pause control says so on screen, because that is the
 * property a person is trusting when they press it.
 */

import { useCallback, useEffect, useState } from "react";
import {
  AlertCircle,
  ArrowDownToLine,
  CheckCircle2,
  ExternalLink,
  Loader2,
  Lock,
  Pause,
  Play,
  ShieldCheck,
} from "lucide-react";
import {
  EXPLORER_TX,
  decodeRevert,
  fromUnits,
  provider,
  readWallet,
  setMaxNotional,
  setPaused,
  tokenDecimals,
  vaultCommitted,
  vaultPaused,
  vaultPosition,
  withdrawAll,
  type Wallet,
} from "../lib/wallet";
import { loadChain, type Chain, type Feed } from "../lib/feed";
import { Badge, Card, cn } from "./ui";

interface Position {
  balance: bigint;
  cap: bigint;
  committed: bigint | null;
  paused: boolean | null;
  decimals: number;
}

export function LimitControl({ onNeedWallet }: { onNeedWallet?: () => void }) {
  const [chain, setChain] = useState<Feed<Chain>>({ state: "loading" });
  const [wallet, setWallet] = useState<Wallet | null>(null);
  const [pos, setPos] = useState<Position | null>(null);
  const [pct, setPct] = useState(100);
  const [busy, setBusy] = useState<string | null>(null);
  const [tx, setTx] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    void loadChain().then(setChain);
    void readWallet().then(setWallet);
    const p = provider();
    const onChange = () => void readWallet().then(setWallet);
    p?.on?.("accountsChanged", onChange);
    p?.on?.("chainChanged", onChange);
    return () => {
      p?.removeListener?.("accountsChanged", onChange);
      p?.removeListener?.("chainChanged", onChange);
    };
  }, []);

  const vaultAddr =
    chain.state === "ready"
      ? (chain.value.deployments.find((d) => d.name === "AgentVault")?.address ?? null)
      : null;
  const assetAddr =
    chain.state === "ready"
      ? (chain.value.deployments.find((d) => d.name === "aQUOTE")?.address ??
        chain.value.deployments.find((d) => d.name === "MockERC20 tQUOTE")?.address ??
        null)
      : null;

  /** Read everything from the chain. Called after every write, never assumed. */
  const refresh = useCallback(async () => {
    if (!wallet?.onXLayer || !vaultAddr || !assetAddr) return;
    try {
      const [decimals, p, committed, paused] = await Promise.all([
        tokenDecimals(assetAddr),
        vaultPosition(vaultAddr, wallet.address),
        vaultCommitted(vaultAddr, wallet.address),
        vaultPaused(vaultAddr, wallet.address),
      ]);
      setPos({ balance: p.balance, cap: p.maxNotional, committed, paused, decimals });
      setPct(100);
    } catch (e) {
      setErr(decodeRevert(e));
    }
  }, [wallet, vaultAddr, assetAddr]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  // The proposed cap: a percentage of the current one, so it can only ever go down.
  const proposed = pos ? (pos.cap * BigInt(Math.round(pct * 100))) / 10000n : 0n;
  const wouldRaise = pos ? proposed > pos.cap : false;
  const unchanged = pos ? proposed === pos.cap : true;

  const doTighten = async () => {
    if (!wallet || !vaultAddr || !pos) return;
    // REFUSED BEFORE THE SIGNATURE. Paying gas to be told a rule is a worse way to learn it.
    if (wouldRaise) {
      setErr("A limit can only be lowered. Raising it is not something this contract allows.");
      return;
    }
    setBusy("tighten");
    setErr(null);
    setTx(null);
    try {
      const hash = await setMaxNotional(wallet.address, vaultAddr, proposed);
      setTx(hash);
      setTimeout(() => void refresh(), 3000);
    } catch (e) {
      setErr(decodeRevert(e));
    } finally {
      setBusy(null);
    }
  };

  const doPause = async (next: boolean) => {
    if (!wallet || !vaultAddr) return;
    setBusy("pause");
    setErr(null);
    setTx(null);
    try {
      const hash = await setPaused(wallet.address, vaultAddr, next);
      setTx(hash);
      setTimeout(() => void refresh(), 3000);
    } catch (e) {
      setErr(decodeRevert(e));
    } finally {
      setBusy(null);
    }
  };

  const doWithdrawAll = async () => {
    if (!wallet || !vaultAddr) return;
    setBusy("withdraw");
    setErr(null);
    setTx(null);
    try {
      const hash = await withdrawAll(wallet.address, vaultAddr);
      setTx(hash);
      setTimeout(() => void refresh(), 3000);
    } catch (e) {
      setErr(decodeRevert(e));
    } finally {
      setBusy(null);
    }
  };

  // ---------------------------------------------------------------- states

  if (!wallet) {
    return (
      <Card title="Your limit">
        <div className="px-4 py-5">
          <p className="text-sm text-ink">Connect a wallet to see and change your limit.</p>
          <p className="text-xs text-ink-faint mt-1 leading-relaxed">
            The limit lives on chain against your address. Nothing here can read it until it knows
            who you are.
          </p>
          {onNeedWallet ? (
            <button
              type="button"
              onClick={onNeedWallet}
              className="mt-3 px-4 py-2.5 rounded text-sm font-medium bg-approved text-bg hover:bg-approved/90"
            >
              Connect a wallet
            </button>
          ) : null}
        </div>
      </Card>
    );
  }

  if (!wallet.onXLayer) {
    return (
      <Card title="Your limit">
        <div className="px-4 py-5">
          <p className="text-sm text-ink">Your wallet is on chain {wallet.chainId}.</p>
          <p className="text-xs text-ink-faint mt-1">This runs on X Layer, chain 196.</p>
        </div>
      </Card>
    );
  }

  if (!pos) {
    return (
      <Card title="Your limit">
        <div className="flex items-center gap-2 px-4 py-6 text-sm text-ink-faint">
          <Loader2 size={14} className="animate-spin" />
          Reading your limit from the chain
        </div>
      </Card>
    );
  }

  const dec = pos.decimals;
  const hasCap = pos.cap > 0n;

  return (
    <Card
      title="Your limit"
      meta={
        <span className="num text-xs text-ink-faint">
          {wallet.address.slice(0, 6)}…{wallet.address.slice(-4)}
        </span>
      }
    >
      {/* The number, large, because it is the answer to the only question that matters. */}
      <div className="px-4 py-5 border-b hair">
        <div className="text-xs text-ink-faint">The most the agent may risk in one trade</div>
        <div className="num text-3xl text-ink mt-1">{fromUnits(pos.cap, dec)}</div>
        <p className="text-xs text-ink-faint mt-2 leading-relaxed">
          {hasCap
            ? `At this cap the largest single trade the agent can open against your deposit is ${fromUnits(pos.cap, dec)}. It cannot exceed that, and nothing can raise it but you lowering it further.`
            : "You have not set a cap yet. You will set one in the same transaction as your first deposit."}
        </p>
      </div>

      {/* Position, read from the chain. */}
      <div className="grid grid-cols-2 border-b hair">
        <div className="px-4 py-3 border-r hair">
          <div className="text-xs text-ink-faint">In the vault</div>
          <div className="num text-lg text-ink mt-0.5">{fromUnits(pos.balance, dec)}</div>
        </div>
        <div className="px-4 py-3">
          <div className="text-xs text-ink-faint">Committed to open trades</div>
          <div className="num text-lg text-ink mt-0.5">
            {pos.committed === null ? "—" : fromUnits(pos.committed, dec)}
          </div>
        </div>
      </div>

      {/* THE CONTROL. */}
      {hasCap ? (
        <div className="px-4 py-4 border-b hair">
          <label className="block">
            <span className="text-xs text-ink-faint">Lower it to</span>
            <div className="mt-2 flex items-baseline gap-3">
              <span className="num text-xl text-approved">{fromUnits(proposed, dec)}</span>
              <span className="text-xs text-ink-faint">{pct}% of your current limit</span>
            </div>
            <input
              type="range"
              min={1}
              max={100}
              value={pct}
              onChange={(e) => setPct(Number(e.target.value))}
              aria-label="New limit as a percentage of the current one"
              className="w-full mt-3 accent-[var(--color-approved)]"
            />
          </label>

          <div className="mt-2 flex gap-2">
            {[50, 25, 10].map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => setPct(p)}
                className={cn(
                  "px-2.5 py-1 rounded border hair text-xs",
                  pct === p ? "bg-raised text-ink" : "text-ink-faint hover:text-ink",
                )}
              >
                {p}%
              </button>
            ))}
          </div>

          <button
            type="button"
            onClick={() => void doTighten()}
            disabled={busy !== null || unchanged || wouldRaise}
            className="mt-3 w-full inline-flex items-center justify-center gap-2 px-4 py-2.5 rounded text-sm font-medium bg-approved text-bg hover:bg-approved/90 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {busy === "tighten" ? <Loader2 size={14} className="animate-spin" /> : <Lock size={14} />}
            {unchanged ? "Move the slider to lower it" : `Lower limit to ${fromUnits(proposed, dec)}`}
          </button>

          <p className="text-xs text-ink-faint mt-2 leading-relaxed">
            The slider does not go above your current limit, because the contract has no path to
            raise one.
          </p>
        </div>
      ) : null}

      {/* Pause, with the property it guarantees stated next to it. */}
      <div className="px-4 py-4 border-b hair">
        <div className="flex items-center justify-between gap-3">
          <div className="min-w-0">
            <div className="text-sm text-ink">
              {pos.paused === null
                ? "Agent status unavailable"
                : pos.paused
                  ? "The agent is paused for your deposit"
                  : "The agent is active on your deposit"}
            </div>
            <p className="text-xs text-ink-faint mt-0.5 leading-relaxed">
              Pausing stops it opening new trades. It does not stop you withdrawing.
            </p>
          </div>
          {pos.paused !== null ? (
            <button
              type="button"
              onClick={() => void doPause(!pos.paused)}
              disabled={busy !== null}
              className="shrink-0 inline-flex items-center gap-2 px-3 py-2 rounded border hair text-sm text-ink hover:bg-raised disabled:opacity-40"
            >
              {busy === "pause" ? (
                <Loader2 size={13} className="animate-spin" />
              ) : pos.paused ? (
                <Play size={13} />
              ) : (
                <Pause size={13} />
              )}
              {pos.paused ? "Resume" : "Pause"}
            </button>
          ) : null}
        </div>
      </div>

      {/* Exit, always available. */}
      <div className="px-4 py-4 border-b hair">
        <button
          type="button"
          onClick={() => void doWithdrawAll()}
          disabled={busy !== null || pos.balance === 0n}
          className="w-full inline-flex items-center justify-center gap-2 px-4 py-2.5 rounded border hair text-sm text-ink hover:bg-raised disabled:opacity-40 disabled:cursor-not-allowed"
        >
          {busy === "withdraw" ? (
            <Loader2 size={14} className="animate-spin" />
          ) : (
            <ArrowDownToLine size={14} />
          )}
          {pos.balance === 0n
            ? "Nothing to withdraw"
            : `Withdraw everything (${fromUnits(pos.balance, dec)})`}
        </button>
        <p className="text-xs text-ink-faint mt-2 leading-relaxed">
          This works whether the agent is running or paused. Withdrawal is not gated on the
          agent's state.
        </p>
      </div>

      {tx ? (
        <div className="px-4 py-3 border-b hair flex items-start gap-2">
          <CheckCircle2 size={14} className="text-approved shrink-0 mt-0.5" />
          <div className="min-w-0">
            <p className="text-xs text-ink">Sent. Reading the result back from the chain.</p>
            <a
              href={`${EXPLORER_TX}${tx}`}
              target="_blank"
              rel="noreferrer noopener"
              className="num text-xs text-telemetry hover:underline inline-flex items-center gap-1"
            >
              {tx.slice(0, 14)}…
              <ExternalLink size={10} />
            </a>
          </div>
        </div>
      ) : null}

      {err ? (
        <div className="px-4 py-3 border-b hair flex items-start gap-2">
          <AlertCircle size={14} className="text-critical shrink-0 mt-0.5" />
          <p className="text-xs text-ink">{err}</p>
        </div>
      ) : null}

      <div className="px-4 py-3 flex flex-wrap gap-2">
        <Badge icon={ShieldCheck} tone="approved">
          only ever lowered
        </Badge>
        <Badge icon={Lock} tone="approved">
          exit never blocked
        </Badge>
        {vaultAddr && chain.state === "ready" ? (
          <a
            href={`${chain.value.explorer_address_base}${vaultAddr}`}
            target="_blank"
            rel="noreferrer noopener"
            className="text-xs text-telemetry hover:underline inline-flex items-center gap-1"
          >
            the contract
            <ExternalLink size={10} />
          </a>
        ) : null}
      </div>
    </Card>
  );
}
