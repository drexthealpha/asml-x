/**
 * The money flow. Connect, put money in with a ceiling, take it out.
 *
 * THIS IS WHAT WAS MISSING. The rebuilt app listed tokens and drew a chart, so clicking anything
 * led nowhere: there was no deposit, no limit, no withdrawal, nothing to DO. A product about an
 * agent trading your money has to let you give it money and take it back.
 *
 * FOUR STATES, ALL DESIGNED, none of them a raw absence:
 *   no wallet      an instruction a person can follow
 *   wrong network  a button that fixes it, not a lecture
 *   connected      the balance and the ceiling, read from the chain
 *   paused         withdrawal still works, and the screen says so
 *
 * THE LIMIT AND THE DEPOSIT ARE ONE TRANSACTION, because the contract takes both. There is never a
 * moment where money sits in the vault with no ceiling on it.
 */

import { useCallback, useEffect, useState } from "react";
import {
  AlertCircle,
  ArrowDownToLine,
  ArrowUpFromLine,
  CheckCircle2,
  ExternalLink,
  Loader2,
  Lock,
  ShieldCheck,
} from "lucide-react";
import {
  EXPLORER_TX,
  allowance,
  approve,
  deposit,
  fromUnits,
  provider,
  setProvider,
  readWallet,
  switchToXLayer,
  toUnits,
  tokenBalance,
  tokenDecimals,
  vaultPaused,
  vaultPosition,
  withdraw,
  type Wallet,
  type WalletError,
} from "../lib/wallet";
import { connectWalletConnect } from "../lib/walletconnect";
import { ConnectPicker } from "./connect-picker";
import type { Discovered } from "../lib/wallets";
import { loadChain, type Chain, type Feed } from "../lib/feed";
import { Badge, Card, cn } from "./ui";

interface Position {
  walletBalance: bigint;
  vaultBalance: bigint;
  maxNotional: bigint;
  decimals: number;
  paused: boolean;
}

function Button({
  children,
  onClick,
  busy,
  disabled,
  tone = "primary",
}: {
  children: React.ReactNode;
  onClick: () => void;
  busy?: boolean;
  disabled?: boolean;
  tone?: "primary" | "quiet";
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={busy || disabled}
      className={cn(
        "inline-flex items-center justify-center gap-2 px-4 py-2.5 rounded text-sm font-medium w-full",
        "disabled:opacity-40 disabled:cursor-not-allowed transition-colors",
        tone === "primary"
          ? "bg-approved text-bg hover:bg-approved/90"
          : "border hair text-ink hover:bg-raised",
      )}
    >
      {busy ? <Loader2 size={14} className="animate-spin" /> : null}
      {children}
    </button>
  );
}

function Field({
  label,
  value,
  onChange,
  suffix,
  hint,
  onMax,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  suffix: string;
  hint?: string;
  onMax?: () => void;
}) {
  return (
    <label className="block">
      <span className="text-xs text-ink-faint">{label}</span>
      <span className="mt-1 flex items-center gap-2 bg-raised border hair rounded px-3 py-2">
        <input
          value={value}
          onChange={(e) => onChange(e.target.value.replace(/[^0-9.]/g, ""))}
          inputMode="decimal"
          placeholder="0.00"
          className="num flex-1 min-w-0 bg-transparent text-sm text-ink outline-none placeholder:text-ink-faint"
        />
        <span className="text-xs text-ink-faint shrink-0">{suffix}</span>
        {onMax ? (
          <button
            type="button"
            onClick={onMax}
            className="text-xs text-telemetry hover:underline shrink-0"
          >
            Max
          </button>
        ) : null}
      </span>
      {hint ? <span className="block text-xs text-ink-faint mt-1">{hint}</span> : null}
    </label>
  );
}

export function Vault() {
  const [chain, setChain] = useState<Feed<Chain>>({ state: "loading" });
  const [wallet, setWallet] = useState<Wallet | null>(null);
  const [checked, setChecked] = useState(false);
  const [pos, setPos] = useState<Position | null>(null);
  const [err, setErr] = useState<WalletError | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [tx, setTx] = useState<string | null>(null);

  const [amount, setAmount] = useState("");
  const [limit, setLimit] = useState("");
  const [out, setOut] = useState("");

  useEffect(() => {
    void loadChain().then(setChain);
  }, []);

  const addr = useCallback(
    (name: string) =>
      chain.state === "ready"
        ? (chain.value.deployments.find((d) => d.name === name)?.address ?? null)
        : null,
    [chain],
  );

  const vaultAddr = addr("AgentVault");
  // The vault's accounting asset. Named aQUOTE on mainnet, tQUOTE on the development chain; both
  // are looked up so a manifest rename cannot blank the screen.
  const assetAddr = addr("aQUOTE") ?? addr("MockERC20 tQUOTE");

  /** Read everything from the chain. Called after every write, never assumed. */
  const refresh = useCallback(async () => {
    if (!wallet?.onXLayer || !vaultAddr || !assetAddr) return;
    try {
      const decimals = await tokenDecimals(assetAddr);
      const [walletBalance, p, paused] = await Promise.all([
        tokenBalance(assetAddr, wallet.address),
        vaultPosition(vaultAddr, wallet.address),
        vaultPaused(vaultAddr),
      ]);
      setPos({
        walletBalance,
        vaultBalance: p.balance,
        maxNotional: p.maxNotional,
        decimals,
        paused,
      });
    } catch (e) {
      setErr({
        message: "Could not read your balance from the chain.",
        next: e instanceof Error ? e.message : "Reload the page.",
      });
    }
  }, [wallet, vaultAddr, assetAddr]);

  useEffect(() => {
    void readWallet().then((w) => {
      setWallet(w);
      setChecked(true);
    });
    const p = provider();
    const onChange = () => void readWallet().then(setWallet);
    p?.on?.("accountsChanged", onChange);
    p?.on?.("chainChanged", onChange);
    return () => {
      p?.removeListener?.("accountsChanged", onChange);
      p?.removeListener?.("chainChanged", onChange);
    };
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  /**
   * Connect by QR or deep link.
   *
   * The returned provider is registered through `setProvider`, so every balance read, approval,
   * deposit and withdrawal below runs against it unchanged. There is no separate mobile code path.
   */
  const doConnectWc = async () => {
    setBusy("walletconnect");
    setErr(null);
    try {
      const p = await connectWalletConnect();
      setProvider(p);
      setWallet(await readWallet());
    } catch (e) {
      const m = e instanceof Error ? e.message : String(e);
      setErr(
        /reject|closed|cancel|denied/i.test(m)
          ? { message: "Connection cancelled.", next: "Press the button again when you are ready." }
          : { message: "Could not reach your wallet.", next: m },
      );
    } finally {
      setBusy(null);
    }
  };

  /**
   * Connect through the wallet the user actually chose.
   *
   * WHY NOT `window.ethereum`. With two extensions installed, `window.ethereum` is whichever one
   * loaded last. Someone clicks "OKX Wallet" and MetaMask opens. EIP-6963 hands back the specific
   * provider that announced itself under that name, and registering it makes every later read and
   * write in this component use it.
   */
  const doPick = async (w: Discovered) => {
    setBusy(w.id);
    setErr(null);
    try {
      setProvider(w.provider);
      const accounts = (await w.provider.request({ method: "eth_requestAccounts" })) as string[];
      if (!accounts?.length) throw new Error("no account was returned");
      setWallet(await readWallet());
    } catch (e) {
      // The chosen provider failed, so it must not stay registered: leaving it would send the next
      // attempt to a wallet the user could not connect.
      setProvider(null);
      const m = e instanceof Error ? e.message : String(e);
      setErr(
        /reject|denied|cancel/i.test(m)
          ? { message: "You cancelled the connection.", next: `Press ${w.name} again when ready.` }
          : { message: `${w.name} could not connect.`, next: m },
      );
    } finally {
      setBusy(null);
    }
  };

  const doDeposit = async () => {
    if (!wallet || !vaultAddr || !assetAddr || !pos) return;
    setBusy("deposit");
    setErr(null);
    setTx(null);
    try {
      const units = toUnits(amount, pos.decimals);
      const cap = toUnits(limit || amount, pos.decimals);
      if (units <= 0n) throw new Error("Enter an amount above zero.");
      if (units > pos.walletBalance) throw new Error("That is more than your wallet holds.");

      // Approve only when the current allowance is short. An unconditional approve costs the user
      // a transaction they do not need.
      const current = await allowance(assetAddr, wallet.address, vaultAddr);
      if (current < units) {
        await approve(wallet.address, assetAddr, vaultAddr, units);
      }
      const hash = await deposit(wallet.address, vaultAddr, units, cap);
      setTx(hash);
      setAmount("");
      setLimit("");
      // Read the result back rather than assuming it. A short delay lets the block land.
      setTimeout(() => void refresh(), 3000);
    } catch (e) {
      const m = e instanceof Error ? e.message : String(e);
      setErr(
        /reject|denied/i.test(m)
          ? { message: "You cancelled the transaction.", next: "Nothing was sent." }
          : { message: m, next: "Check the amount and try again." },
      );
    } finally {
      setBusy(null);
    }
  };

  const doWithdraw = async () => {
    if (!wallet || !vaultAddr || !pos) return;
    setBusy("withdraw");
    setErr(null);
    setTx(null);
    try {
      const units = toUnits(out, pos.decimals);
      if (units <= 0n) throw new Error("Enter an amount above zero.");
      if (units > pos.vaultBalance) throw new Error("That is more than your vault holds.");
      const hash = await withdraw(wallet.address, vaultAddr, units);
      setTx(hash);
      setOut("");
      setTimeout(() => void refresh(), 3000);
    } catch (e) {
      const m = e instanceof Error ? e.message : String(e);
      setErr(
        /reject|denied/i.test(m)
          ? { message: "You cancelled the transaction.", next: "Nothing was sent." }
          : { message: m, next: "Check the amount and try again." },
      );
    } finally {
      setBusy(null);
    }
  };

  // ---------------------------------------------------------------- states

  if (!checked) {
    return (
      <Card title="Your money">
        <div className="flex items-center gap-2 px-4 py-6 text-sm text-ink-faint">
          <Loader2 size={14} className="animate-spin" />
          Checking for a wallet
        </div>
      </Card>
    );
  }

  // NO EXTENSION IS NOT A DEAD END. This used to say "install a wallet and reload", which a phone
  // user cannot act on: mobile browsers do not take extensions. WalletConnect reaches OKX Wallet,
  // MetaMask mobile and every other WalletConnect wallet by QR or deep link, so the majority of
  // visitors now have a route. The extension option is offered second, as the desktop fallback.
  if (!wallet) {
    return (
      <Card title="Your money">
        <div className="px-4 py-4">
          <p className="text-sm text-ink mb-3">Choose a wallet</p>
          <ConnectPicker onPick={(w) => void doPick(w)} onWalletConnect={() => void doConnectWc()} busy={busy} />
          <p className="text-xs text-ink-faint mt-3 leading-relaxed">
            Connecting only shows your balance. Nothing moves until you deposit, and you can
            withdraw whenever you want.
          </p>
          {err ? (
            <div className="mt-3 flex items-start gap-2">
              <AlertCircle size={14} className="text-critical shrink-0 mt-0.5" />
              <div>
                <p className="text-xs text-ink">{err.message}</p>
                <p className="text-xs text-ink-faint">{err.next}</p>
              </div>
            </div>
          ) : null}
        </div>
      </Card>
    );
  }

  if (!wallet.onXLayer) {
    return (
      <Card title="Your money">
        <div className="px-4 py-5">
          <p className="text-sm text-ink">Your wallet is on the wrong network.</p>
          <p className="text-xs text-ink-faint mt-1 mb-3">
            This app runs on X Layer. Your wallet is on chain {wallet.chainId}.
          </p>
          <Button onClick={() => void switchToXLayer().then(() => readWallet().then(setWallet))}>
            Switch to X Layer
          </Button>
        </div>
      </Card>
    );
  }

  const dec = pos?.decimals ?? 6;

  return (
    <Card
      title="Your money"
      meta={
        <span className="num text-ink-faint">
          {wallet.address.slice(0, 6)}…{wallet.address.slice(-4)}
        </span>
      }
    >
      {/* Position, read from the chain on every refresh. */}
      <div className="grid grid-cols-2 border-b hair">
        <div className="px-4 py-3 border-r hair">
          <div className="text-xs text-ink-faint">In the vault</div>
          <div className="num text-xl text-ink mt-0.5">
            {pos ? fromUnits(pos.vaultBalance, dec) : "—"}
          </div>
        </div>
        <div className="px-4 py-3">
          <div className="text-xs text-ink-faint">Most it may risk at once</div>
          <div className="num text-xl text-ink mt-0.5">
            {pos ? fromUnits(pos.maxNotional, dec) : "—"}
          </div>
        </div>
      </div>

      {pos?.paused ? (
        <div className="px-4 py-3 border-b hair flex items-start gap-2">
          <Lock size={14} className="text-approved shrink-0 mt-0.5" />
          <p className="text-xs text-ink-soft leading-relaxed">
            The agent is paused and is not trading. Your withdrawals still work normally.
          </p>
        </div>
      ) : null}

      {/* Deposit */}
      <div className="px-4 py-4 border-b hair grid gap-3">
        <Field
          label="Deposit"
          value={amount}
          onChange={setAmount}
          suffix="tokens"
          hint={pos ? `${fromUnits(pos.walletBalance, dec)} in your wallet` : undefined}
          onMax={pos ? () => setAmount(fromUnits(pos.walletBalance, dec)) : undefined}
        />
        <Field
          label="Most the agent may risk in one trade"
          value={limit}
          onChange={setLimit}
          suffix="tokens"
          hint="Leave blank to use the deposit amount. You can lower this later, never raise it."
        />
        <Button
          onClick={() => void doDeposit()}
          busy={busy === "deposit"}
          disabled={!amount || !pos}
        >
          <ArrowDownToLine size={15} />
          Deposit and set limit
        </Button>
      </div>

      {/* Withdraw */}
      <div className="px-4 py-4 grid gap-3">
        <Field
          label="Withdraw"
          value={out}
          onChange={setOut}
          suffix="tokens"
          onMax={pos ? () => setOut(fromUnits(pos.vaultBalance, dec)) : undefined}
        />
        <Button
          onClick={() => void doWithdraw()}
          busy={busy === "withdraw"}
          disabled={!out || !pos || pos.vaultBalance === 0n}
          tone="quiet"
        >
          <ArrowUpFromLine size={15} />
          Withdraw
        </Button>
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
              {tx.slice(0, 12)}…
              <ExternalLink size={10} />
            </a>
          </div>
        </div>
      ) : null}

      {err ? (
        <div className="px-4 py-3 border-t hair flex items-start gap-2">
          <AlertCircle size={14} className="text-critical shrink-0 mt-0.5" />
          <div>
            <p className="text-xs text-ink">{err.message}</p>
            <p className="text-xs text-ink-faint">{err.next}</p>
          </div>
        </div>
      ) : null}

      <div className="px-4 py-3 border-t hair flex items-start gap-2">
        <ShieldCheck size={14} className="text-approved shrink-0 mt-0.5" />
        <p className="text-xs text-ink-faint leading-relaxed">
          Your limit can only be lowered, never raised. Withdrawals work even when the agent is
          paused.
        </p>
      </div>

      {!vaultAddr ? (
        <div className="px-4 py-3 border-t hair">
          <Badge icon={AlertCircle} tone="shielded">
            vault address unavailable
          </Badge>
        </div>
      ) : null}
    </Card>
  );
}
