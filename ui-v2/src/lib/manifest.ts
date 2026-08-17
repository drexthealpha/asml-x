/**
 * The deployment manifest and the shipped limits, fetched ONCE per page load.
 *
 * WHY. Both `PersonalView` and `ExitBar` fetched `data/deployments.json` on mount, and `Activate`
 * fetched `data/limits.json` on mount. Switching routes unmounts and remounts them, so every visit
 * to the personal view refetched both files before it could render anything. Measured with the task
 * 9.7 audit: the exit bar had data at 120ms (it reads the shared position store, which was already
 * warm) while the balance, limits and fee panels were still absent at 620ms and only appeared at
 * 1627ms.
 *
 * Nothing in either file changes during a page load. They are build artifacts written by the deploy
 * script and by `cargo test`. Refetching them on every route change is work that can only produce
 * the answer it already has.
 *
 * A module-level promise rather than React state: the cache must outlive any component, since the
 * whole point is that remounting must not restart the fetch. Concurrent callers share the same
 * in-flight promise, so two components mounting together make one request rather than two.
 */

export interface Manifest {
  rpc_url?: string;
  deployments?: { name: string; address: string }[];
}

export interface LimitRow {
  key: string;
  label: string;
  micro?: number;
  count?: number;
  protects: string;
}

export interface LimitsDoc {
  source: string;
  microPerUnit: number;
  limits: LimitRow[];
}

let manifestPromise: Promise<Manifest> | null = null;
let limitsPromise: Promise<LimitsDoc> | null = null;

async function fetchJson<T>(url: string): Promise<T> {
  const res = await fetch(url, { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return (await res.json()) as T;
}

export function loadManifest(): Promise<Manifest> {
  // A REJECTED promise is not cached: a failed load must be retryable, or one network hiccup during
  // startup would leave the page permanently unable to find its own contracts.
  if (!manifestPromise) {
    manifestPromise = fetchJson<Manifest>("data/deployments.json").catch((e) => {
      manifestPromise = null;
      throw e;
    });
  }
  return manifestPromise;
}

export function loadLimits(): Promise<LimitsDoc> {
  if (!limitsPromise) {
    limitsPromise = fetchJson<LimitsDoc>("data/limits.json").catch((e) => {
      limitsPromise = null;
      throw e;
    });
  }
  return limitsPromise;
}

/**
 * Name-based lookup, never positional.
 *
 * A positional parse of this manifest once sent every setup transaction to the wrong contract,
 * because the row order changed between deployments.
 */
export function pickAddress(m: Manifest, name: string): string | null {
  return m.deployments?.find((d) => d.name === name)?.address ?? null;
}
