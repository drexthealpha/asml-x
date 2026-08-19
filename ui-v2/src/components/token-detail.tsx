/**
 * One token, in full. What opens when a row is clicked.
 *
 * WHY EVERY ROW MUST OPEN SOMETHING. Rows were static divs: clicking DAI or WBTC or STARCOIN did
 * nothing, while the fields below were already being fetched and discarded. A list that does not
 * open is a screenshot.
 *
 * THE ORDER IS THE ORDER OF THE QUESTIONS SOMEONE ACTUALLY ASKS:
 *   1. what is it worth, and is it moving
 *   2. can I get out — liquidity, which pools, how deep
 *   3. can I be trapped — honeypot, tax, mintable, LP burned
 *   4. am I the exit liquidity — holder concentration, bundle buying, shared funding
 *
 * THE UNCOMFORTABLE NUMBERS ARE NOT BURIED. "Top 100 wallets hold 92%" and "liquidity providers
 * can still pull 62% of the pool" go above the fold, not behind a disclosure. A price and a chart
 * make anything look tradable; these are the figures that tell a person to stop.
 */

import { useEffect } from "react";
import {
  AlertTriangle,
  ExternalLink,
  ShieldAlert,
  ShieldCheck,
  TrendingDown,
  TrendingUp,
  X,
} from "lucide-react";
import { compact, money, pct, type TokenDetail } from "../lib/feed";
import { Badge, cn } from "./ui";

function Change({ label, v }: { label: string; v?: string }) {
  const n = v === undefined ? null : Number.parseFloat(v);
  const has = n !== null && Number.isFinite(n);
  return (
    <div className="px-3 py-2 text-center">
      <div className="text-xs text-ink-faint">{label}</div>
      <div
        className={cn(
          "num text-sm mt-0.5",
          !has ? "text-ink-faint" : n >= 0 ? "text-approved" : "text-critical",
        )}
      >
        {has ? `${n >= 0 ? "+" : ""}${n.toFixed(2)}%` : "—"}
      </div>
    </div>
  );
}

function Fact({ label, value, sub }: { label: string; value: string | null; sub?: string }) {
  return (
    <div className="px-4 py-2.5 border-b hair flex items-baseline justify-between gap-3">
      <span className="text-xs text-ink-faint">{label}</span>
      <div className="text-right">
        {/* Absent stays absent. A dash is honest; a zero is a claim nobody measured. */}
        <span className="num text-sm text-ink">{value ?? "—"}</span>
        {sub ? <div className="text-xs text-ink-faint">{sub}</div> : null}
      </div>
    </div>
  );
}

export function TokenDetailPanel({
  t,
  onClose,
  explorerBase,
}: {
  t: TokenDetail;
  onClose: () => void;
  explorerBase?: string;
}) {
  // Escape closes it. A panel that can only be dismissed with a mouse is a trap for anyone
  // navigating by keyboard.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const top100 = pct(t.top100_percent);
  const lpBurned = t.lp_burned_percent ? Number.parseFloat(t.lp_burned_percent) : null;
  // LP burned is the share that can NEVER be withdrawn. The remainder is what a liquidity provider
  // could still pull, which is the number that matters to someone holding the token.
  const pullable = lpBurned !== null && Number.isFinite(lpBurned) ? 100 - lpBurned : null;
  const concentrated = top100 !== null && Number.parseFloat(t.top100_percent ?? "0") > 0.9;

  const risky =
    t.honeypot === true ||
    t.risk_level === "HIGH" ||
    t.low_liquidity === true ||
    concentrated;

  return (
    <div
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/70 p-0 sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-label={`${t.symbol} details`}
      onClick={onClose}
    >
      <div
        className="bg-surface border hair rounded-t-lg sm:rounded-lg w-full max-w-lg max-h-[92vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <header className="sticky top-0 bg-surface border-b hair px-4 py-3 flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <h2 className="text-base font-medium text-ink">{t.symbol}</h2>
              {t.risk_level ? (
                <Badge
                  icon={t.risk_level === "LOW" ? ShieldCheck : ShieldAlert}
                  tone={
                    t.risk_level === "LOW"
                      ? "approved"
                      : t.risk_level === "HIGH"
                        ? "critical"
                        : "shielded"
                  }
                >
                  {t.risk_level.toLowerCase()} risk
                </Badge>
              ) : null}
            </div>
            <div className="num text-2xl text-ink mt-1">${money(t.price)}</div>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="text-ink-faint hover:text-ink p-1 shrink-0"
          >
            <X size={18} />
          </button>
        </header>

        {/* 1. Is it moving. */}
        <div className="grid grid-cols-4 border-b hair divide-x divide-line">
          <Change label="5 min" v={t.change_5m} />
          <Change label="1 hour" v={t.change_1h} />
          <Change label="4 hours" v={t.change_4h} />
          <Change label="24 hours" v={t.change_24h} />
        </div>

        {/* The warning goes FIRST when there is one, not at the bottom where it reads as a caveat. */}
        {risky ? (
          <div className="px-4 py-3 border-b hair bg-critical/5 flex items-start gap-2">
            <AlertTriangle size={15} className="text-critical shrink-0 mt-0.5" />
            <div className="text-xs text-ink-soft leading-relaxed">
              {t.honeypot === true
                ? "This token may not be sellable after you buy it."
                : concentrated
                  ? `A small number of wallets own ${top100} of this. They can move the price against you.`
                  : t.low_liquidity === true
                    ? "There is very little available to trade. Getting out could be expensive."
                    : "This token carries elevated risk."}
            </div>
          </div>
        ) : null}

        {/* 2. Can I get out. */}
        <Fact label="Available to trade" value={compact(t.liquidity)} />
        <Fact label="Total value" value={compact(t.market_cap)} />
        <Fact label="People holding it" value={t.holders ? Number(t.holders).toLocaleString() : null} />
        <Fact
          label="Cost to sell"
          value={t.sell_tax ? `${(Number.parseFloat(t.sell_tax) * 100).toFixed(1)}%` : "none"}
        />

        {/* 3. Where it trades. Real pool names, real protocols. */}
        {t.pools?.length ? (
          <div className="border-b hair">
            <div className="px-4 pt-3 pb-1 text-xs text-ink-faint">Where it trades</div>
            {t.pools.map((p) => (
              <div
                key={p.address}
                className="px-4 py-2 flex items-baseline justify-between gap-3"
              >
                <span className="text-sm text-ink truncate">
                  {p.protocol || p.pool}
                </span>
                <span className="num text-xs text-ink-faint shrink-0">{compact(p.usd)}</span>
              </div>
            ))}
          </div>
        ) : null}

        {/* 4. Am I the exit liquidity. */}
        <div className="px-4 pt-3 pb-1 text-xs text-ink-faint">Ownership</div>
        <Fact label="Top 100 wallets own" value={top100} />
        <Fact
          label="Liquidity that can be withdrawn"
          value={pullable !== null ? `${pullable.toFixed(0)}%` : null}
          sub={pullable !== null && pullable > 50 ? "providers could pull most of it" : undefined}
        />
        <Fact label="Holder clustering" value={t.cluster_concentration ?? null} />
        <Fact label="Bought in one block" value={pct(t.bundle_holding_percent)} />

        <div className="px-4 py-3 flex flex-wrap gap-2">
          {t.honeypot === false ? (
            <Badge icon={ShieldCheck} tone="approved">
              sellable
            </Badge>
          ) : null}
          {t.mintable === false ? (
            <Badge icon={ShieldCheck} tone="approved">
              supply fixed
            </Badge>
          ) : t.mintable === true ? (
            <Badge icon={ShieldAlert} tone="shielded">
              more can be created
            </Badge>
          ) : null}
          {t.open_source === true ? (
            <Badge icon={ShieldCheck} tone="approved">
              code public
            </Badge>
          ) : null}
          {t.index_price ? (
            <Badge icon={TrendingUp} tone="telemetry">
              reference ${money(t.index_price)}
            </Badge>
          ) : null}
        </div>

        {explorerBase ? (
          <div className="px-4 pb-4">
            <a
              href={`${explorerBase}${t.address}`}
              target="_blank"
              rel="noreferrer noopener"
              className="text-xs text-telemetry hover:underline inline-flex items-center gap-1"
            >
              View the contract
              <ExternalLink size={10} />
            </a>
          </div>
        ) : null}
      </div>
    </div>
  );
}

/** Re-exported so callers do not need to import lucide directly for the common case. */
export { TrendingDown };

/**
 * What opens when a token has no detail record yet.
 *
 * WHY THIS EXISTS RATHER THAN NOTHING. A row that clicks and does nothing reads as a broken app.
 * The Insights surface names tokens from the smart-money feed that the detail sweep may not have
 * reached yet, and swallowing those clicks was indistinguishable from a bug. This says which token
 * it is, why there is nothing to show, and gives a way out.
 */
export function MissingDetail({
  symbol,
  onClose,
}: {
  symbol: string;
  onClose: () => void;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/70 p-0 sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-label={`${symbol} details unavailable`}
      onClick={onClose}
    >
      <div
        className="bg-surface border hair rounded-t-lg sm:rounded-lg w-full max-w-sm"
        onClick={(e) => e.stopPropagation()}
      >
        <header className="px-4 py-3 border-b hair flex items-center justify-between gap-3">
          <h2 className="text-base font-medium text-ink">{symbol}</h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="text-ink-faint hover:text-ink p-1"
          >
            <X size={18} />
          </button>
        </header>
        <div className="px-4 py-5">
          <p className="text-sm text-ink">Details for this token are still loading.</p>
          <p className="text-xs text-ink-faint mt-1 leading-relaxed">
            It appeared in a live signal feed and the full record is being fetched. Nothing is shown
            rather than a partial picture of an asset you might trade.
          </p>
        </div>
      </div>
    </div>
  );
}
