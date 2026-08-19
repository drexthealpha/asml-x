/**
 * OKX request signing, server-side only. Shared by every function in this directory.
 *
 * WHY THIS EXISTS. Locally the feeds are signed by `scripts/feed_server.py`, which reads
 * credentials from `~/.asml-keys/okx.env`. That file does not exist on Vercel and must not: a
 * secret shipped to a browser is a published secret, and a secret committed to a repo is worse.
 *
 * On Vercel the same signing happens inside a serverless function, where `process.env` holds the
 * credentials and the browser only ever sees results. The signature scheme is identical, so the
 * hosted deployment and the local one are reading the same API in the same way, and a difference
 * between them is a bug rather than a configuration.
 *
 * REQUIRED ENVIRONMENT, set in the Vercel project:
 *   OKX_API_KEY  OKX_SECRET  OKX_PASSPHRASE   (OKX_PROJECT optional)
 *
 * WITHOUT THEM the functions return 503 and say so. They do NOT fall back to unsigned requests:
 * an unauthenticated call returns thin data that looks like a quiet market rather than a missing
 * key, which is the failure this project keeps having to dig out.
 */

import crypto from "node:crypto";

const HOST = "https://web3.okx.com";

export function creds() {
  const key = process.env.OKX_API_KEY;
  const secret = process.env.OKX_SECRET || process.env.OKX_SECRET_KEY;
  const passphrase = process.env.OKX_PASSPHRASE;
  if (!key || !secret || !passphrase) return null;
  return { key, secret, passphrase, project: process.env.OKX_PROJECT || "" };
}

function headers(c, method, path, body = "") {
  // OKX wants milliseconds with exactly three decimal places.
  const ts = new Date().toISOString().replace(/(\.\d{3})\d*Z$/, "$1Z");
  const sign = crypto
    .createHmac("sha256", c.secret)
    .update(ts + method + path + body)
    .digest("base64");

  const h = {
    "OK-ACCESS-KEY": c.key,
    "OK-ACCESS-SIGN": sign,
    "OK-ACCESS-TIMESTAMP": ts,
    "OK-ACCESS-PASSPHRASE": c.passphrase,
    "Content-Type": "application/json",
  };
  if (c.project) h["OK-ACCESS-PROJECT"] = c.project;
  return h;
}

/** Signed GET. Returns the parsed body, or null. */
export async function get(path, c) {
  const r = await fetch(HOST + path, { headers: headers(c, "GET", path) });
  if (!r.ok) return null;
  const d = await r.json();
  return d.code === "0" ? d.data : null;
}

/** Signed POST. The body is serialised ONCE and the same string is signed and sent. */
export async function post(path, payload, c) {
  const body = JSON.stringify(payload);
  const r = await fetch(HOST + path, {
    method: "POST",
    headers: headers(c, "POST", path, body),
    body,
  });
  if (!r.ok) return null;
  const d = await r.json();
  return d.code === "0" ? d.data : null;
}

/** The standard response shape: JSON, never cached, CORS-open for read-only market data. */
export function send(res, status, payload) {
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Cache-Control", "no-store, max-age=0");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.status(status).send(JSON.stringify(payload));
}

/** Guard every handler: no credentials means a loud 503, never a quiet empty result. */
export function requireCreds(res) {
  const c = creds();
  if (!c) {
    send(res, 503, {
      error: "OKX credentials are not configured on this deployment",
      fix: "Set OKX_API_KEY, OKX_SECRET and OKX_PASSPHRASE in the Vercel project settings",
    });
    return null;
  }
  return c;
}

export const CHAIN = "196";
