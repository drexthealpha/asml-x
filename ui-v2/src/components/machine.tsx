/**
 * The machine, and whether it is inside its own limits right now.
 *
 * WHAT THIS REPLACES. The footer listed nine contract addresses linked to the explorer, which
 * proves they exist and nothing else. A person deciding whether to trust this with money wants a
 * different question answered: is it running, and is it near its own edge? Those are single
 * `eth_call`s, and none of them were being made.
 *
 * THE HEADLINE IS THE UTILISATION BAR. "Holding 14.96 of a 1000 ceiling" is the one number that
 * says whether the safety limit is theoretical or actually binding, and it moves.
 *
 * EVERY VALUE IS READ FROM CHAIN 196 ON EACH REFRESH. A value that could not be read says so
 * rather than showing a zero, because a zero here reads as "no risk taken" when it means
 * "nobody checked".
 */

import { Activity, ExternalLink, ShieldAlert, ShieldCheck } from "lucide-react";
import {
  POLL,
  ago,
  loadContracts,
  usePolled,
  type ContractCard,
  type Contracts,
} from "../lib/feed";
import { Badge, Card, Show } from "./ui";

/** How much of the on-chain ceiling is in use, as a bar. */
function Utilisation({ c }: { c: ContractCard }) {
  const pctFact = c.facts.find((f) => f.label.includes("Share of the ceiling"));
  const pct = pctFact?.value ? Number.parseFloat(pctFact.value) : null;
  if (pct === null || !Number.isFinite(pct)) return null;

  // Above 80% of the on-chain ceiling is worth flagging before it binds.
  const tight = pct > 80;
  return (
    <div className="px-4 pb-3">
      <div className="h-1.5 rounded overflow-hidden bg-raised" aria-hidden="true">
        <div
          className={tight ? "bg-shielded h-full" : "bg-approved h-full"}
          style={{ width: `${Math.min(100, Math.max(0.5, pct))}%` }}
        />
      </div>
      <p className="text-xs text-ink-faint mt-1.5 leading-relaxed">
        {tight
          ? `Using ${pctFact?.value} of the ceiling. The limit is close to binding.`
          : `Using ${pctFact?.value} of the ceiling it is allowed.`}
      </p>
    </div>
  );
}

function ContractPanel({ c, explorer }: { c: ContractCard; explorer: string }) {
  return (
    <Card
      title={c.name}
      meta={
        c.address ? (
          <a
            href={`${explorer}${c.address}`}
            target="_blank"
            rel="noreferrer noopener"
            className="num text-xs text-telemetry hover:underline inline-flex items-center gap-1"
          >
            {c.address.slice(0, 8)}…{c.address.slice(-4)}
            <ExternalLink size={10} />
          </a>
        ) : null
      }
    >
      <div className="px-4 py-3 border-b hair">
        <p className="text-xs text-ink-soft leading-relaxed">{c.plain}</p>
      </div>

      {c.facts.map((f) => (
        <div
          key={f.label}
          className="px-4 py-2.5 border-b hair flex items-baseline justify-between gap-3"
        >
          <span className="text-xs text-ink-faint">{f.label}</span>
          {/* Absent stays absent. A dash is honest; a zero is a claim nobody measured. */}
          {f.value === null ? (
            <span className="text-xs text-shielded">could not read</span>
          ) : (
            <span className="num text-sm text-ink">{f.value}</span>
          )}
        </div>
      ))}

      <Utilisation c={c} />

      {c.status ? (
        <div className="px-4 py-3">
          <Badge
            icon={c.status.tone === "critical" ? ShieldAlert : ShieldCheck}
            tone={c.status.tone}
          >
            {c.status.text}
          </Badge>
        </div>
      ) : null}
    </Card>
  );
}

export function Machine() {
  const feed = usePolled<Contracts>(loadContracts, POLL.contracts);

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-6">
      <div className="mb-4">
        <h2 className="text-lg text-ink">What is running, right now</h2>
        <p className="text-sm text-ink-soft mt-1 leading-relaxed max-w-[62ch]">
          Six contracts on X Layer do the work. Everything below is read from them on this refresh,
          not from anything the app remembers. Each one links to the public explorer so you can
          check it yourself.
        </p>
        {feed.state === "ready" ? (
          <p className="flex items-center gap-1.5 text-xs text-ink-faint mt-2">
            <Activity
              size={11}
              className={feed.freshness.live ? "text-approved pulse" : "text-shielded"}
            />
            chain {feed.value.chain_id}
            {feed.freshness.live ? ", live" : `, ${ago(feed.value.fetched_at_utc) ?? "cached"}`}
          </p>
        ) : null}
      </div>

      <Show feed={feed} what="the contract state">
        {(v) => (
          <div className="grid gap-4 md:grid-cols-2">
            {v.contracts.map((c) => (
              <ContractPanel key={c.contract} c={c} explorer={v.explorer} />
            ))}
          </div>
        )}
      </Show>
    </div>
  );
}
