/**
 * ONE poll of the user's vault position, shared by every component that needs it.
 *
 * WHY THIS EXISTS, measured rather than anticipated. `Activate` and `ExitBar` each read the position
 * independently: seven `eth_call`s apiece, every five seconds, against a public RPC. Fourteen calls
 * per five seconds from one page was enough for X Layer's endpoint to start refusing, and the
 * browser console filled with ERR_CONNECTION_REFUSED and ERR_EMPTY_RESPONSE. Both components swallow
 * read failures by design, so nothing showed an error: the exit bar simply never appeared, which is
 * the worst possible way for this particular bug to present, because the control a user needs in a
 * panic was missing and the page looked healthy.
 *
 * The fix is architectural rather than a longer interval. There is now ONE poll, one set of
 * subscribers, and one in-flight guard so a slow response cannot overlap the next tick. Adding a
 * third consumer costs nothing.
 *
 * A module-level store rather than React context: the poll must survive components mounting and
 * unmounting as routes change, and a context provider high enough to do that would have to live
 * above the router anyway. This is smaller and has no provider to forget.
 */

import { type VaultAddresses, type VaultPosition, readPosition } from "./vault";

type Listener = (s: PositionState) => void;

export interface PositionState {
  /** `null` means NOT YET READ. Distinct from a real zero balance, which is a VaultPosition. */
  position: VaultPosition | null;
  /** The last read error, kept so a consumer can show it rather than rendering a silent blank. */
  error: string | null;
  /** True once a read has completed, successfully or not. Lets a UI say "unknown" honestly. */
  loaded: boolean;
}

const POLL_MS = 8000;

let state: PositionState = { position: null, error: null, loaded: false };
let listeners: Listener[] = [];
let timer: ReturnType<typeof setInterval> | null = null;
let inFlight = false;

let who: string | null = null;
let addresses: VaultAddresses | null = null;
let rpcUrl: string | null = null;

function emit() {
  for (const l of listeners) l(state);
}

async function poll(): Promise<void> {
  if (!who || !addresses || !rpcUrl) return;
  // A slow response must not overlap the next tick, or a stalled RPC turns one poll into a queue.
  if (inFlight) return;
  inFlight = true;
  try {
    const position = await readPosition(who, addresses, rpcUrl);
    state = { position, error: null, loaded: true };
  } catch (e) {
    // The PREVIOUS position is kept. Clearing it would hide the exit controls the moment the network
    // hiccups, which is exactly when a user is most likely to want them.
    state = {
      position: state.position,
      error: e instanceof Error ? e.message : String(e),
      loaded: true,
    };
  } finally {
    inFlight = false;
    emit();
  }
}

/** Point the store at a user and a deployment. Restarts the poll when either changes. */
export function configurePosition(
  who_: string | null,
  addresses_: VaultAddresses | null,
  rpcUrl_: string | null,
): void {
  const changed = who_ !== who || addresses_ !== addresses || rpcUrl_ !== rpcUrl;
  who = who_;
  addresses = addresses_;
  rpcUrl = rpcUrl_;

  if (!who || !addresses || !rpcUrl) {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
    state = { position: null, error: null, loaded: false };
    emit();
    return;
  }

  if (changed) {
    state = { position: null, error: null, loaded: false };
    emit();
    void poll();
  }
  if (!timer) timer = setInterval(() => void poll(), POLL_MS);
}

export function subscribePosition(l: Listener): () => void {
  listeners.push(l);
  l(state);
  return () => {
    listeners = listeners.filter((x) => x !== l);
  };
}

/** Force an immediate re-read, used after a transaction lands. */
export function refreshPosition(): Promise<void> {
  return poll();
}

export function getPosition(): PositionState {
  return state;
}
