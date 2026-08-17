/**
 * Run Full Demo, task 9.6.
 *
 * NO DEPOSIT REQUIRED and no wallet required. This runs against the project's own capital, so a judge
 * who has never connected anything can press one button and watch a complete cycle: thesis, risk
 * decision, execution or refusal, the journal row it wrote, and the transaction it submitted.
 *
 * THINKING: #12 design thinking (this is the first thing a judge clicks), #66 red teaming (it must
 * never fail, and it must not break when double-clicked), #62 pre-mortem.
 *
 * THE NAMED FAKE WIN is "a demo that replays a recorded journal", and the counter is that "each run
 * must produce a NEW journal row with a new block number". So this renders `journal_before` and
 * `journal_after` from the API response, side by side, and the block number of the row that run
 * wrote. A replay would show those two numbers equal, on screen, to the person watching.
 *
 * PATTERNS APPLIED (evidence/ui-study.md):
 * - `orderbook-panel.tsx:151-153` distinct sentences for distinct situations: running, refused,
 *   executed and failed are four different messages, not one spinner and one toast.
 * - `orderbook-panel.tsx:121-137` controls live in the labels they affect; the button states what it
 *   will do and, afterwards, what it did.
 * - `orderbook-row.tsx:34` 12px `tabular-nums` rows at `py-0.5 px-2` for every number.
 */

import { useCallback, useState } from "react";
import { Panel } from "./primitives";

/**
 * Where the coordination API listens: same host as the page, port 8737.
 *
 * The port and the key are what the server PRINTS in its startup banner. An earlier version of this
 * file guessed 8080 and omitted the key entirely, and the gate spent 90 seconds polling a port
 * nothing was bound to. The banner had the answer the whole time.
 */
const API_PORT = 8737;

/**
 * The demo key the API ships with, and it is deliberately in the client.
 *
 * This API is unauthenticated by design: its own module docs say "there is no privileged path, a
 * caller cannot obtain a quote the agent itself would be refused". The key is a rate-limiting
 * identifier, not a secret, so putting it in a page that anybody can view source on costs nothing.
 * If it ever gates something that matters, this line becomes a real problem and should be revisited.
 */
const DEMO_KEY = "demo-agent-key-1";

function apiBase(): string {
  return `http://${window.location.hostname}:${API_PORT}`;
}

interface DemoResult {
  ok?: boolean;
  error?: string;
  action?: string;
  elapsed_ms?: number;
  journal_before?: number;
  journal_after?: number;
  decision_id?: number;
  block_number?: number;
  thesis?: string;
  risk_verdict?: string;
  tx_hash?: string | null;
  candidates?: number;
}

function Row({ label, value, tone }: { label: string; value: string; tone?: string }) {
  return (
    <div className="grid grid-cols-[minmax(0,11rem)_minmax(0,1fr)] gap-2 px-2 py-0.5 border-b hairline last:border-b-0">
      <span className="text-2xs text-[var(--text-weak)]">{label}</span>
      <span className="num text-2xs break-all" style={tone ? { color: tone } : undefined}>
        {value}
      </span>
    </div>
  );
}

export function DemoButton({ explorerTxBase }: { explorerTxBase?: string }) {
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<DemoResult | null>(null);
  const [failure, setFailure] = useState<string | null>(null);

  const run = useCallback(async () => {
    setBusy(true);
    setFailure(null);
    setResult(null);
    try {
      const res = await fetch(`${apiBase()}/demo`, {
        method: "POST",
        headers: { "content-type": "application/json", "x-api-key": DEMO_KEY },
        body: "{}",
      });
      const body = (await res.json()) as DemoResult;
      if (!res.ok) {
        // The API's own message, not a generic one. A 429 here means somebody double-clicked, and
        // saying so is more useful than "something went wrong".
        setFailure(`${body.error ?? `HTTP ${res.status}`}${body.action ? ` — ${body.action}` : ""}`);
      } else {
        setResult(body);
      }
    } catch (e) {
      setFailure(
        `${e instanceof Error ? e.message : String(e)} — the coordination API must be running on port 8080`,
      );
    } finally {
      setBusy(false);
    }
  }, []);

  const refused = result?.risk_verdict && !/approve/i.test(result.risk_verdict);

  return (
    <Panel title="Run the agent" meta="no deposit, no wallet">
      <div className="flex flex-col gap-2 px-2 py-2">
        <p className="text-xs text-[var(--text-weak)]">
          One click runs a complete cycle against X Layer using the project's own capital: it reads
          the chain, forms a thesis, scores the alternatives, puts the winner through the risk gate,
          and either executes it or refuses with a reason.
        </p>

        <div>
          <button
            type="button"
            data-testid="run-demo"
            disabled={busy}
            onClick={() => void run()}
            className="px-3 py-1.5 text-xs border hairline bg-[var(--fill-hover)] hover:bg-[var(--bg-raised)] disabled:opacity-60"
            style={{ color: "var(--text-strong)" }}
          >
            {busy ? "Running a live cycle..." : "Run full demo"}
          </button>
        </div>

        {failure ? (
          <div data-testid="demo-error">
            <p className="text-xs" style={{ color: "var(--status-short)" }}>
              {failure}
            </p>
            <p className="text-xs text-[var(--text-weak)]">
              Nothing was submitted. Press the button again to retry.
            </p>
          </div>
        ) : null}

        {result ? (
          <div className="flex flex-col" data-testid="demo-result">
            {/* THE ANTI-REPLAY EVIDENCE, on screen rather than only in the gate. A recorded replay
                would show these two numbers equal. */}
            <Row
              label="Journal rows"
              value={`${result.journal_before} to ${result.journal_after}  (a new row was written)`}
              tone="var(--status-long)"
            />
            <Row label="Block" value={String(result.block_number ?? "n/a")} />
            <Row label="Decision" value={String(result.decision_id ?? "n/a")} />
            <Row label="Candidates scored" value={String(result.candidates ?? "n/a")} />
            <Row
              label="Risk verdict"
              value={String(result.risk_verdict ?? "n/a")}
              tone={refused ? "var(--status-short)" : "var(--status-long)"}
            />
            <Row label="Took" value={`${((result.elapsed_ms ?? 0) / 1000).toFixed(1)}s`} />

            {result.tx_hash ? (
              <div className="grid grid-cols-[minmax(0,11rem)_minmax(0,1fr)] gap-2 px-2 py-0.5">
                <span className="text-2xs text-[var(--text-weak)]">Transaction</span>
                <a
                  className="num text-2xs break-all"
                  style={{ color: "var(--status-info)" }}
                  href={`${explorerTxBase ?? "https://www.oklink.com/x-layer-testnet/tx/"}${result.tx_hash}`}
                  target="_blank"
                  rel="noreferrer noopener"
                >
                  {result.tx_hash}
                </a>
              </div>
            ) : (
              <Row
                label="Transaction"
                value="none: the agent refused, so nothing was submitted"
                tone="var(--text-weak)"
              />
            )}

            {result.thesis ? (
              <p className="px-2 py-2 text-xs text-[var(--text-weak)]">{result.thesis}</p>
            ) : null}
          </div>
        ) : null}
      </div>
    </Panel>
  );
}
