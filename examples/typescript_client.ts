/**
 * Minimal ASML-X coordination client. No dependencies, runs on Node 18+ or Bun.
 *
 * Run the API first:
 *     ./target/release/asml-coord
 *
 * Then:
 *     node --experimental-strip-types examples/typescript_client.ts
 *     # or: bun examples/typescript_client.ts
 *
 * Same shape as examples/python_client.py, deliberately: an agent in another process reads the
 * brain's view, sizes its own order, requests a quote through the SAME risk gate an internal
 * decision passes, and accepts it. Settlement is done by the brain runtime, which owns the keystore.
 */

/**
 * The only two things this example needs from the host, declared inline so it compiles with nothing
 * installed. Depending on `@types/node` to read two environment variables would make a 60 line
 * example require a package install before it can be type-checked.
 */
declare const process: {
  env: Record<string, string | undefined>;
  exit(code: number): void;
};

const BASE = process.env.ASML_API ?? "http://127.0.0.1:8737";
const KEY = process.env.ASML_API_KEY ?? "demo-agent-key-1";

async function call(
  method: string,
  path: string,
  body?: unknown,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      "x-api-key": KEY,
      ...(body === undefined ? {} : { "content-type": "application/json" }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  // A refusal is an ANSWER: every non-2xx carries a JSON body explaining itself. Throwing on
  // !res.ok would discard the reason, which is the most useful part of the response.
  const text = await res.text();
  return { status: res.status, json: text ? JSON.parse(text) : {} };
}

async function main(): Promise<number> {
  const thesis = await call("GET", "/thesis");
  console.log(`[${thesis.status}] thesis: ${String(thesis.json.thesis ?? "").slice(0, 100)}`);
  console.log(`       block ${thesis.json.block}, snapshot age ${thesis.json.snapshot_age_ms} ms`);

  const cap = await call("GET", "/capacity");
  const permitted = Number(cap.json.max_permitted_size_micro ?? "0");
  console.log(
    `[${cap.status}] capacity: ${permitted} micro permitted, exposure ${cap.json.current_exposure_micro}`,
  );
  if (cap.json.first_refusal_beyond) {
    console.log(`       refuses beyond that with: ${cap.json.first_refusal_beyond}`);
  }

  // Size it yourself. Asking for exactly what you were offered is not a decision.
  const size = Math.max(Math.floor(permitted / 4), 500_000);
  let side = "buy";

  let quote = await call("POST", "/quote", { size_micro: String(size), side });
  if (quote.status !== 200) {
    console.log(`[${quote.status}] quote refused: ${quote.json.refusal ?? quote.json.error}`);
    side = "sell";
    quote = await call("POST", "/quote", { size_micro: String(size), side });
    if (quote.status !== 200) {
      console.log(`[${quote.status}] refused on both sides: ${quote.json.refusal ?? quote.json.error}`);
      return 1;
    }
  }

  console.log(
    `[${quote.status}] quote ${quote.json.quote_id}: ${side} ${quote.json.size_micro} at ${quote.json.price_micro}`,
  );
  console.log(`       valid for ${quote.json.ttl_ms} ms, priced at block ${quote.json.block}`);

  const accepted = await call("POST", "/accept", { quote_id: quote.json.quote_id });
  console.log(
    `[${accepted.status}] accepted: ${accepted.json.accepted}, handoff written: ${accepted.json.handoff_written}`,
  );
  console.log(`       ${accepted.json.note ?? ""}`);
  return accepted.status === 200 ? 0 : 1;
}

main().then((code) => process.exit(code));
