/**
 * Flow instrumentation, task 10.1.
 *
 * Five marks: first paint, connect, defaults accepted, deposit confirmed, activated. Task 10.2 then
 * uses them to answer "how long does a cold user take", and task 10.3 publishes the number.
 *
 * THINKING: #50 empirical, #60 map-territory (a claim nobody timed is a slogan), #49 skeptical.
 *
 * WRITTEN TO A FILE, NOT A CONSOLE, which the task states explicitly. A console log vanishes when the
 * tab closes and cannot be diffed, cited or reproduced. These marks are POSTed to the coordination
 * API, which appends them to evidence/phase10/flow-marks.jsonl, so a timing claim has an artifact
 * behind it like every other claim in this project.
 *
 * PERFORMANCE.NOW, NOT DATE.NOW, for the deltas. `Date.now` is wall-clock and can step backwards
 * when the system clock syncs mid-run, which would produce a negative duration in the middle of a
 * measurement and be quietly averaged into a headline number. `performance.now` is monotonic. The
 * wall-clock time is recorded too, once, so a run can be located in the journal afterwards.
 *
 * A FAILED POST NEVER BLOCKS THE USER. Instrumentation that can break the flow it measures is worse
 * than no instrumentation: the measurement would then be of a product nobody ships.
 */

export type FlowMark =
  | "first_paint"
  | "connected"
  | "defaults_seen"
  | "deposit_submitted"
  | "activated";

interface Mark {
  mark: FlowMark;
  /** Milliseconds since first paint. Monotonic. */
  sinceFirstPaintMs: number;
  /** Wall clock, for locating the run in the journal. */
  at: string;
}

const API_PORT = 8737;
const DEMO_KEY = "demo-agent-key-1";

/** A run id so concurrent tabs cannot interleave into one nonsense timeline. */
const runId = `run-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

let origin: number | null = null;
const seen = new Set<FlowMark>();
const marks: Mark[] = [];

/**
 * Record a mark. Idempotent per mark: the first occurrence wins.
 *
 * Idempotence matters because these fire from React effects, which run twice in StrictMode and again
 * on any remount. Without it, "connected" would be re-stamped every time the user changed tabs and
 * the elapsed time would collapse toward zero, which is the direction that flatters the number.
 */
export function mark(name: FlowMark): void {
  if (seen.has(name)) return;
  seen.add(name);

  if (origin === null) origin = performance.now();
  const entry: Mark = {
    mark: name,
    sinceFirstPaintMs: Math.round(performance.now() - origin),
    at: new Date().toISOString(),
  };
  marks.push(entry);

  void fetch(`http://${window.location.hostname}:${API_PORT}/flow-mark`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": DEMO_KEY },
    body: JSON.stringify({ runId, ...entry }),
    keepalive: true, // survives a navigation, which "activated" often triggers
  }).catch(() => {
    // Deliberately swallowed. Instrumentation must never break the flow it measures.
  });
}

/** The marks so far, for the in-page audit to read without waiting on the server. */
export function flowMarks(): { runId: string; marks: Mark[] } {
  return { runId, marks: [...marks] };
}

/** Exposed so task 10.2's cold-run harness can read the timeline it just produced. */
if (typeof window !== "undefined") {
  (window as unknown as { __asmlFlowMarks?: typeof flowMarks }).__asmlFlowMarks = flowMarks;
}
