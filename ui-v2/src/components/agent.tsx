/**
 * What the agent is doing with your money.
 *
 * THE SURFACE THAT WAS MISSING. The app showed prices and let you deposit, but nothing showed the
 * agent actually working — which is the entire reason someone would use this rather than a wallet.
 * Weeks of risk-engine work existed and none of it was visible.
 *
 * THE REFUSAL COUNT IS THE HEADLINE, NOT A FOOTNOTE. 688 declined out of 720 considered is not a
 * failure rate; it is the product working. Framing matters and so does honesty: the number is
 * large, it is shown at full size, and it is explained rather than buried or spun.
 *
 * NO ENGINEERING VOCABULARY REACHES THIS SCREEN. `InsufficientFreeMargin { would_leave: 22 }`
 * becomes "Not enough money left to cover it safely". The translation happens in
 * scripts/agent_activity.py against the agent's own journal, so this component renders sentences
 * rather than inventing them.
 */

import { Activity, ArrowUpRight, CheckCircle2, ExternalLink, Pause, ShieldCheck } from "lucide-react";
import { POLL, ago, loadActivity, usePolled, type Agent } from "../lib/feed";
import { Card, Show } from "./ui";

/** The one number that explains the product, at the size that says so. */
function Headline({ a }: { a: Agent }) {
  const declined = a.options_declined;
  const considered = a.options_considered;
  const pct = considered ? Math.round((declined / considered) * 100) : 0;

  return (
    <Card
      title="Your protection, working"
      meta={
        <span className="flex items-center gap-1.5">
          <Activity size={11} className="text-approved pulse" />
          {a.status === "watching" ? "watching the market" : a.status}
        </span>
      }
    >
      <div className="px-4 py-5">
        <div className="num text-4xl text-approved leading-none">{declined}</div>
        <p className="text-sm text-ink mt-2">trades stopped before they happened</p>
        <p className="text-xs text-ink-faint mt-1 leading-relaxed">
          The agent looked at {considered} possible trades and made {a.trades_made}. It turned down
          the other {declined} — {pct}% — because they broke a rule you set. A high number here
          means the limits are doing their job.
        </p>
      </div>

      {/* Why, ranked. The top reason is the one worth reading. */}
      <div className="border-t hair">
        {a.why_declined.slice(0, 5).map((r) => (
          <div
            key={r.reason}
            className="px-4 py-2.5 border-b hair last:border-b-0 flex items-baseline justify-between gap-3"
          >
            <span className="text-sm text-ink-soft">{r.reason}</span>
            <span className="num text-sm text-ink-faint shrink-0">{r.count}</span>
          </div>
        ))}
      </div>
    </Card>
  );
}

export function AgentView() {
  const act = usePolled<Agent>(loadActivity, POLL.activity);

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-6 grid gap-4 lg:grid-cols-[minmax(0,1fr)_24rem]">
      <div className="min-w-0 flex flex-col gap-4">
        <Show feed={act} what="the agent's activity">
          {(a) => (
            <>
              <Headline a={a} />

              <Card
                title="Every decision it made"
                meta={a.market ? <span className="num">{a.market}</span> : null}
              >
                <div className="px-4 py-3 border-b hair">
                  <p className="text-xs text-ink-soft leading-relaxed">
                    Most of the time the right move is to do nothing. Each row is one moment the
                    agent looked at the market and chose.
                  </p>
                </div>
                {a.decisions.length === 0 ? (
                  <p className="px-4 py-6 text-sm text-ink-faint">
                    The agent has not made any decisions yet.
                  </p>
                ) : (
                  a.decisions.map((d) => (
                    <div key={d.id} className="px-4 py-3 border-b hair last:border-b-0">
                      <div className="flex items-baseline justify-between gap-3">
                        <span
                          className={`text-sm ${d.acted ? "text-approved" : "text-ink-soft"}`}
                        >
                          {d.acted ? (
                            <ArrowUpRight size={13} className="inline mr-1" />
                          ) : (
                            <Pause size={12} className="inline mr-1" />
                          )}
                          {d.did}
                        </span>
                        <span className="text-xs text-ink-faint shrink-0 num">
                          {d.considered} looked at
                        </span>
                      </div>
                      {d.saw ? (
                        <p className="text-xs text-ink-faint mt-1 leading-snug">{d.saw}</p>
                      ) : null}
                      {d.refused > 0 ? (
                        <p className="text-xs text-ink-faint mt-1">
                          {d.refused} stopped by your limits
                        </p>
                      ) : null}
                    </div>
                  ))
                )}
              </Card>
            </>
          )}
        </Show>
      </div>

      <aside className="flex flex-col gap-4">
        <Show feed={act} what="trade history">
          {(a) => (
            <Card title="Real trades on the blockchain">
              {a.real_swaps.length === 0 ? (
                <div className="px-4 py-5">
                  <p className="text-sm text-ink">No trades executed yet.</p>
                  <p className="text-xs text-ink-faint mt-1 leading-relaxed">
                    When the agent trades, every one appears here with a link anyone can check.
                  </p>
                </div>
              ) : (
                a.real_swaps.map((s) => (
                  <div key={s.tx} className="px-4 py-3 border-b hair last:border-b-0">
                    <div className="flex items-center gap-2">
                      <CheckCircle2 size={14} className="text-approved shrink-0" />
                      <span className="text-sm text-ink">
                        {s.from} → {s.to}
                      </span>
                    </div>
                    <p className="text-xs text-ink-faint mt-1">
                      through {s.venues} · {ago(s.at) ?? ""}
                    </p>
                    <a
                      href={s.explorer}
                      target="_blank"
                      rel="noreferrer noopener"
                      className="text-xs text-telemetry hover:underline inline-flex items-center gap-1 mt-1"
                    >
                      Check it yourself
                      <ExternalLink size={10} />
                    </a>
                  </div>
                ))
              )}
            </Card>
          )}
        </Show>

        {/* The three promises. Stated as what they mean, not as what they are called. */}
        <Card title="Rules the agent cannot break">
          <ul className="divide-y divide-line">
            <li className="px-4 py-3 flex items-start gap-2.5">
              <ShieldCheck size={15} className="text-approved shrink-0 mt-0.5" />
              <div>
                <p className="text-sm text-ink">It cannot risk more than you allow</p>
                <p className="text-xs text-ink-faint mt-0.5 leading-relaxed">
                  Your limit is stored on the blockchain. Raising it is impossible — not difficult,
                  impossible.
                </p>
              </div>
            </li>
            <li className="px-4 py-3 flex items-start gap-2.5">
              <ShieldCheck size={15} className="text-approved shrink-0 mt-0.5" />
              <div>
                <p className="text-sm text-ink">It cannot learn its way around the rules</p>
                <p className="text-xs text-ink-faint mt-0.5 leading-relaxed">
                  The part that learns has no ability to touch the part that limits. They are
                  separated in the code itself.
                </p>
              </div>
            </li>
            <li className="px-4 py-3 flex items-start gap-2.5">
              <ShieldCheck size={15} className="text-approved shrink-0 mt-0.5" />
              <div>
                <p className="text-sm text-ink">It cannot skip the check</p>
                <p className="text-xs text-ink-faint mt-0.5 leading-relaxed">
                  A trade that has not been approved cannot even be written. The program refuses to
                  build.
                </p>
              </div>
            </li>
          </ul>
        </Card>
      </aside>
    </div>
  );
}
