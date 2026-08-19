/**
 * The trade surface. This is the product.
 *
 * WHAT A PERSON CAME HERE TO DO: see what they can trade, see what it costs, and know the agent
 * cannot lose more than they allowed. Everything on this screen serves one of those three. The
 * previous version led with a decision journal, a refusal ledger and evidence identifiers, which
 * answer a question nobody arriving here is asking.
 *
 * EVERY TOKEN, NOT A CURATED PAIR. The list is `universe.json`: whatever X Layer lists, priced and
 * route-checked on this run. A token that cannot be priced or cannot be routed is shown as such
 * and cannot be selected, because inviting someone to trade an unroutable token is how they lose
 * money to a failed transaction.
 */

import { useMemo, useState } from "react";
import {
  ArrowRight,
  CheckCircle2,
  Lock,
  Search,
  ShieldAlert,
  ShieldCheck,
  Zap,
} from "lucide-react";
import {
  POLL,
  loadChain,
  loadDepth,
  loadDetails,
  loadUniverse,
  money,
  usePolled,
  type Chain,
  type Depth,
  type Details,
  type Token,
  type Universe,
} from "../lib/feed";
import { Badge, Card, Show, cn } from "./ui";
import { Vault } from "./vault";
import { MissingDetail, TokenDetailPanel } from "./token-detail";

function TokenRow({
  t,
  quote,
  selected,
  onPick,
}: {
  t: Token;
  quote: string;
  selected: boolean;
  onPick: (t: Token) => void;
}) {
  const tradable = t.routable && t.price !== null;
  const price = money(t.price);

  return (
    <button
      type="button"
      disabled={!tradable}
      onClick={() => onPick(t)}
      aria-pressed={selected}
      className={cn(
        "w-full text-left grid grid-cols-[1fr_auto] items-center gap-3 px-4 py-2.5 border-b hair",
        tradable ? "hover:bg-raised cursor-pointer" : "opacity-45 cursor-not-allowed",
        selected && "bg-raised",
      )}
    >
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-sm text-ink font-medium">{t.symbol}</span>
          {!tradable ? (
            <Badge icon={ShieldAlert} tone="shielded">
              {t.price === null ? "no price" : "cannot trade"}
            </Badge>
          ) : null}
        </div>
        <div className="text-xs text-ink-faint truncate">
          {/* The router's own explanation, in place of the venue list, when it declined. A person
              deciding what to trade needs the reason before they commit, not after. */}
          {tradable
            ? t.venues.length > 0
              ? t.venues.join(", ")
              : t.name
            : (t.note ?? t.name)}
        </div>
      </div>
      <div className="text-right shrink-0">
        {price ? (
          <>
            <div className="num text-sm text-ink">${price}</div>
            <div className="text-xs text-ink-faint">per {t.symbol}</div>
          </>
        ) : (
          <span className="text-xs text-ink-faint">unpriced</span>
        )}
      </div>
      <span className="sr-only">{tradable ? `Trade ${t.symbol} for ${quote}` : "Not tradable"}</span>
    </button>
  );
}

/** The measured cost of size. Real quotes at real sizes, not a formula. */
function CostOfSize({ depth }: { depth: Depth }) {
  return (
    <Card
      title="What it costs to trade bigger"
      meta={<span className="num">{depth.pair}</span>}
    >
      <div className="px-4 py-3">
        <p className="text-xs text-ink-soft leading-relaxed">
          Larger trades get worse prices, because they use up the cheap liquidity first. These are
          real quotes at each size.
        </p>
      </div>
      <div className="border-t hair">
        {depth.rungs.map((r) => (
          <div
            key={r.size}
            className="grid grid-cols-[5rem_1fr_auto] items-center gap-3 px-4 py-2 border-b hair last:border-b-0"
          >
            <span className="num text-sm text-ink">{r.size}</span>
            <div className="min-w-0">
              <div className="num text-sm text-ink">${money(r.unit_price)}</div>
              <div className="text-xs text-ink-faint truncate">
                {r.venues.length} {r.venues.length === 1 ? "pool" : "pools"}
              </div>
            </div>
            {r.within_tolerance ? (
              <Badge icon={CheckCircle2} tone="approved">
                good price
              </Badge>
            ) : (
              <Badge icon={ShieldAlert} tone="shielded">
                too expensive
              </Badge>
            )}
          </div>
        ))}
      </div>
      <div className="px-4 py-3 border-t hair flex items-start gap-2">
        <ShieldCheck size={14} className="text-approved shrink-0 mt-0.5" />
        <p className="text-xs text-ink-soft leading-relaxed">
          The agent will not trade more than{" "}
          <span className="num text-ink">{depth.max_safe_size}</span> at once, because past that the
          price gets worse than the {depth.slippage_tolerance_bps} basis point limit allows.
        </p>
      </div>
    </Card>
  );
}

export function Trade() {
  const universe = usePolled<Universe>(loadUniverse, POLL.universe);
  const depth = usePolled<Depth>(loadDepth, POLL.depth);
  const [query, setQuery] = useState("");
  const [picked, setPicked] = useState<Token | null>(null);
  // Detail records for every listed token, so any row can open. Polled slowly: holder counts and
  // pool composition do not move at price speed.
  const details = usePolled<Details>(loadDetails, POLL.detail);
  const chain = usePolled<Chain>(loadChain, 300000);
  const [openSymbol, setOpenSymbol] = useState<string | null>(null);

  const tokens = universe.state === "ready" ? universe.value.tokens : [];
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    const rows = q
      ? tokens.filter(
          (t) => t.symbol.toLowerCase().includes(q) || t.name.toLowerCase().includes(q),
        )
      : tokens;
    // Tradable first: a list that leads with things you cannot trade wastes the reader's attention.
    return [...rows].sort((a, b) => {
      const at = a.routable && a.price !== null ? 0 : 1;
      const bt = b.routable && b.price !== null ? 0 : 1;
      return at - bt || a.symbol.localeCompare(b.symbol);
    });
  }, [tokens, query]);

  return (
    // THE VAULT COLUMN COMES FIRST BELOW THE LARGE BREAKPOINT. Previously the token list occupied
    // the whole viewport and everything a person could actually DO sat in a right-hand column
    // pushed below the fold, so clicking a token appeared to do nothing at all. `order` puts the
    // action first on narrow screens without changing the desktop layout.
    <div className="mx-auto w-full max-w-6xl px-4 py-6 grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
      <div className="flex flex-col gap-4 min-w-0 order-2 lg:order-1">
        <Card
          title="Tokens you can trade"
          meta={
            universe.state === "ready" ? (
              <span className="num">
                {universe.value.tradable_count} of {universe.value.token_count}
              </span>
            ) : null
          }
        >
          <div className="px-4 py-3 border-b hair">
            <label className="relative block">
              <span className="sr-only">Search tokens</span>
              <Search
                size={14}
                className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint pointer-events-none"
              />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search"
                className="w-full bg-raised border hair rounded px-9 py-2 text-sm text-ink placeholder:text-ink-faint"
              />
            </label>
          </div>

          <Show feed={universe} what="the token list">
            {(u) =>
              filtered.length === 0 ? (
                <p className="px-4 py-6 text-sm text-ink-faint">
                  No token matches “{query}”.
                </p>
              ) : (
                <div className="max-h-[26rem] overflow-y-auto">
                  {filtered.map((t) => (
                    <TokenRow
                      key={t.address}
                      t={t}
                      quote={u.quote_symbol}
                      selected={picked?.address === t.address}
                      onPick={(tok) => {
                        setPicked(tok);
                        setOpenSymbol(tok.symbol);
                      }}
                    />
                  ))}
                </div>
              )
            }
          </Show>
        </Card>

        <Show feed={depth} what="pricing detail">
          {(d) => <CostOfSize depth={d} />}
        </Show>
      </div>

      <aside className="flex flex-col gap-4 order-1 lg:order-2">
        <Vault />

        <Card title="Your trade">
          {picked ? (
            <div className="px-4 py-4">
              <div className="flex items-center gap-3">
                <span className="text-lg text-ink font-medium">{picked.symbol}</span>
                <ArrowRight size={16} className="text-ink-faint" />
                <span className="text-lg text-ink font-medium">
                  {universe.state === "ready" ? universe.value.quote_symbol : ""}
                </span>
              </div>
              <div className="num text-2xl text-ink mt-3">${money(picked.price)}</div>
              <p className="text-xs text-ink-faint mt-1">{picked.name}</p>
              {picked.venues.length > 0 ? (
                <div className="mt-4 flex items-start gap-2">
                  <Zap size={14} className="text-telemetry shrink-0 mt-0.5" />
                  <p className="text-xs text-ink-soft leading-relaxed">
                    Routed through {picked.venues.join(", ")}.
                  </p>
                </div>
              ) : null}
            </div>
          ) : (
            <div className="px-4 py-6">
              <p className="text-sm text-ink">Pick a token to see its price and route.</p>
              <p className="text-xs text-ink-faint mt-1 leading-relaxed">
                Greyed-out tokens have no price or no route on X Layer right now, so they cannot be
                traded safely.
              </p>
            </div>
          )}
        </Card>

        {/* The three promises, in a person's words. These are the reason to trust the product with
            money, so they sit beside the action rather than behind a tab. */}
        <Card title="What protects you">
          <ul className="divide-y divide-line">
            <li className="px-4 py-3 flex items-start gap-2.5">
              <ShieldCheck size={15} className="text-approved shrink-0 mt-0.5" />
              <div>
                <p className="text-sm text-ink">Your limit only tightens</p>
                <p className="text-xs text-ink-faint mt-0.5 leading-relaxed">
                  You set the most the agent may risk. Nothing can raise it later, not even the
                  agent learning it could do better.
                </p>
              </div>
            </li>
            <li className="px-4 py-3 flex items-start gap-2.5">
              <Lock size={15} className="text-approved shrink-0 mt-0.5" />
              <div>
                <p className="text-sm text-ink">You can always withdraw</p>
                <p className="text-xs text-ink-faint mt-0.5 leading-relaxed">
                  Pausing stops the agent. It never stops you taking your money out.
                </p>
              </div>
            </li>
            <li className="px-4 py-3 flex items-start gap-2.5">
              <CheckCircle2 size={15} className="text-approved shrink-0 mt-0.5" />
              <div>
                <p className="text-sm text-ink">Every trade is checked first</p>
                <p className="text-xs text-ink-faint mt-0.5 leading-relaxed">
                  A trade that fails the safety check cannot be sent. There is no path around it.
                </p>
              </div>
            </li>
          </ul>
        </Card>
      </aside>

      {/* THE DETAIL PANEL. Every row opens; there is no token whose row is decorative. When the
          record has not arrived yet the fallback says so, because a click that does nothing is
          indistinguishable from a broken app. */}
      {openSymbol ? (
        details.state === "ready" && details.value.tokens[openSymbol] ? (
          <TokenDetailPanel
            t={details.value.tokens[openSymbol]}
            onClose={() => setOpenSymbol(null)}
            explorerBase={chain.state === "ready" ? chain.value.explorer_address_base : undefined}
          />
        ) : (
          <MissingDetail symbol={openSymbol} onClose={() => setOpenSymbol(null)} />
        )
      ) : null}
    </div>
  );
}
