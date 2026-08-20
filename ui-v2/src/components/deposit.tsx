/**
 * Deposit, with the cap set in the same transaction and the fee quoted by the contract.
 *
 * TASKS 2, 3 AND 5 IN ONE PLACE, because they are one decision for the person making it: how much
 * to put in, what the agent may risk with it, what it costs, and which ceiling binds first.
 *
 * THE FEE COMES FROM `FeeCollector.quoteFee(uint256)`, a view on the contract that will charge it.
 * Multiplying by `feeBps` in the UI would usually agree and would be wrong the moment the
 * contract's rounding differs. A number shown before someone signs has to come from the thing that
 * will actually take it.
 *
 * TWO CEILINGS, AND WHICH ONE BINDS. Your own cap and the global `RiskGuard.maxGross` both apply.
 * Showing only one invites the belief it is the only one, so both are shown with the binding one
 * named. That is the difference between a limit a person understands and a number they hope about.
 *
 * THE CAP IS NOT OPTIONAL. `deposit(amount, maxNotional)` takes both, so there is never a moment
 * where funds sit in the vault with no ceiling attached.
 */

import { useCallback, useEffect, useState } from "react";
import {
  AlertCircle,
  ArrowDownToLine,
  CheckCircle2,
  ExternalLink,
  Loader2,
  ShieldCheck,
} from "lucide-react";
import {
  EXPLORER_TX,
  allowance,
  approve,
  decodeRevert,
  deposit,
  fromUnits,
  guardState,
  provider,
  quoteFee,
  readWallet,
  toUnits,
  tokenBalance,
  tokenDecimals,
  vaultPosition,
  type Wallet,
} from "../lib/wallet";
import { loadChain, type Chain, type Feed } from "../lib/feed";
import { Badge, Card } from "./ui";

export function Deposit() {
  const [chain, setChain] = useState<Feed<Chain>>({ state: "loading" });
  const [wallet, setWallet] = useState<Wallet | null>(null);
  const [decimals, setDecimals] = useState(18);
  const [walletBal, setWalletBal] = useState<bigint | null>(null);
  const [currentCap, setCurrentCap] = useState<bigint | null>(null);
  const [guard, setGuard] = useState<{ maxGross: bigint | null; gross: bigint | null; killed: boolean | null } | null>(null);
  const [fee, setFee] = useState<bigint | null>(null);

  const [amount, setAmount] = useState("");
  const [cap, setCap] = useState("");
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

  const find = useCallback(
    (n: string) =>
      chain.state === "ready"
        ? (chain.value.deployments.find((d) => d.name === n)?.address ?? null)
        : null,
    [chain],
  );

  const vaultAddr = find("AgentVault");
  const assetAddr = find("aQUOTE") ?? find("MockERC20 tQUOTE");
  const feeAddr = find("FeeCollector");
  const guardAddr = find("RiskGuard");

  const refresh = useCallback(async () => {
    if (!wallet?.onXLayer || !vaultAddr || !assetAddr) return;
    try {
      const [d, bal, pos, g] = await Promise.all([
        tokenDecimals(assetAddr),
        tokenBalance(assetAddr, wallet.address),
        vaultPosition(vaultAddr, wallet.address),
        guardAddr ? guardState(guardAddr) : Promise.resolve(null),
      ]);
      setDecimals(d);
      setWalletBal(bal);
      setCurrentCap(pos.maxNotional);
      setGuard(g);
    } catch (e) {
      setErr(decodeRevert(e));
    }
  }, [wallet, vaultAddr, assetAddr, guardAddr]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  // The fee, quoted by the contract, whenever the cap changes. The cap is the notional a trade can
  // reach, so that is what the fee applies to.
  useEffect(() => {
    const capUnits = cap || amount;
    if (!feeAddr || !capUnits) {
      setFee(null);
      return;
    }
    let live = true;
    void quoteFee(feeAddr, toUnits(capUnits, decimals)).then((f) => {
      if (live) setFee(f);
    });
    return () => {
      live = false;
    };
  }, [feeAddr, cap, amount, decimals]);

  const doDeposit = async () => {
    if (!wallet || !vaultAddr || !assetAddr) return;
    setBusy("deposit");
    setErr(null);
    setTx(null);
    try {
      const units = toUnits(amount, decimals);
      const capUnits = toUnits(cap || amount, decimals);
      if (units <= 0n) throw new Error("Enter an amount above zero.");
      if (walletBal !== null && units > walletBal) {
        throw new Error("That is more than your wallet holds.");
      }
      // A LOWER CAP THAN YOU HAVE IS FINE; a higher one is refused before signing when one is
      // already set, because the contract's guarantee is that it only tightens.
      if (currentCap !== null && currentCap > 0n && capUnits > currentCap) {
        throw new Error(
          `Your limit is already ${fromUnits(currentCap, decimals)} and can only be lowered.`,
        );
      }

      const current = await allowance(assetAddr, wallet.address, vaultAddr);
      if (current < units) {
        setBusy("approve");
        await approve(wallet.address, assetAddr, vaultAddr, units);
        setBusy("deposit");
      }
      const hash = await deposit(wallet.address, vaultAddr, units, capUnits);
      setTx(hash);
      setAmount("");
      setCap("");
      setTimeout(() => void refresh(), 3000);
    } catch (e) {
      setErr(decodeRevert(e));
    } finally {
      setBusy(null);
    }
  };

  if (!wallet?.onXLayer) return null;

  const bindingCeiling = (() => {
    if (!guard?.maxGross || !guard.gross) return null;
    const headroom = guard.maxGross - guard.gross;
    const mine = cap ? toUnits(cap, decimals) : currentCap;
    if (mine === null) return null;
    return mine <= headroom ? "yours" : "the global one";
  })();

  return (
    <Card title="Add money">
      {guard?.killed === true ? (
        <div className="px-4 py-3 border-b hair bg-critical/10 flex items-start gap-2">
          <AlertCircle size={14} className="text-critical shrink-0 mt-0.5" />
          <p className="text-xs text-ink leading-relaxed">
            The emergency stop is on. Deposits are pointless right now; withdrawals still work.
          </p>
        </div>
      ) : null}

      <div className="px-4 py-4 grid gap-3">
        <label className="block">
          <span className="text-xs text-ink-faint">How much to deposit</span>
          <span className="mt-1 flex items-center gap-2 bg-raised border hair rounded px-3 py-2">
            <input
              value={amount}
              onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))}
              inputMode="decimal"
              placeholder="0.00"
              className="num flex-1 min-w-0 bg-transparent text-sm text-ink outline-none placeholder:text-ink-faint"
            />
            {walletBal !== null ? (
              <button
                type="button"
                onClick={() => setAmount(fromUnits(walletBal, decimals))}
                className="text-xs text-telemetry hover:underline shrink-0"
              >
                Max
              </button>
            ) : null}
          </span>
          {walletBal !== null ? (
            <span className="block text-xs text-ink-faint mt-1">
              {fromUnits(walletBal, decimals)} in your wallet
            </span>
          ) : null}
        </label>

        <label className="block">
          <span className="text-xs text-ink-faint">The most the agent may risk in one trade</span>
          <span className="mt-1 flex items-center gap-2 bg-raised border hair rounded px-3 py-2">
            <input
              value={cap}
              onChange={(e) => setCap(e.target.value.replace(/[^0-9.]/g, ""))}
              inputMode="decimal"
              placeholder={amount || "0.00"}
              className="num flex-1 min-w-0 bg-transparent text-sm text-ink outline-none placeholder:text-ink-faint"
            />
          </span>
          <span className="block text-xs text-ink-faint mt-1">
            {currentCap && currentCap > 0n
              ? `Currently ${fromUnits(currentCap, decimals)}. This can only go down.`
              : "Leave blank to use the deposit amount. You can lower it later, never raise it."}
          </span>
        </label>

        {/* What it costs, asked of the contract that charges it. */}
        {fee !== null ? (
          <div className="px-3 py-2 rounded border hair bg-raised">
            <div className="flex items-baseline justify-between gap-3">
              <span className="text-xs text-ink-faint">Fee on a trade of that size</span>
              <span className="num text-sm text-ink">{fromUnits(fee, decimals)}</span>
            </div>
            <p className="text-xs text-ink-faint mt-1 leading-relaxed">
              Quoted by the fee contract itself. Charged only when a trade executes, never on this
              deposit and never on a withdrawal.
            </p>
          </div>
        ) : null}

        {/* Which ceiling binds first. */}
        {bindingCeiling && guard?.maxGross && guard.gross !== null ? (
          <div className="px-3 py-2 rounded border hair">
            <p className="text-xs text-ink-soft leading-relaxed">
              Two ceilings apply: yours, and a global one of{" "}
              <span className="num">{fromUnits(guard.maxGross, decimals)}</span> across everyone,{" "}
              <span className="num">{fromUnits(guard.gross, decimals)}</span> of which is in use.{" "}
              <span className="text-ink">{bindingCeiling === "yours" ? "Yours" : "The global one"}</span>{" "}
              binds first.
            </p>
          </div>
        ) : null}

        <button
          type="button"
          onClick={() => void doDeposit()}
          disabled={busy !== null || !amount}
          className="w-full inline-flex items-center justify-center gap-2 px-4 py-2.5 rounded text-sm font-medium bg-approved text-bg hover:bg-approved/90 disabled:opacity-40 disabled:cursor-not-allowed"
        >
          {busy ? <Loader2 size={14} className="animate-spin" /> : <ArrowDownToLine size={14} />}
          {busy === "approve" ? "Approving…" : busy === "deposit" ? "Depositing…" : "Deposit and set the limit"}
        </button>

        <div className="flex items-start gap-2">
          <ShieldCheck size={13} className="text-approved shrink-0 mt-0.5" />
          <p className="text-xs text-ink-faint leading-relaxed">
            The limit is set in the same transaction as the deposit, so your money is never in the
            vault without a ceiling on it.
          </p>
        </div>
      </div>

      {tx ? (
        <div className="px-4 py-3 border-t hair flex items-start gap-2">
          <CheckCircle2 size={14} className="text-approved shrink-0 mt-0.5" />
          <div className="min-w-0">
            <p className="text-xs text-ink">Sent.</p>
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
        <div className="px-4 py-3 border-t hair flex items-start gap-2">
          <AlertCircle size={14} className="text-critical shrink-0 mt-0.5" />
          <p className="text-xs text-ink">{err}</p>
        </div>
      ) : null}

      {guard?.killed === false ? (
        <div className="px-4 py-3 border-t hair">
          <Badge icon={ShieldCheck} tone="approved">
            emergency stop is off
          </Badge>
        </div>
      ) : null}
    </Card>
  );
}
