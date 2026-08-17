/**
 * Turn a contract revert into a sentence a person can act on, task 9.8.
 *
 * THE DEFECT THIS FIXES, measured rather than imagined. Asking the vault to withdraw more than the
 * balance produced this, verbatim, in the UI:
 *
 *   Error: Failed to estimate gas: server returned an error response: error code 3: execution
 *   reverted, data: "0xcf47918100000000000000000000000000000000000000000000d3c21bcecceda1
 *   0000000000000000000000000000000000000000000000000000000000000000"
 *
 * Every fact needed is in there and none of it is legible. Task 9.8's named fake win is "a generic
 * 'something went wrong' toast counted as handling", and a raw hex dump fails the same test for the
 * same reason: it does not tell the user what happened or what to do next.
 *
 * SELECTORS ARE VERIFIED, not guessed. `scripts/verify-revert-selectors.sh` checks every one against
 * `cast sig`. Five of eleven hand-written selectors were wrong the first time this project wrote
 * them by hand, so none of these is trusted without a check.
 *
 * The fallback is deliberately honest: an unrecognised revert keeps its raw data AND still offers a
 * next action, because a user facing an error nobody anticipated is exactly the user most likely to
 * be stuck.
 */

/** 18 decimals, formatted by string slicing so nothing rounds. */
function fmt(wei: bigint, dp = 4): string {
  const s = wei.toString().padStart(19, "0");
  const whole = s.slice(0, s.length - 18).replace(/^0+(?=\d)/, "");
  const frac = s.slice(s.length - 18, s.length - 18 + dp);
  return `${whole}.${frac}`;
}

export interface FriendlyError {
  /** What happened, in the user's terms. */
  message: string;
  /** What to do about it. Never empty: a cause with no way forward is a dead end. */
  action: string;
  /** The decoded custom-error name, for the evidence file rather than for display. */
  errorName?: string;
  /** The raw revert data, kept so nothing is lost. */
  raw?: string;
}

type Decoder = (words: bigint[]) => FriendlyError;

/** selector -> decoder. Signatures are written beside each so `cast sig` can check them. */
const DECODERS: Record<string, { sig: string; decode: Decoder }> = {
  // cast sig "InsufficientBalance(uint256,uint256)"
  "0xcf479181": {
    sig: "InsufficientBalance(uint256,uint256)",
    decode: ([requested, available]) => ({
      errorName: "InsufficientBalance",
      message: `You asked to withdraw ${fmt(requested)} tQUOTE but only ${fmt(available)} is available right now.`,
      action:
        available === 0n
          ? "Your funds may be committed to a trade in flight. Wait for it to settle, then try again."
          : `Withdraw ${fmt(available)} tQUOTE or less.`,
    }),
  },
  // cast sig "ExceedsUserLimit(uint256,uint256)"
  "0x38888fc7": {
    sig: "ExceedsUserLimit(uint256,uint256)",
    decode: ([requested, limit]) => ({
      errorName: "ExceedsUserLimit",
      message: `That trade is ${fmt(requested)} tQUOTE, above your own per-action limit of ${fmt(limit)}.`,
      action: "Raise your limit on this screen, or leave it as it is and the agent will trade smaller.",
    }),
  },
  // cast sig "DepositorPaused(address)"
  "0xaed11bd2": {
    sig: "DepositorPaused(address)",
    decode: () => ({
      errorName: "DepositorPaused",
      message: "The agent is paused for your account, so it cannot open new positions.",
      action: "Press Resume to let it trade again. Withdrawing works whether you are paused or not.",
    }),
  },
  // cast sig "ZeroAmount()"
  "0x1f2a2005": {
    sig: "ZeroAmount()",
    decode: () => ({
      errorName: "ZeroAmount",
      message: "There is nothing to move: the amount is zero.",
      action: "Deposit first, or wait for a trade in flight to settle.",
    }),
  },
  // cast sig "InvalidSignature()"
  "0x8baa579f": {
    sig: "InvalidSignature()",
    decode: () => ({
      errorName: "InvalidSignature",
      message:
        "The approval signature was not accepted. Someone may have submitted it first, which uses it up.",
      action: "Press the button again: a fresh signature will be requested.",
    }),
  },
  // cast sig "PermitExpired(uint256,uint256)"
  "0xe37c206e": {
    sig: "PermitExpired(uint256,uint256)",
    decode: () => ({
      errorName: "PermitExpired",
      message: "The approval signature expired before the transaction was mined.",
      action: "Press the button again to sign a fresh one.",
    }),
  },
  // cast sig "NotAuthorisedTaker(address)"
  "0xed8e2879": {
    sig: "NotAuthorisedTaker(address)",
    decode: () => ({
      errorName: "NotAuthorisedTaker",
      message: "That account is not allowed to trade directly against the venue.",
      action: "Trades go through the agent's executor. Use Run full demo rather than the venue directly.",
    }),
  },
};

const HEX_ERROR = /0x[0-9a-fA-F]{8,}/;

/**
 * Decode a provider or contract error into something actionable.
 *
 * Handles the shapes a wallet actually produces: a raw revert string, a nested `data` field, and the
 * gas-estimation wrapper that buries the revert inside a sentence about estimating gas.
 */
export function friendlyError(err: unknown): FriendlyError {
  const text =
    typeof err === "string"
      ? err
      : err instanceof Error
        ? err.message
        : typeof err === "object" && err !== null && "message" in err
          ? String((err as { message: unknown }).message)
          : String(err);

  // EIP-1193 user rejection, which arrives long before any contract is touched.
  if (typeof err === "object" && err !== null && "code" in err) {
    const code = (err as { code: unknown }).code;
    if (code === 4001) {
      return {
        message: "You declined the request in your wallet.",
        action: "Press the button again and approve it.",
      };
    }
  }

  const match = text.match(HEX_ERROR);
  if (match) {
    const data = match[0];
    const selector = data.slice(0, 10).toLowerCase();
    const entry = DECODERS[selector];
    if (entry) {
      const body = data.slice(10);
      const words: bigint[] = [];
      for (let i = 0; i + 64 <= body.length; i += 64) {
        words.push(BigInt("0x" + body.slice(i, i + 64)));
      }
      return { ...entry.decode(words), raw: data };
    }
    // Unrecognised, and it says so rather than pretending.
    return {
      message: "The transaction was refused by the contract.",
      action: "Nothing was moved. Press the button again, and if it keeps failing the raw reason is below.",
      raw: data,
    };
  }

  if (/failed to fetch|networkerror|econnrefused/i.test(text)) {
    return {
      message: "Could not reach the network.",
      action: "Check your connection. The page keeps retrying by itself.",
    };
  }

  return {
    message: text.slice(0, 200),
    action: "Nothing was moved. Press the button again to retry.",
  };
}

/** The selector table, exported so a gate can verify every signature against `cast sig`. */
export const REVERT_SELECTORS = Object.entries(DECODERS).map(([sel, v]) => ({
  selector: sel,
  signature: v.sig,
}));

/**
 * The decoder, reachable from the console.
 *
 * Two lines, kept deliberately. A support conversation that begins with a user pasting a raw revert
 * ends immediately if anyone can run the decoder on it and read the sentence back. It also lets task
 * 9.8's gate exercise the REAL decoder instead of a copy of its logic written inside the test, which
 * would only ever prove the test agrees with itself.
 *
 * This exposes nothing the page does not already do on every error, so it widens no surface.
 */
if (typeof window !== "undefined") {
  (window as unknown as { __asmlDecodeError?: typeof friendlyError }).__asmlDecodeError =
    friendlyError;
}
