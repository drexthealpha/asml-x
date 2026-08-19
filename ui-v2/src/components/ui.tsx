/**
 * The pieces every surface is built from.
 *
 * WHAT IS DELIBERATELY ABSENT: any component for rendering an evidence id, a sample size, a
 * journal entry, a refusal ledger row, or a hex digest. Those existed in the old app and they are
 * the reason a non-technical visitor could not tell what the product does. If a number cannot be
 * explained to someone who just wants to trade, it does not get a component here.
 */

import type { ReactNode } from "react";
import { AlertCircle, Loader2 } from "lucide-react";
import type { Feed } from "../lib/feed";

export function cn(...parts: (string | false | null | undefined)[]): string {
  return parts.filter(Boolean).join(" ");
}

/** A titled region. One border, no shadow, no gradient. */
export function Card({
  title,
  meta,
  children,
  className,
}: {
  title?: string;
  meta?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={cn("border hair bg-surface rounded-lg overflow-hidden", className)}>
      {title ? (
        <header className="flex items-baseline justify-between gap-3 px-4 py-3 border-b hair">
          <h2 className="text-sm font-medium text-ink">{title}</h2>
          {meta ? <div className="text-xs text-ink-faint shrink-0">{meta}</div> : null}
        </header>
      ) : null}
      {children}
    </section>
  );
}

/**
 * Renders a feed, and NEVER renders a number the feed did not supply.
 *
 * The loading and failure states say different things on purpose. "Loading" and "no data" looked
 * identical in the old app, so a broken fetch was indistinguishable from an empty market.
 */
export function Show<T>({
  feed,
  children,
  what,
}: {
  feed: Feed<T>;
  what: string;
  children: (value: T) => ReactNode;
}) {
  if (feed.state === "loading") {
    return (
      <div className="flex items-center gap-2 px-4 py-6 text-sm text-ink-faint">
        <Loader2 size={14} className="animate-spin" />
        Loading {what}
      </div>
    );
  }
  if (feed.state === "failed") {
    return (
      <div className="flex items-start gap-2 px-4 py-6">
        <AlertCircle size={14} className="text-critical shrink-0 mt-0.5" />
        <div>
          <p className="text-sm text-ink">{what} is unavailable right now.</p>
          <p className="text-xs text-ink-faint mt-0.5">
            Nothing is shown rather than a stale figure. {feed.why}
          </p>
        </div>
      </div>
    );
  }
  return <>{children(feed.value)}</>;
}

/** A headline figure with its label. Used sparingly: most numbers belong in a table. */
export function Stat({
  label,
  value,
  sub,
  tone,
}: {
  label: string;
  value: ReactNode;
  sub?: ReactNode;
  tone?: "approved" | "shielded" | "critical" | "telemetry";
}) {
  const color =
    tone === "approved"
      ? "text-approved"
      : tone === "shielded"
        ? "text-shielded"
        : tone === "critical"
          ? "text-critical"
          : tone === "telemetry"
            ? "text-telemetry"
            : "text-ink";
  return (
    <div className="px-4 py-3">
      <div className="text-xs text-ink-faint">{label}</div>
      <div className={cn("num text-xl leading-tight mt-0.5", color)}>{value}</div>
      {sub ? <div className="text-xs text-ink-faint mt-0.5">{sub}</div> : null}
    </div>
  );
}

/**
 * A status, always as icon plus word plus colour.
 *
 * Never colour alone. A red dot with no label is unreadable to a colourblind user and meaningless
 * to everyone else.
 */
export function Badge({
  icon: Icon,
  children,
  tone,
}: {
  icon: React.ComponentType<{ size?: number; className?: string }>;
  children: ReactNode;
  tone: "approved" | "shielded" | "critical" | "telemetry" | "muted";
}) {
  const map = {
    approved: "text-approved border-approved/30 bg-approved/10",
    shielded: "text-shielded border-shielded/30 bg-shielded/10",
    critical: "text-critical border-critical/30 bg-critical/10",
    telemetry: "text-telemetry border-telemetry/30 bg-telemetry/10",
    muted: "text-ink-faint border-line bg-raised",
  } as const;
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 px-2 py-0.5 rounded border text-xs whitespace-nowrap",
        map[tone],
      )}
    >
      <Icon size={12} className="shrink-0" />
      {children}
    </span>
  );
}

/** The value that is genuinely absent. Never a zero standing in for one. */
export function NoValue({ why }: { why: string }) {
  return <span className="text-ink-faint text-xs">{why}</span>;
}
