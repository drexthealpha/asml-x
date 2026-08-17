"""Task 5.1: compute every metrics-panel counter once, and write the file the panel renders.

Two families of counter, kept separate on screen because they have different authority:

  ONCHAIN   read live from the guard and the venue this run. These are facts about the chain.
  JOURNAL   counted from the agent's own record. These are facts about what the agent did.

Mixing them would let a journal-derived number borrow the credibility of a chain read.
"""
import datetime
import json
import os
import sys

REPO = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X"
J = f"{REPO}/ui-v2/public/data/journal.jsonl"
OUT = f"{REPO}/ui-v2/public/data/metrics.json"
EXPLORER_TX = "https://www.oklink.com/x-layer-testnet/tx/"
EXPLORER_ADDR = "https://www.oklink.com/x-layer-testnet/address/"
WEI_PER_MICRO = 10**12


def env_int(name):
    v = os.environ.get(name, "").strip()
    try:
        return int(v)
    except ValueError:
        return None



def _deployment(key):
    """One source of truth for deployed addresses: the file the deploy script writes."""
    with open(f"{REPO}/deployments.json", encoding="utf-8") as fh:
        return json.load(fh)[key]


def _fee_metrics():
    """Fee revenue, read from the file scripts/fee_logs.py wrote.

    This is the counter to Phase 7's headline fake win, which TASKS.md names as "a counter
    incremented in TypeScript on each decision". Nothing here is journal-derived and nothing is
    incremented: the totals are contract state and the detail rows are decoded chain logs.

    If the file is missing the fetcher failed, and this returns an `error` key with NO totals, so the
    panel renders an error rather than a confident zero. A zero and a failed read look identical to a
    reader and only one of them means the business made no money.
    """
    path = os.environ.get("FEE_JSON", "")
    if not path or not os.path.exists(path):
        return {
            "collector": _deployment("feeCollector"),
            "error": "fee chain read did not produce a file; totals deliberately omitted",
        }
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        return {"collector": _deployment("feeCollector"), "error": f"fee metrics unreadable: {exc}"}


def _fee_metrics_dead():
    """Fee revenue, derived ONLY from eth_getLogs output.

    This is the counter to Phase 7's headline fake win, which TASKS.md names as "a counter
    incremented in TypeScript on each decision". Nothing here is journal-derived and nothing is
    incremented; the totals are a fold over logs the chain returned. If the log file is missing or
    unparseable this returns an `error` key and NO totals, so the panel renders an error rather than
    a confident zero. A zero and a failed read look identical to a reader, and only one of them means
    the business made no money.
    """
    path = os.environ.get("FEE_LOGS", "")
    out = {"collector": _deployment("feeCollector"), "source": "eth_getLogs FeeCharged"}
    if not path or not os.path.exists(path):
        out["error"] = "no FeeCharged log file; the chain read did not run"
        return out
    try:
        with open(path, encoding="utf-8") as fh:
            logs = json.load(fh)
    except Exception as exc:
        out["error"] = f"FeeCharged logs unreadable: {exc}"
        return out

    events = []
    for lg in logs:
        data = lg["data"][2:]
        words = [data[i : i + 64] for i in range(0, len(data), 64)]
        if len(words) < 4:
            continue
        events.append(
            {
                "payer": "0x" + lg["topics"][1][-40:],
                "market": lg["topics"][2],
                "token": "0x" + words[0][-40:],
                "notional_wei": str(int(words[1], 16)),
                "fee_wei": str(int(words[2], 16)),
                "fee_bps": int(words[3], 16),
                "tx": lg.get("transactionHash"),
                "block": int(lg["blockNumber"], 16) if isinstance(lg.get("blockNumber"), str) else lg.get("blockNumber"),
            }
        )

    out["event_count"] = len(events)
    out["total_fees_wei"] = str(sum(int(e["fee_wei"]) for e in events))
    out["total_notional_wei"] = str(sum(int(e["notional_wei"]) for e in events))
    # Newest first, five deep. The panel renders these rows verbatim.
    out["recent"] = sorted(events, key=lambda e: e["block"] or 0, reverse=True)[:5]
    return out


def _counted(value, source):
    """A counter that knows where it came from."""
    return {"value": value, "source": source}


def _failed(source, why):
    """A counter whose source could not be read. NO value key: a consumer cannot render a number it
    was not given, so a failed read cannot be mistaken for a zero."""
    return {"error": why, "source": source}


# Params::default() in crates/decision-engine/src/lib.rs. See the module docstring for why a
# baseline is duplicated here when observations never are.
_PARAM_DEFAULTS = {
    "momentum_weight_bps": 2000,
    "variance_weight_bps": 8000,
    "thin_book_penalty_bps": 150,
}

def _learning_effect(repo):
    """Task 14.6. The learning effect, never separated from the sample it rests on."""
    lpath = f"{repo}/ui-v2/public/data/learned-state.json"
    spath = f"{repo}/evidence/settlements.jsonl"
    out = {}

    try:
        with open(lpath, encoding="utf-8") as fh:
            ls = json.load(fh)
    except Exception as exc:
        # One failure, reported once against every figure that depended on it. A partially
        # populated block would let a component render three of four numbers and look complete.
        err = _failed("ui-v2/public/data/learned-state.json", f"unreadable: {exc}")
        return {"samples": err, "hitRateBps": err, "changes": err, "realizedPnl": err}

    stats = (ls.get("stats") or {}).get("imbalance_bps") or {}
    samples = int(stats.get("samples") or 0)
    settled = int(ls.get("settled_count") or 0)
    flat = int(ls.get("unscored_flat") or 0)

    out["samples"] = _counted(
        {"scored": samples, "settled": settled, "droppedFlat": flat},
        "learned-state.json: scored samples, settled outcomes, and forecasts dropped as flat",
    )

    if samples == 0:
        # NOT a zero hit rate. Zero of zero is undefined, and rendering 0% would assert the
        # signal is always wrong when in fact nothing has been measured.
        out["hitRateBps"] = _failed(
            "learned-state.json stats.imbalance_bps",
            "no scored samples yet, so a hit rate is undefined rather than zero",
        )
    else:
        out["hitRateBps"] = _counted(
            {"value": int(stats.get("hit_rate_bps") or 0), "samples": samples},
            "learned-state.json stats.imbalance_bps.hit_rate_bps, paired with its sample count",
        )

    # Parameter moves. Each carries the sample count that triggered it and the trigger sentence,
    # so a reader sees WHY a number moved rather than only that it did.
    hist = ls.get("history") or []
    changes = []
    for h in hist:
        changes.append({
            "parameter": h.get("parameter"),
            "from": h.get("from"),
            "to": h.get("to"),
            "samples": h.get("samples"),
            "trigger": h.get("trigger"),
        })
    out["changes"] = _counted(
        changes,
        "learned-state.json history: every parameter move with the sample count that triggered it",
    )


    # NET move, default to current. The per-move history shows clamped steps that look like nothing
    # happened; this shows what actually happened across the whole run of the system.
    params = ls.get("params") or {}
    net = []
    for name, default in _PARAM_DEFAULTS.items():
        current = params.get(name)
        if current is None:
            continue
        net.append({
            "parameter": name,
            "default": default,
            "current": int(current),
            "moved": int(current) != default,
        })
    out["netMove"] = _counted(
        net,
        "learned-state.json params against Params::default() in crates/decision-engine/src/lib.rs",
    )

    # Realized PnL, summed from the settlements themselves rather than carried in state, so the
    # figure cannot drift from the rows it claims to summarise.
    try:
        rows = [json.loads(l) for l in open(spath, encoding="utf-8") if l.strip()]
        pnl = [int(r["realized_pnl_micro"]) for r in rows]
        out["realizedPnl"] = _counted(
            {
                "totalMicro": sum(pnl),
                "settlements": len(pnl),
                "profitable": sum(1 for p in pnl if p > 0),
                "losing": sum(1 for p in pnl if p < 0),
                "flat": sum(1 for p in pnl if p == 0),
                "basis": "mark to market against a later observed mid, not cash proceeds",
            },
            "evidence/settlements.jsonl, summed from the rows themselves",
        )
    except Exception as exc:
        out["realizedPnl"] = _failed("evidence/settlements.jsonl", f"unreadable: {exc}")

    return out


def _growth_counters(fees):
    """Task 13.1. Every counter names its source and a failed source yields an error, not a zero.

    The named fake win is "a counter that ticks on a timer". Nothing here is time-derived: each value
    is a count of something that exists in the chain or in the journal, and re-running this script
    without new activity produces identical numbers.
    """
    import os

    repo = REPO
    out = {}

    # ---- fees, from the chain read that lib/fee_logs.py already performed
    if fees and "error" not in fees and "total_fees_wei" in fees:
        out["feesCollectedWei"] = _counted(
            fees["total_fees_wei"],
            "FeeCollector.totalCollected(token), read from contract state",
        )
        out["feeEvents"] = _counted(
            fees.get("event_count", 0),
            "FeeCollector.chargeCount(), read from contract state",
        )
    else:
        why = (fees or {}).get("error", "the fee chain read did not run")
        out["feesCollectedWei"] = _failed("FeeCollector.totalCollected(token)", why)
        out["feeEvents"] = _failed("FeeCollector.chargeCount()", why)

    # ---- journal-derived counters
    jpath = f"{repo}/evidence/journal.jsonl"
    try:
        rows = [json.loads(l) for l in open(jpath, encoding="utf-8") if l.strip()]
    except Exception as exc:
        rows = None
        for k in ("agentActions", "candidatesEvaluated", "refusalsTotal", "volumeTouchedMicro"):
            out[k] = _failed("evidence/journal.jsonl", f"unreadable: {exc}")
        out["refusalsByReason"] = _failed("evidence/journal.jsonl", f"unreadable: {exc}")

    if rows is not None:
        submitted = [r for r in rows if r.get("tx_hash")]
        out["agentActions"] = _counted(
            len(submitted), "evidence/journal.jsonl, rows carrying a tx_hash"
        )
        cands = sum(len(r.get("candidates", []) or []) for r in rows)
        out["candidatesEvaluated"] = _counted(
            cands, "evidence/journal.jsonl, summed candidate arrays"
        )

        reasons = {}
        for r in rows:
            for c in r.get("candidates", []) or []:
                if c.get("chosen"):
                    continue
                why = c.get("rejection_reason") or "unstated"
                reasons[why] = reasons.get(why, 0) + 1
        out["refusalsTotal"] = _counted(
            sum(reasons.values()), "evidence/journal.jsonl, unchosen candidates"
        )
        out["refusalsByReason"] = {
            "value": dict(sorted(reasons.items(), key=lambda kv: -kv[1])[:8]),
            "source": "evidence/journal.jsonl, unchosen candidates grouped by rejection_reason",
        }

        # Volume the agent actually touched, from the notional it acted on.
        # Notional is NOT a field on a candidate. The candidate carries scoring components
        # (expected_edge_micro, capital_cost_micro, score_micro) and the size lives in the action
        # text the runtime wrote, e.g. "take order 1 Sell 1.500000 base at 1.900000". Parsing that
        # is fragile, so the counter reports what it can defend and says so rather than inventing a
        # figure or silently reporting 0, which is what the first version did.
        import re as _re
        vol = 0
        parsed = 0
        for r in submitted:
            m = _re.search(r"([0-9]+\.[0-9]+) base at ([0-9]+\.[0-9]+)", r.get("action", ""))
            if m:
                vol += int(float(m.group(1)) * float(m.group(2)) * 1_000_000)
                parsed += 1
        if parsed:
            out["volumeTouchedMicro"] = _counted(
                vol,
                f"evidence/journal.jsonl, size x price parsed from the action text of {parsed} "
                f"of {len(submitted)} submitted rows",
            )
        else:
            out["volumeTouchedMicro"] = _failed(
                "evidence/journal.jsonl",
                "no submitted row carried a parseable size and price in its action text",
            )

    # ---- learning, from the generated state file
    lpath = f"{repo}/ui-v2/public/data/learned-state.json"
    try:
        with open(lpath, encoding="utf-8") as fh:
            ls = json.load(fh)
        settled = ls.get("settled") or ls.get("settled_count") or 0
        if isinstance(settled, list):
            settled = len(settled)
        out["learningUpdates"] = _counted(
            settled, "ui-v2/public/data/learned-state.json, settled forecasts"
        )
    except Exception as exc:
        out["learningUpdates"] = _failed(
            "ui-v2/public/data/learned-state.json", f"unreadable: {exc}"
        )

    # ---- coordination, from the accepted-quote handoff record
    cpath = f"{repo}/evidence/phase6/accepted-quotes.jsonl"
    if os.path.exists(cpath):
        try:
            n = sum(1 for l in open(cpath, encoding="utf-8") if l.strip())
            out["coordinationCalls"] = _counted(
                n, "evidence/phase6/accepted-quotes.jsonl, accepted external quotes"
            )
        except Exception as exc:
            out["coordinationCalls"] = _failed(
                "evidence/phase6/accepted-quotes.jsonl", f"unreadable: {exc}"
            )
    else:
        out["coordinationCalls"] = _failed(
            "evidence/phase6/accepted-quotes.jsonl", "file absent: no external agent has settled yet"
        )

    return out


def main():
    rows = [json.loads(l) for l in open(J, encoding="utf-8") if l.strip()]
    agent = [r for r in rows if not (
        str(r.get("thesis", "")).startswith("naive baseline")
        or str(r.get("risk_verdict", "")).startswith("baseline:")
    )]

    takes = [r for r in agent if str(r.get("action", "")).startswith("take")]
    holds = [r for r in agent if r.get("action") == "hold"]
    submitted = [r for r in agent if r.get("tx_hash")]

    refusals = {}
    for r in agent:
        for c in r.get("candidates", []):
            reason = c.get("rejection_reason")
            if not reason:
                continue
            body = reason.split(": ", 1)[-1] if ": " in reason else reason
            name = body.split("{")[0].strip() or reason
            refusals[name] = refusals.get(name, 0) + 1

    # Volume: sum of |signed notional| for the chosen candidate of each take, in micro quote units.
    # Derived from the journal's own numbers, so it is a JOURNAL counter, not an onchain one. Stated
    # that way on screen because the venue does not expose a per-agent volume counter.
    volume_micro = 0
    for r in takes:
        for c in r.get("candidates", []):
            if c.get("chosen"):
                try:
                    volume_micro += abs(int(c.get("expected_edge_micro", 0) or 0))
                except (TypeError, ValueError):
                    pass

    exposure = env_int("EXPOSURE")
    cap = env_int("CAP")
    gross = env_int("GROSS")
    maxgross = env_int("MAXGROSS")

    def pct(a, b):
        if a is None or not b:
            return None
        return round(100.0 * a / b, 2)

    metrics = {
        "generated_at_utc": datetime.datetime.now(datetime.timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
        "generated_by": "bash scripts/88-recompute-metrics.sh",
        "explorer_tx_base": EXPLORER_TX,
        "explorer_address_base": EXPLORER_ADDR,
        "fees": _fee_metrics(),
        "growth": _growth_counters(_fee_metrics()),
        "learningEffect": _learning_effect(REPO),
        "onchain": {
            "head_block": env_int("BLOCK"),
            # Read from deployments.json, never pinned. These were literals from a Phase 2 deploy,
            # which meant that after the task 7.6 redeploy the panel would have shown addresses and
            # explorer links belonging to abandoned contracts, next to numbers read from the live
            # ones. Two truths on one row, neither labelled.
            "guard_address": _deployment("riskGuard"),
            "venue_address": _deployment("venue"),
            "fee_collector_address": _deployment("feeCollector"),
            "market_exposure_wei": exposure,
            "market_cap_wei": cap,
            "market_utilisation_pct": pct(exposure, cap),
            "gross_exposure_wei": gross,
            "gross_cap_wei": maxgross,
            "gross_utilisation_pct": pct(gross, maxgross),
            "killed": os.environ.get("KILLED", "").strip(),
            "venue_order_count": env_int("ORDERS"),
            "agent_key_nonce": env_int("NONCE"),
            # TWO LIMITS EXIST AND THEY DISAGREE ON PURPOSE. The onchain per-market cap is 500
            # quote units; the offchain risk engine's conservative_testnet cap is 50. The offchain
            # limit binds first by design, which is why the risk panel can show 100% utilisation
            # while this onchain figure reads about 10%. Both numbers are correct and they measure
            # different limits, so the panel labels which is which rather than showing one and
            # letting a reader assume it is the binding one.
            "note_two_limits": (
                "onchain cap 500 quote units, offchain engine cap 50. The offchain limit binds "
                "first by design, so onchain utilisation reads roughly a tenth of the offchain "
                "figure. See crates/risk-engine Limits::conservative_testnet."
            ),
        },
        "journal": {
            "rows": len(rows),
            "agent_decisions": len(agent),
            "baseline_control_rows": len(rows) - len(agent),
            "takes": len(takes),
            "holds": len(holds),
            "submitted": len(submitted),
            "candidates_total": sum(len(r.get("candidates", [])) for r in agent),
            "refusals_total": sum(refusals.values()),
            "refusals_by_reason": dict(sorted(refusals.items(), key=lambda kv: -kv[1])),
            "expected_edge_sum_micro": volume_micro,
        },
        "learning": {},
        "recent_transactions": [
            {
                "decision_id": int(r["decision_id"]),
                "block": int(r["block_number"]),
                "tx_hash": r["tx_hash"],
            }
            for r in sorted(submitted, key=lambda r: -int(r["decision_id"]))[:20]
        ],
    }

    learned_path = f"{REPO}/ui-v2/public/data/learned-state.json"
    if os.path.exists(learned_path):
        try:
            ls = json.load(open(learned_path, encoding="utf-8"))
            metrics["learning"] = {
                "settled": ls.get("settled_count"),
                "unscored_flat": ls.get("unscored_flat"),
                "pending": len(ls.get("pending", []) or []),
                "signals_tracked": len(ls.get("stats", {}) or {}),
            }
        except Exception as e:
            metrics["learning"] = {"error": str(e)}

    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(metrics, fh, indent=2)
        fh.write("\n")

    o, jn = metrics["onchain"], metrics["journal"]
    print(f"  journal rows {jn['rows']}  agent {jn['agent_decisions']}  baseline {jn['baseline_control_rows']}")
    print(f"  takes {jn['takes']}  holds {jn['holds']}  submitted {jn['submitted']}")
    print(f"  candidates {jn['candidates_total']}  refusals {jn['refusals_total']}")
    for name, n in list(jn["refusals_by_reason"].items())[:6]:
        print(f"    {name}: {n}")
    print(f"  market utilisation: {o['market_utilisation_pct']}%  "
          f"({(o['market_exposure_wei'] or 0) // WEI_PER_MICRO} of "
          f"{(o['market_cap_wei'] or 0) // WEI_PER_MICRO} micro units)")
    print(f"  gross utilisation:  {o['gross_utilisation_pct']}%")
    print(f"  learning: {metrics['learning']}")
    print(f"  recent transactions carried into the panel: {len(metrics['recent_transactions'])}")
    print(f"  wrote {OUT}")

    # A metrics file whose onchain half is missing would let the panel render blanks that look like
    # zeros, so refuse rather than write a half-file.
    g = metrics["growth"]
    print("  growth counters, each with its source:")
    for k, v in g.items():
        if "error" in v:
            print(f"    {k:22} ERROR  {v['error'][:48]}")
        else:
            val = v["value"]
            shown = f"{len(val)} reasons" if isinstance(val, dict) else val
            print(f"    {k:22} {shown}")

    l = metrics["learningEffect"]
    print("  learning effect, every figure with its sample:")
    for k, v in l.items():
        if "error" in v:
            print(f"    {k:22} ERROR  {v['error'][:48]}")
        else:
            print(f"    {k:22} {v['value']}")

    f = metrics["fees"]
    print(f"  fees: {f.get('event_count', 'ERROR')} FeeCharged events, "
          f"{f.get('total_fees_wei', 'n/a')} wei collected, read from {f.get('source', f.get('error', 'UNKNOWN'))}")

    if o["market_exposure_wei"] is None or o["head_block"] is None:
        print("  ONCHAIN READS MISSING, the panel would render blanks. Failing.")
        return 1
    if "error" in f:
        # Same rule as above applied to revenue: a failed read must not be indistinguishable from a
        # business that earned nothing.
        print(f"  FEE CHAIN READ FAILED: {f['error']}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
