/**
 * Your limits. THE PRODUCT, visible before anyone connects anything.
 *
 * WHAT WAS WRONG. The limit control lived inside the vault panel and rendered only AFTER a wallet
 * connected. Someone arriving at the page saw a Connect button and a token list, and nothing at
 * all about the thing the whole system exists to do. The single most important promise — you set
 * a cap and the agent cannot exceed it — was behind a wallet connection, which is exactly backwards:
 * the promise is the reason to connect.
 *
 * So the limits are shown first, always, with the real on-chain values, and the connect step comes
 * after. Nothing here is a mock-up of a limit: every number is read from a deployed contract, and
 * when a read fails the row says so rather than showing a plausible figure.
 *
 * TWO LAYERS OF LIMIT, and the distinction is the product:
 *   YOURS      the cap you set on your own deposit. Only ever lowered.
 *   THE RWA    a second set of refusals that only mean anything for a real-world asset:
 *   GUARD'S    price divergence, oracle staleness, redemption windows, issuer pause.
 */

import {
  AlertCircle,
  Clock,
  ExternalLink,
  Lock,
  ShieldCheck,
  TrendingDown,
  Wallet as WalletIcon,
} from "lucide-react";
import { POLL, ago, loadRwaState, usePolled, type RwaState } from "../lib/feed";
import { Badge, Card, Show } from "./ui";

/** The four rules the deployed RWA guard enforces, each with its live value. */
function RwaRules({ s }: { s: RwaState }) {
  const icons = [TrendingDown, Clock, Clock, ShieldCheck];
  return (
    <>
      {s.rules.map((r, i) => {
        const Icon = icons[i] ?? ShieldCheck;
        return (
          <div key={r.name} className="px-4 py-3 border-b hair last:border-b-0">
            <div className="flex items-baseline justify-between gap-3">
              <span className="flex items-center gap-2 text-sm text-ink">
                <Icon size={14} className="text-approved shrink-0" />
                {r.name}
              </span>
              {/* A value that could not be read says so. A plausible number in its place would be
                  the worst thing this panel could do: it would look like a verified limit. */}
              {r.display ? (
                <span className="num text-sm text-approved shrink-0">{r.display}</span>
              ) : (
                <span className="text-xs text-shielded shrink-0">could not read</span>
              )}
            </div>
            <p className="text-xs text-ink-faint mt-1 leading-relaxed">{r.plain}</p>
          </div>
        );
      })}
    </>
  );
}

export function Limits({ onConnect }: { onConnect?: () => void }) {
  const rwa = usePolled<RwaState>(loadRwaState, POLL.rwastate);

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-6 grid gap-4 lg:grid-cols-[minmax(0,1fr)_24rem]">
      <div className="min-w-0 flex flex-col gap-4">
        {/* THE PROMISE, FIRST, in one sentence a person finishes. */}
        <Card title="The limit you set">
          <div className="px-4 py-5">
            <p className="text-lg text-ink leading-snug max-w-[42ch]">
              You decide the most this agent may ever risk in a single trade. It cannot go above
              that number.
            </p>
            <p className="text-sm text-ink-soft mt-3 leading-relaxed max-w-[52ch]">
              Not "should not". Cannot. The limit lives in a contract on X Layer that has no code
              path to raise it, and the part of the agent that learns has no way to reach it at
              all.
            </p>

            <div className="mt-5 grid gap-3 sm:grid-cols-3">
              <div className="border hair rounded p-3">
                <ShieldCheck size={16} className="text-approved" />
                <div className="text-sm text-ink mt-2">Only ever lowered</div>
                <p className="text-xs text-ink-faint mt-1 leading-relaxed">
                  You can tighten it whenever you want. Nothing can loosen it, including the agent.
                </p>
              </div>
              <div className="border hair rounded p-3">
                <Lock size={16} className="text-approved" />
                <div className="text-sm text-ink mt-2">Your exit is never blocked</div>
                <p className="text-xs text-ink-faint mt-1 leading-relaxed">
                  Pausing stops the agent. It does not stop you withdrawing.
                </p>
              </div>
              <div className="border hair rounded p-3">
                <AlertCircle size={16} className="text-approved" />
                <div className="text-sm text-ink mt-2">No way around the check</div>
                <p className="text-xs text-ink-faint mt-1 leading-relaxed">
                  Code that tries to trade without approval does not run. It fails to build.
                </p>
              </div>
            </div>

            {onConnect ? (
              <button
                type="button"
                onClick={onConnect}
                className="mt-5 inline-flex items-center gap-2 px-4 py-2.5 rounded text-sm font-medium bg-approved text-bg hover:bg-approved/90"
              >
                <WalletIcon size={15} />
                Connect and set your limit
              </button>
            ) : null}
          </div>
        </Card>

        {/* THE RWA LAYER, live from the deployed guard. */}
        <Card
          title="Extra rules for real-world assets"
          meta={
            rwa.state === "ready" ? (
              <span className="text-xs">{ago(rwa.value.fetched_at_utc) ?? "live"}</span>
            ) : null
          }
        >
          <div className="px-4 py-3 border-b hair">
            <p className="text-xs text-ink-soft leading-relaxed">
              Assets backed by something in the real world can break in ways a normal token cannot:
              the price feed goes stale, the issuer halts, a redemption window opens. These four
              rules run on top of your own limit, and every value below is read from the contract
              enforcing it.
            </p>
          </div>
          <Show feed={rwa} what="the on-chain rules">
            {(s) => <RwaRules s={s} />}
          </Show>
        </Card>
      </div>

      <aside className="flex flex-col gap-4">
        <Card title="Enforced by">
          <Show feed={rwa} what="contract addresses">
            {(s) => (
              <>
                <div className="px-4 py-3 border-b hair">
                  <div className="text-xs text-ink-faint">The rules</div>
                  <a
                    href={`${s.explorer}${s.guard_address}`}
                    target="_blank"
                    rel="noreferrer noopener"
                    className="num text-xs text-telemetry hover:underline inline-flex items-center gap-1 mt-1"
                  >
                    {s.guard_address.slice(0, 10)}…{s.guard_address.slice(-6)}
                    <ExternalLink size={10} />
                  </a>
                </div>
                <div className="px-4 py-3 border-b hair">
                  <div className="text-xs text-ink-faint">The vault holding the assets</div>
                  <a
                    href={`${s.explorer}${s.vault_address}`}
                    target="_blank"
                    rel="noreferrer noopener"
                    className="num text-xs text-telemetry hover:underline inline-flex items-center gap-1 mt-1"
                  >
                    {s.vault_address.slice(0, 10)}…{s.vault_address.slice(-6)}
                    <ExternalLink size={10} />
                  </a>
                </div>
                <div className="px-4 py-3 flex flex-wrap gap-2">
                  {s.vault_paused === false ? (
                    <Badge icon={ShieldCheck} tone="approved">
                      running
                    </Badge>
                  ) : s.vault_paused === true ? (
                    <Badge icon={Lock} tone="shielded">
                      paused, withdrawals still work
                    </Badge>
                  ) : null}
                  <Badge icon={ShieldCheck} tone="telemetry">
                    X Layer, chain {s.chain_id}
                  </Badge>
                </div>
                {s.unreadable.length > 0 ? (
                  <div className="px-4 pb-3">
                    <p className="text-xs text-shielded leading-relaxed">
                      {s.unreadable.length} value
                      {s.unreadable.length === 1 ? "" : "s"} could not be read from the chain on
                      this refresh, and are shown as unread rather than guessed.
                    </p>
                  </div>
                ) : null}
              </>
            )}
          </Show>
        </Card>
      </aside>
    </div>
  );
}
