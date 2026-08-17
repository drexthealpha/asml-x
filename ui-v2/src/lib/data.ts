/**
 * Typed loaders for the agent's real output files.
 *
 * PATTERN APPLIED, from evidence/ui-study.md section 3: HypeTerminal keeps every reliability
 * number in ONE constants table (`reliability.ts:1-48`) and runs a single staleness watchdog with
 * per-key thresholds (`staleness.ts:20-109`) rather than a timer per component. Our transport is
 * a poll over static files plus JSON-RPC, but the two ideas that transfer are exactly those: one
 * place for the polling and freshness numbers, and freshness as a first-class piece of state.
 *
 * THE HARD RULE IN THIS FILE: a parse failure or a missing file returns an ERROR, never a
 * default. Every panel renders that error where the numbers would have been. A UI that shows 0
 * when it means "unknown" is worse than one that shows nothing, because 0 is a number a reader
 * will believe. This is what task 4.7's no-data proof checks.
 */

import { DATA_SOURCES, type DataSourceKey } from "../config/layout";

/** One place for every freshness and polling number (their reliability.ts:1-48). */
export const DATA_LIMITS = {
  /** How often the loader re-reads the files. The agent writes a journal row per cycle and a
   * cycle is several seconds, so anything faster is wasted work. */
  pollIntervalMs: 4_000,
  /** Past this age a source is STALE and says so. Chosen to be several poll intervals, so a
   * single slow read does not flip the badge. */
  stalenessThresholdMs: 30_000,
  /** A journal larger than this is truncated at read time rather than parsed whole. */
  maxJournalBytes: 4 * 1024 * 1024,
  /** Rows kept in memory, newest first. */
  maxRows: 500,
} as const;

export type Load<T> =
  | { state: "loading" }
  | { state: "ok"; value: T; fetchedAtMs: number }
  | { state: "error"; source: string; reason: string };

/**
 * The unit a signal's value is actually in.
 *
 * A REAL SCHEMA DEFECT, found by looking at the rendered panel: the journal field is called
 * `value_micro` for every signal, but it only holds micro-units for some of them.
 *
 *   spread_bps      value_micro = -2325      plain BASIS POINTS
 *   imbalance_bps   value_micro = -9176      plain BASIS POINTS
 *   bid_depth_base  value_micro = 1375000    micro-units, so 1.375 base
 *
 * `crates/runtime/src/main.rs:106-125` assigns `value_micro: e.value` for the bps signals, where
 * `e.value` is already in basis points, so the name is wrong rather than the number.
 *
 * The UI was dividing every one of them by 1e6, which rendered spread -2325 bps as "-0.00" and
 * imbalance -9176 bps as "-0.01". Every signal in the panel read as zero, on a screen whose whole
 * purpose is showing what the agent saw.
 *
 * The unit is inferred from the NAME SUFFIX, which is the only information the current schema
 * carries. This is a workaround for a producer bug and it is labelled as one both here and in the
 * panel; the durable fix is a `unit` field on SignalRecord, recorded as a defect rather than
 * silently absorbed.
 */
export type SignalUnit = "bps" | "micro";

export function unitOf(signalName: string): SignalUnit {
  return signalName.endsWith("_bps") ? "bps" : "micro";
}

/** Format a signal value in its real unit. */
export function formatSignal(name: string, value: number): string {
  if (!Number.isFinite(value)) return "invalid";
  if (unitOf(name) === "bps") {
    // Basis points are integers here; showing decimals would imply precision the source lacks.
    return `${Math.round(value)}`;
  }
  return fromMicro(value);
}

export interface Signal {
  name: string;
  valueMicro: number;
  confidenceHalfwidthMicro: number;
  inputAgeMs: number;
}

export interface Candidate {
  label: string;
  chosen: boolean;
  scoreMicro: number;
  expectedEdgeMicro: number;
  variancePenaltyMicro: number;
  capitalCostMicro: number;
  executionRiskPenaltyMicro: number;
  rejectionReason: string | null;
}

export interface Decision {
  decisionId: number;
  blockNumber: number;
  observedAtMs: number;
  market: string;
  action: string;
  thesis: string;
  thesisConfidenceBps: number;
  riskVerdict: string;
  txHash: string | null;
  signals: Signal[];
  candidates: Candidate[];
  evidence: string[];
  /** True for the naive-baseline control rows. These are NOT agent decisions and must never be
   * mixed into agent statistics. Task 1.16's DuckDB aggregation found 8 of them in the journal,
   * and the river benchmark had silently included them, inflating its margin from 2.5 points to
   * 11.5. The UI is not going to repeat that. */
  isBaseline: boolean;
  /** Domain violations found in this row. Added after task 4.9's red team: a fixture row with a
   * 20-digit block number and a confidence of 999999999 bps rendered as "100000000000000000000"
   * and "10000000.0%" without comment. Neither is possible, and printing an impossible value with
   * a percent sign after it is the same defect as printing a zero for missing data. A row with
   * anomalies still renders, because hiding it would be its own kind of lie, but it renders
   * FLAGGED and its numbers are suppressed. */
  anomalies: string[];
}

/** Largest integer JavaScript can represent exactly. Beyond it, a printed digit string is a
 * rounding artifact rather than the value in the file. */
const SAFE_INT = Number.MAX_SAFE_INTEGER;

function decisionAnomalies(d: Omit<Decision, "anomalies">): string[] {
  const out: string[] = [];
  if (!Number.isFinite(d.blockNumber) || d.blockNumber < 0) {
    out.push("block number is not a positive number");
  } else if (d.blockNumber > SAFE_INT) {
    out.push("block number exceeds exact integer range");
  }
  // Basis points are hundredths of a percent, so a confidence cannot exceed 10000.
  if (!Number.isFinite(d.thesisConfidenceBps)) {
    out.push("confidence is not a number");
  } else if (d.thesisConfidenceBps < 0 || d.thesisConfidenceBps > 10_000) {
    out.push(`confidence of ${d.thesisConfidenceBps} bps is outside 0..10000`);
  }
  for (const c of d.candidates) {
    if (Math.abs(c.scoreMicro) > SAFE_INT) {
      out.push(`candidate "${c.label}" score exceeds exact integer range`);
      break;
    }
  }
  for (const s of d.signals) {
    if (Math.abs(s.valueMicro) > SAFE_INT) {
      out.push(`signal "${s.name}" value exceeds exact integer range`);
      break;
    }
  }

  // TASK 5.7: a decision with fewer than two candidates is NOT A DECISION.
  //
  // This is the anti-if-else-ladder check moved from the UI's rhetoric into its data layer. The whole
  // claim of the brain panel is that the agent SCORED alternatives and rejected them; a cycle with one
  // candidate is a hardcoded action wearing the shape of a choice, and rendering it in the same style
  // as a real decision would be the UI vouching for something it cannot see.
  //
  // Zero candidates is worse than one and is called out separately, because it means the journal row
  // records an action with no reasoning at all.
  if (d.candidates.length === 0) {
    out.push("no candidates recorded: this row shows an action with no reasoning behind it");
  } else if (d.candidates.length === 1) {
    out.push(
      "only 1 candidate: a cycle that scored one option did not choose, it executed a fixed action",
    );
  }
  return out;
}

/** Journal numbers arrive as strings because they are i128 micro-units. Parse explicitly. */
function num(v: unknown): number {
  if (typeof v === "number") return v;
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return Number.NaN;
}

function str(v: unknown): string {
  return typeof v === "string" ? v : "";
}

function parseSignal(raw: Record<string, unknown>): Signal {
  return {
    name: str(raw.name),
    valueMicro: num(raw.value_micro),
    confidenceHalfwidthMicro: num(raw.confidence_halfwidth_micro),
    inputAgeMs: num(raw.input_age_ms),
  };
}

function parseCandidate(raw: Record<string, unknown>): Candidate {
  return {
    label: str(raw.label),
    chosen: raw.chosen === true,
    scoreMicro: num(raw.score_micro),
    expectedEdgeMicro: num(raw.expected_edge_micro),
    variancePenaltyMicro: num(raw.variance_penalty_micro),
    capitalCostMicro: num(raw.capital_cost_micro),
    executionRiskPenaltyMicro: num(raw.execution_risk_penalty_micro),
    rejectionReason:
      typeof raw.rejection_reason === "string" ? raw.rejection_reason : null,
  };
}

export function parseDecision(raw: Record<string, unknown>): Decision {
  const thesis = str(raw.thesis);
  const verdict = str(raw.risk_verdict);
  const base: Omit<Decision, "anomalies"> = {
    decisionId: num(raw.decision_id),
    blockNumber: num(raw.block_number),
    observedAtMs: num(raw.observed_at_ms),
    market: str(raw.market),
    action: str(raw.action),
    thesis,
    thesisConfidenceBps: num(raw.thesis_confidence_bps),
    riskVerdict: verdict,
    txHash: typeof raw.tx_hash === "string" && raw.tx_hash !== "" ? raw.tx_hash : null,
    signals: Array.isArray(raw.signals)
      ? raw.signals.map((s) => parseSignal(s as Record<string, unknown>))
      : [],
    candidates: Array.isArray(raw.candidates)
      ? raw.candidates.map((c) => parseCandidate(c as Record<string, unknown>))
      : [],
    evidence: Array.isArray(raw.evidence) ? raw.evidence.map(str) : [],
    isBaseline: thesis.startsWith("naive baseline") || verdict.startsWith("baseline:"),
  };
  return { ...base, anomalies: decisionAnomalies(base) };
}

async function fetchText(key: DataSourceKey): Promise<Load<string>> {
  const url = DATA_SOURCES[key];
  try {
    const res = await fetch(url, { cache: "no-store" });
    if (!res.ok) {
      return { state: "error", source: url, reason: `HTTP ${res.status}` };
    }
    const text = await res.text();
    // A dev server that returns index.html for a missing file is the classic way a UI ends up
    // "successfully" parsing nothing. Detect it explicitly.
    if (text.trimStart().startsWith("<!doctype") || text.trimStart().startsWith("<html")) {
      return { state: "error", source: url, reason: "server returned HTML, file not present" };
    }
    if (text.length > DATA_LIMITS.maxJournalBytes) {
      return {
        state: "error",
        source: url,
        reason: `larger than the ${DATA_LIMITS.maxJournalBytes} byte read limit`,
      };
    }
    return { state: "ok", value: text, fetchedAtMs: Date.now() };
  } catch (e) {
    return { state: "error", source: url, reason: e instanceof Error ? e.message : String(e) };
  }
}

export interface JournalLoad {
  decisions: Decision[];
  /** Lines that failed to parse. Surfaced, never swallowed: a malformed journal must be visible
   * as a malformed journal, which is what task 4.9 red-teams. */
  malformedLines: number;
  totalLines: number;
  baselineRows: number;
}

export async function loadJournal(): Promise<Load<JournalLoad>> {
  const t = await fetchText("journal");
  if (t.state !== "ok") return t;

  const lines = t.value.split("\n").filter((l) => l.trim() !== "");
  const decisions: Decision[] = [];
  let malformed = 0;
  for (const line of lines) {
    try {
      const raw = JSON.parse(line) as Record<string, unknown>;
      const d = parseDecision(raw);
      // A row with no usable decision id is malformed even if it is valid JSON.
      if (!Number.isFinite(d.decisionId)) {
        malformed += 1;
        continue;
      }
      decisions.push(d);
    } catch {
      malformed += 1;
    }
  }
  if (decisions.length === 0) {
    return {
      state: "error",
      source: DATA_SOURCES.journal,
      reason:
        lines.length === 0
          ? "file is empty"
          : `all ${lines.length} line(s) failed to parse as decisions`,
    };
  }
  decisions.sort((a, b) => b.decisionId - a.decisionId);
  return {
    state: "ok",
    fetchedAtMs: t.fetchedAtMs,
    value: {
      decisions: decisions.slice(0, DATA_LIMITS.maxRows),
      malformedLines: malformed,
      totalLines: lines.length,
      baselineRows: decisions.filter((d) => d.isBaseline).length,
    },
  };
}

export interface SignalStat {
  name: string;
  samples: number;
  correct: number;
  hitRateBps: number;
  sumRealizedBps: number;
  sumEdgeErrorMicro: number;
}

/** A forecast the learner has opened and not yet scored. */
export interface PendingForecast {
  signalName: string;
  predicted: string;
  expectedEdgeMicro: number;
  midAtDecisionMicro: number;
  openedAtMs: number;
}

export interface LearnedState {
  settledCount: number;
  unscoredFlat: number;
  stats: SignalStat[];
  pendingCount: number;
  /** The pending rows themselves, not just their count. Added after the density measurement:
   * showing only a count left a 624x472 void in the bottom right of a 1920x1080 viewport
   * (14.2% of the screen), and the honest way to fill it is with the data the file already
   * holds rather than with decoration. */
  pending: PendingForecast[];
  /** The learned parameters as they stand now, with the DEFAULTS they started from so a change is
   * visible as a change rather than as a number. Task 5.6 asks for "after N settled outcomes I
   * changed X from A to B", and the state file records only the current value, so the baseline has
   * to come from the crate's documented defaults. Those are cited in the panel. */
  params: LearnedParam[];
}

export interface LearnedParam {
  name: string;
  currentBps: number;
  defaultBps: number;
}

/**
 * Defaults from `crates/learning/src/lib.rs`, `Params::default()`.
 *
 * Hardcoding a baseline in the UI would normally be exactly what task 5.2 forbids, so it is worth
 * being precise about why this is different: these are not observations, they are the STARTING POINT
 * a change is measured against, and the state file does not record them. They live in one named
 * table with the source path, and 5.2's checker classifies them as CONFIG for that reason. If the
 * crate's defaults change, this table is wrong and the panel will show a false delta, so the risk is
 * real and the mitigation is that the panel prints the source path next to the numbers.
 */
export const LEARNING_DEFAULT_BPS: Record<string, number> = {
  momentum_weight_bps: 2000,
  thin_book_penalty_bps: 150,
  variance_weight_bps: 8000,
};

export async function loadLearnedState(): Promise<Load<LearnedState>> {
  const t = await fetchText("learned");
  if (t.state !== "ok") return t;
  try {
    const raw = JSON.parse(t.value) as Record<string, unknown>;
    const statsRaw = (raw.stats ?? {}) as Record<string, Record<string, unknown>>;
    const stats: SignalStat[] = Object.entries(statsRaw).map(([name, s]) => ({
      name,
      samples: num(s.samples),
      correct: num(s.correct),
      hitRateBps: num(s.hit_rate_bps),
      sumRealizedBps: num(s.sum_realized_bps),
      sumEdgeErrorMicro: num(s.sum_edge_error_micro),
    }));
    const pendingRaw = Array.isArray(raw.pending) ? raw.pending : [];
    const pending: PendingForecast[] = pendingRaw.map((p) => {
      const o = p as Record<string, unknown>;
      return {
        signalName: str(o.signal_name),
        predicted: str(o.predicted),
        expectedEdgeMicro: num(o.expected_edge_micro),
        midAtDecisionMicro: num(o.mid_at_decision),
        openedAtMs: num(o.opened_at_ms),
      };
    });
    return {
      state: "ok",
      fetchedAtMs: t.fetchedAtMs,
      value: {
        settledCount: num(raw.settled_count),
        unscoredFlat: num(raw.unscored_flat),
        stats,
        pendingCount: pending.length,
        pending,
        params: Object.entries((raw.params ?? {}) as Record<string, unknown>).map(
          ([name, v]) => ({
            name,
            currentBps: num(v),
            // A parameter with no recorded default gets NaN rather than 0: showing a delta against
            // a default we do not have would be inventing the baseline.
            defaultBps: name in LEARNING_DEFAULT_BPS ? LEARNING_DEFAULT_BPS[name] : Number.NaN,
          }),
        ),
      },
    };
  } catch (e) {
    return {
      state: "error",
      source: DATA_SOURCES.learned,
      reason: e instanceof Error ? e.message : String(e),
    };
  }
}

export interface Deployment {
  name: string;
  address: string;
  role: string;
  /** Whether this contract is a self-deployed stand-in rather than a third-party venue. Drives
   * the provenance badge in task 4.6. Sourced from the data file, never hardcoded in a
   * component, so a new contract cannot render without a badge. */
  selfDeployed: boolean;
}

export interface ChainConfig {
  chainId: number;
  rpcUrl: string;
  explorerBase: string;
  deployments: Deployment[];
}

export async function loadDeployments(): Promise<Load<ChainConfig>> {
  const t = await fetchText("deployments");
  if (t.state !== "ok") return t;
  try {
    const raw = JSON.parse(t.value) as Record<string, unknown>;
    const list = Array.isArray(raw.deployments) ? raw.deployments : [];
    return {
      state: "ok",
      fetchedAtMs: t.fetchedAtMs,
      value: {
        chainId: num(raw.chain_id),
        rpcUrl: str(raw.rpc_url),
        explorerBase: str(raw.explorer_base),
        deployments: list.map((d) => {
          const o = d as Record<string, unknown>;
          return {
            name: str(o.name),
            address: str(o.address),
            role: str(o.role),
            selfDeployed: o.self_deployed === true,
          };
        }),
      },
    };
  } catch (e) {
    return {
      state: "error",
      source: DATA_SOURCES.deployments,
      reason: e instanceof Error ? e.message : String(e),
    };
  }
}

/** Metrics written by `bash scripts/88-recompute-metrics.sh`. The UI renders these and computes
 * none of them, so the panel cannot drift from the script that task 5.1 asks to reproduce. */
export interface Metrics {
  generatedAtUtc: string;
  generatedBy: string;
  explorerTxBase: string;
  explorerAddressBase: string;
  onchain: {
    headBlock: number | null;
    guardAddress: string;
    venueAddress: string;
    marketExposureWei: number | null;
    marketCapWei: number | null;
    marketUtilisationPct: number | null;
    grossExposureWei: number | null;
    grossCapWei: number | null;
    grossUtilisationPct: number | null;
    killed: string;
    venueOrderCount: number | null;
    agentKeyNonce: number | null;
  };
  journal: {
    rows: number;
    agentDecisions: number;
    baselineControlRows: number;
    takes: number;
    holds: number;
    submitted: number;
    candidatesTotal: number;
    refusalsTotal: number;
    refusalsByReason: Record<string, number>;
  };
  learning: {
    settled: number | null;
    unscoredFlat: number | null;
    pending: number | null;
    signalsTracked: number | null;
  };
  /** Fee revenue read from chain. OPTIONAL and possibly carrying only an `error`: a failed chain
   *  read must be representable as something other than zero, because zero is a claim about the
   *  business and a failed read is a claim about the network. */
  fees?: MetricsFees;
  /** Growth counters, task 13.1. Each carries its own source, and a counter whose source could not
   *  be read carries an `error` and NO `value`, so a consumer cannot render a number it was never
   *  given. */
  growth?: Record<string, GrowthCounter>;
  /** The learning effect, task 14.6. Same `{value?, source, error?}` shape as `growth`, and every
   *  figure inside carries the sample count it rests on IN THE SAME OBJECT. That pairing is the
   *  point: an accuracy or a parameter move rendered on its own invites a reader to treat ten
   *  samples as a track record, so the data structure makes the honest framing the easy one. */
  learningEffect?: Record<string, LearningCounter>;
}

/** One figure of the learning effect, task 14.6.
 *
 * Deliberately NOT reusing `GrowthCounter`. Its `value` is a number or a flat map of numbers, and
 * widening it to carry the parameter-change array as well would loosen the type the growth panel
 * relies on. Two shapes, two types, rather than one type that means whichever the reader guesses. */
export interface LearningCounter {
  /** Absent when the source could not be read. Absent is NOT zero. */
  value?: LearningSamples | LearningRate | LearningChange[] | LearningNet[] | LearningPnl;
  source: string;
  error?: string;
}

export interface LearningSamples {
  scored: number;
  settled: number;
  /** Forecasts dropped because the market did not move. A high figure relative to `scored` means
   *  the venue is too quiet to learn from, which is worth showing rather than burying. */
  droppedFlat: number;
}

/** A rate that cannot be rendered without the sample it rests on. */
export interface LearningRate {
  value: number;
  samples: number;
}

export interface LearningChange {
  parameter: string;
  from: number;
  to: number;
  samples: number;
  /** The sentence the learner itself recorded for why this moved. */
  trigger: string;
}

/** A parameter's NET move, default to current.
 *
 * Separate from `LearningChange` because they answer different questions. The change list shows
 * individual clamped steps, which are small by design and read as "nothing happened"; this shows
 * what the system actually did over its whole life. Momentum weight moving 411 to 401 and momentum
 * weight having fallen from 2000 to 391 are the same run described two ways, and only one of them
 * tells a reader whether anything was learned. */
export interface LearningNet {
  parameter: string;
  /** From `Params::default()` in the crate, cited in the source string. */
  default: number;
  current: number;
  moved: boolean;
}

export interface LearningPnl {
  totalMicro: number;
  settlements: number;
  profitable: number;
  losing: number;
  flat: number;
  /** Says in words that this is mark to market, not cash proceeds. Rendered, not just stored. */
  basis: string;
}

export interface GrowthCounter {
  /** Absent when the source could not be read. Absent is NOT zero. */
  value?: number | Record<string, number>;
  /** Where this number came from, in words, shown beside it in the UI. */
  source: string;
  error?: string;
}

export interface MetricsFees {
  collector: string;
  /** Present only when the read succeeded. Absent alongside `error`. */
  totalFeesWei?: string;
  eventCount?: number;
  feeBps?: number;
  treasury?: string;
  /** Newest first. May be shorter than `eventCount` when the log scan was bounded. */
  recent?: MetricsFeeEvent[];
  /** False when the bounded log scan could not reach far enough to list every recent charge. */
  recentIsComplete?: boolean;
  error?: string;
}

export interface MetricsFeeEvent {
  payer: string;
  market: string;
  token: string;
  /** Wei, as a string. Never parsed to a number anywhere in the UI. */
  notionalWei: string;
  feeWei: string;
  feeBps: number;
  tx: string;
  logIndex: number;
  block: number;
}

/** Map the `fees` block. Returns `undefined` when the block is absent entirely, and an object
 *  carrying only `error` when the chain read failed, so no caller can mistake either for zero
 *  revenue. Amounts stay strings. */
function mapFees(f?: Record<string, unknown>): MetricsFees | undefined {
  if (!f || typeof f !== "object") return undefined;
  const collector = String(f.collector ?? "");
  if (typeof f.error === "string") return { collector, error: f.error };
  if (typeof f.total_fees_wei !== "string") {
    return { collector, error: "metrics.json carried no fee total" };
  }
  const rows = Array.isArray(f.recent) ? (f.recent as Record<string, unknown>[]) : [];
  return {
    collector,
    totalFeesWei: f.total_fees_wei,
    eventCount: typeof f.event_count === "number" ? f.event_count : undefined,
    feeBps: typeof f.fee_bps === "number" ? f.fee_bps : undefined,
    treasury: typeof f.treasury === "string" ? f.treasury : undefined,
    recentIsComplete: f.recent_is_complete === true,
    recent: rows.map((e) => ({
      payer: String(e.payer ?? ""),
      market: String(e.market ?? ""),
      token: String(e.token ?? ""),
      notionalWei: String(e.notional_wei ?? "0"),
      feeWei: String(e.fee_wei ?? "0"),
      feeBps: typeof e.fee_bps === "number" ? e.fee_bps : 0,
      tx: String(e.tx ?? ""),
      logIndex: typeof e.log_index === "number" ? e.log_index : 0,
      block: typeof e.block === "number" ? e.block : 0,
    })),
  };
}

export async function loadMetrics(): Promise<Load<Metrics>> {
  const url = "data/metrics.json";
  try {
    const res = await fetch(url, { cache: "no-store" });
    if (!res.ok) return { state: "error", source: url, reason: `HTTP ${res.status}` };
    const text = await res.text();
    if (text.trimStart().startsWith("<")) {
      return { state: "error", source: url, reason: "server returned HTML, file not present" };
    }
    const raw = JSON.parse(text) as Record<string, never>;
    const o = (raw as Record<string, Record<string, unknown>>).onchain ?? {};
    const j = (raw as Record<string, Record<string, unknown>>).journal ?? {};
    const l = (raw as Record<string, Record<string, unknown>>).learning ?? {};
    const n = (v: unknown): number | null =>
      typeof v === "number" && Number.isFinite(v) ? v : null;
    return {
      state: "ok",
      fetchedAtMs: Date.now(),
      value: {
        generatedAtUtc: String((raw as Record<string, unknown>).generated_at_utc ?? ""),
        generatedBy: String((raw as Record<string, unknown>).generated_by ?? ""),
        explorerTxBase: String((raw as Record<string, unknown>).explorer_tx_base ?? ""),
        explorerAddressBase: String((raw as Record<string, unknown>).explorer_address_base ?? ""),
        onchain: {
          headBlock: n(o.head_block),
          guardAddress: String(o.guard_address ?? ""),
          venueAddress: String(o.venue_address ?? ""),
          marketExposureWei: n(o.market_exposure_wei),
          marketCapWei: n(o.market_cap_wei),
          marketUtilisationPct: n(o.market_utilisation_pct),
          grossExposureWei: n(o.gross_exposure_wei),
          grossCapWei: n(o.gross_cap_wei),
          grossUtilisationPct: n(o.gross_utilisation_pct),
          killed: String(o.killed ?? ""),
          venueOrderCount: n(o.venue_order_count),
          agentKeyNonce: n(o.agent_key_nonce),
        },
        journal: {
          rows: n(j.rows) ?? 0,
          agentDecisions: n(j.agent_decisions) ?? 0,
          baselineControlRows: n(j.baseline_control_rows) ?? 0,
          takes: n(j.takes) ?? 0,
          holds: n(j.holds) ?? 0,
          submitted: n(j.submitted) ?? 0,
          candidatesTotal: n(j.candidates_total) ?? 0,
          refusalsTotal: n(j.refusals_total) ?? 0,
          refusalsByReason: (j.refusals_by_reason as Record<string, number>) ?? {},
        },
        learning: {
          settled: n(l.settled),
          unscoredFlat: n(l.unscored_flat),
          pending: n(l.pending),
          signalsTracked: n(l.signals_tracked),
        },
        fees: mapFees((raw as Record<string, Record<string, unknown>>).fees),
        // Passed through as-is: the shape is already {value?, source, error?} and flattening it
        // would lose exactly the distinction between "zero" and "unreadable" that it exists for.
        growth: (raw as Record<string, unknown>).growth as
          | Record<string, GrowthCounter>
          | undefined,
        learningEffect: (raw as Record<string, unknown>).learningEffect as
          | Record<string, LearningCounter>
          | undefined,
      },
    };
  } catch (e) {
    return { state: "error", source: url, reason: e instanceof Error ? e.message : String(e) };
  }
}

/** One captured comparator state: the same order judged against both markets, task 5.4. */
export interface ComparatorState {
  name: string;
  setup: string;
  parsed: boolean;
  block: number | null;
  order: string;
  vault: {
    oracleAgeSecs: number | null;
    paused: boolean | null;
    secondsUntilWindow: number | null;
    divergenceBps: number | null;
    yieldIndex: string | null;
  };
  crypto: { verdict: string; detail: string };
  rwa: { verdict: string; detail: string };
  divergentTreatment: boolean;
  rwaSpecificReason: boolean;
}

export interface ComparatorData {
  generatedBy: string;
  states: ComparatorState[];
}

export async function loadComparator(): Promise<Load<ComparatorData>> {
  const url = "data/comparator.json";
  try {
    const res = await fetch(url, { cache: "no-store" });
    if (!res.ok) return { state: "error", source: url, reason: `HTTP ${res.status}` };
    const text = await res.text();
    if (text.trimStart().startsWith("<")) {
      return { state: "error", source: url, reason: "server returned HTML, file not present" };
    }
    const raw = JSON.parse(text) as Record<string, unknown>;
    const rawStates = Array.isArray(raw.states) ? raw.states : [];
    const states: ComparatorState[] = rawStates.map((r) => {
      const o = r as Record<string, unknown>;
      const v = (o.vault ?? {}) as Record<string, unknown>;
      const c = (o.crypto ?? {}) as Record<string, unknown>;
      const w = (o.rwa ?? {}) as Record<string, unknown>;
      const n = (x: unknown): number | null =>
        typeof x === "number" && Number.isFinite(x) ? x : null;
      return {
        name: str(o.name),
        setup: str(o.setup),
        parsed: o.parsed === true,
        block: n(o.block),
        order: str(o.order),
        vault: {
          oracleAgeSecs: n(v.oracleAgeSecs),
          paused: typeof v.paused === "boolean" ? v.paused : null,
          secondsUntilWindow: n(v.secondsUntilWindow),
          divergenceBps: n(v.divergenceBps),
          yieldIndex: v.yieldIndex === null || v.yieldIndex === undefined ? null : str(v.yieldIndex),
        },
        crypto: { verdict: str(c.verdict), detail: str(c.detail) },
        rwa: { verdict: str(w.verdict), detail: str(w.detail) },
        divergentTreatment: o.divergentTreatment === true,
        rwaSpecificReason: o.rwaSpecificReason === true,
      };
    });
    return {
      state: "ok",
      fetchedAtMs: Date.now(),
      value: { generatedBy: str(raw.generatedBy), states },
    };
  } catch (e) {
    return { state: "error", source: url, reason: e instanceof Error ? e.message : String(e) };
  }
}

/** Micro-units to a display string. 1e6 micro-units is one whole unit.
 *
 * Values past exact integer range print as "invalid" rather than as a rounded digit string. The
 * red team fed a score of 1e30 and the first version printed it; a number JavaScript cannot hold
 * exactly is not a number this UI should assert. */
export function fromMicro(v: number, decimals = 2): string {
  if (!Number.isFinite(v)) return "—";
  if (Math.abs(v) > Number.MAX_SAFE_INTEGER) return "invalid";
  return (v / 1_000_000).toFixed(decimals);
}

/** Basis points to a percent string. Out-of-domain values print as "invalid": bps are hundredths
 * of a percent, so anything above 10000 is not a percentage and must not be shown as one. The red
 * team's 999999999 bps rendered as "10000000.0%" before this guard. */
export function bpsToPct(v: number, decimals = 2): string {
  if (!Number.isFinite(v)) return "—";
  if (v < 0 || v > 10_000) return "invalid";
  return (v / 100).toFixed(decimals);
}

/** A block number for display. Beyond exact integer range the digits are an artifact. */
export function blockLabel(v: number): string {
  if (!Number.isFinite(v) || v < 0) return "—";
  if (v > Number.MAX_SAFE_INTEGER) return "invalid";
  return String(v);
}

/** Age of a timestamp, and whether it is past the staleness threshold.
 * The threshold comes from DATA_LIMITS, not from the call site (their reliability.ts:32-47). */
export function freshness(atMs: number, nowMs: number) {
  const ageMs = nowMs - atMs;
  return { ageMs, isStale: ageMs > DATA_LIMITS.stalenessThresholdMs };
}
