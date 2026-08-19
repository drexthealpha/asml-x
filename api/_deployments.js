/**
 * The deployment manifest, loaded at run time rather than through a JSON import assertion.
 *
 * WHY NOT `import x from "./x.json" with { type: "json" }`. Import attributes need a recent Node
 * and are still flagged in some runtimes; a function that fails to load returns an opaque 500 with
 * nothing in it that says why. Reading the file is boring and works everywhere.
 *
 * The manifest is written by the deploy scripts from the deployment that actually happened, so the
 * addresses here are never typed by hand.
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";

let cached = null;

export function deployments() {
  if (cached) return cached;
  // Vercel runs functions from the project root, so the public directory is a sibling of api/.
  const candidates = [
    join(process.cwd(), "public", "data", "deployments.json"),
    join(process.cwd(), "ui-v2", "public", "data", "deployments.json"),
    join(process.cwd(), "dist", "data", "deployments.json"),
  ];
  for (const p of candidates) {
    try {
      cached = JSON.parse(readFileSync(p, "utf8"));
      return cached;
    } catch {
      // Try the next candidate. An exhausted list is reported by the caller, not swallowed.
    }
  }
  return null;
}

/** One contract address by name, or null. Never a placeholder. */
export function address(name) {
  const d = deployments();
  return d?.deployments?.find((x) => x.name === name)?.address ?? null;
}
