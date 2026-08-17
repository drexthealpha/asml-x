# Chain verification report

Run 2026-08-17 07:32:43 UTC. dry=1

| id | evidence exists | command | result |
|---|---|---|---|
| C-202 | yes | `bash scripts/67-verify-deployments.sh` | dry, not run |
| C-203 | yes | `bash scripts/67-verify-deployments.sh` | dry, not run |
| C-204 | yes | `bash scripts/67-verify-deployments.sh` | dry, not run |
| C-205 | yes | `bash scripts/67-verify-deployments.sh` | dry, not run |
| C-211 | yes | `bash scripts/68-verify-tx-claims.sh` | dry, not run |
| C-220 | yes | `bash scripts/45c-halmos-upgrade.sh` | dry, not run |
| C-221 | yes | `bash scripts/47d-hevm-argotorg.sh` | dry, not run |
| C-222 | yes | `bash scripts/48-scribble-smoke.sh` | dry, not run |
| C-223 | yes | `bash scripts/46-kontrol-smoke.sh` | dry, not run |
| C-224 | yes | `bash scripts/56-act-install.sh` | dry, not run |
| C-230 | yes | `bash scripts/59-cargo-mutants.sh` | dry, not run |
| C-231 | yes | `bash scripts/66-remutate.sh` | dry, not run |
| C-240 | yes | `bash scripts/64-graph-query-log.sh` | dry, not run |
| C-241 | yes | `bash scripts/64-graph-query-log.sh` | dry, not run |
| C-250 | yes | `bash scripts/51-paperscraper-smoke.sh` | dry, not run |
| C-251 | yes | `bash scripts/55-river-smoke.sh` | dry, not run |
| C-252 | yes | `bash scripts/62-support-tools.sh` | dry, not run |
| C-260 | yes | `bash scripts/58-codebase-memory-mcp.sh` | dry, not run |
| C-261 | yes | `bash scripts/57c-gemini-429.sh` | dry, not run |
| C-262 | yes | `bash scripts/61-frontend-scaffold.sh` | dry, not run |
| C-263 | yes | `bash scripts/45-toolchain-floor.sh` | dry, not run |
| C-201 | yes | `bash scripts/63-claim-inventory.sh` | dry, not run |
| C-270 | yes | `grep -rn 'reqwest` | dry, not run |
| C-300 | yes | `bash scripts/73-clone-hypeterminal.sh` | dry, not run |
| C-301 | yes | `bash scripts/74-verify-ui-study.sh` | dry, not run |
| C-302 | yes | `bash scripts/74-verify-ui-study.sh` | dry, not run |
| C-232 | yes | `bash scripts/66-remutate.sh` | dry, not run |
| C-121 | yes | `bash scripts/77-journal-scale-audit.sh` | dry, not run |
| C-401 | yes | `bash scripts/78-ui-data.sh then serve ui-v2 and run scripts/measure-density.js` | dry, not run |
| C-402 | yes | `cp -r ui-v2/dist /tmp/nodata && rm -rf /tmp/nodata/data && python3 -m http.server` | dry, not run |
| C-403 | yes | `bash scripts/78-ui-data.sh` | dry, not run |
| C-120 | yes | `bash scripts/71-alloy-smoke.sh && bash scripts/71b-alloy-run.sh` | dry, not run |
| C-127 | yes | `grep -cE '^. [^` | dry, not run |
| C-122 | yes | `bash scripts/72-revm-smoke.sh && bash scripts/72b-revm-run.sh` | dry, not run |
| C-128 | yes | `bash scripts/82-repro-audit.sh` | dry, not run |
| C-404 | yes | `bash scripts/80-ui-redteam.sh` | dry, not run |
| C-405 | yes | `bash scripts/84-journal-split.sh && bash scripts/77-journal-scale-audit.sh` | dry, not run |
| C-406 | yes | `bash scripts/78-ui-data.sh then serve ui-v2 and run scripts/measure-density.js` | dry, not run |
| C-407 | yes | `bash scripts/86-seam-test.sh` | dry, not run |
| C-408 | yes | `serve ui-v2 then paste scripts/measure-contrast.js in the console` | dry, not run |
| C-409 | yes | `bash scripts/78-ui-data.sh then read the Live brain signals table` | dry, not run |
| C-410 | yes | `bash scripts/serve-ui.sh then paste scripts/measure-overflow.js in the console` | dry, not run |
| C-500 | yes | `bash scripts/88-recompute-metrics.sh` | dry, not run |
| C-501 | yes | `bash scripts/87-assert-no-magic-numbers.sh` | dry, not run |
| C-502 | yes | `bash scripts/89-journal-load-test.sh then paste scripts/measure-feed.js in the console` | dry, not run |
| C-503 | yes | `bash scripts/90-comparator-states.sh` | dry, not run |
| C-504 | yes | `bash scripts/91-assert-comparator-states.sh` | dry, not run |
| C-505 | yes | `bash scripts/78-ui-data.sh then open the Chain view` | dry, not run |
| C-506 | yes | `bash scripts/92-phase5-redteam.sh then open http://localhost:4177` | dry, not run |
| C-600 | yes | `ASML_RATE_LIMIT=20 bash scripts/26-coordination-live.sh` | dry, not run |
| C-601 | yes | `bash scripts/94-coord-probe.sh` | dry, not run |
| C-602 | yes | `ASML_RATE_LIMIT=20 bash scripts/26-coordination-live.sh` | dry, not run |
| C-603 | yes | `bash scripts/96-external-settlement.sh` | dry, not run |
| C-604 | yes | `bash scripts/97-adversarial-callers.sh` | dry, not run |
| C-605 | yes | `bash scripts/98-signing-latency.sh` | dry, not run |
| C-606 | yes | `bash scripts/99-examples-run.sh` | dry, not run |
| C-701 | yes | `bash scripts/100-fee-pattern-research.sh` | dry, not run |
| C-702 | yes | `cd contracts && forge test --match-contract FeeCollectorTest` | dry, not run |
| C-703 | yes | `bash scripts/101-fee-bypass-gate.sh` | dry, not run |
| C-704 | yes | `bash scripts/102-fee-bypass-mutation.sh` | dry, not run |
| C-705 | yes | `bash scripts/104b-fee-formal.sh` | dry, not run |
| C-706 | yes | `bash scripts/104-fee-mutation.sh` | dry, not run |
| C-707 | yes | `bash scripts/105-fee-live-testnet.sh` | dry, not run |
| C-708 | yes | `bash scripts/107-fee-ui-gate.sh` | dry, not run |
| C-709 | yes | `bash scripts/12-deploy-venue.sh` | dry, not run |
| C-710 | yes | `bash scripts/109-phase7-redteam.sh` | dry, not run |
| C-800 | yes | `bash scripts/111-vault-research.sh` | dry, not run |
| C-801 | yes | `bash scripts/112b-vault-tests.sh` | dry, not run |
| C-802 | yes | `bash scripts/112d-per-user-limits.sh` | dry, not run |
| C-803 | yes | `bash scripts/112e-vault-formal.sh` | dry, not run |
| C-804 | yes | `bash scripts/112-vault-mutation.sh` | dry, not run |
| C-805 | yes | `bash scripts/113-vault-live.sh` | dry, not run |
| C-806 | yes | `bash scripts/114-pause-under-load.sh` | dry, not run |
| C-807 | yes | `bash scripts/115-phase8-redteam.sh` | dry, not run |
| C-900 | yes | `bash scripts/130-connect-flow.sh` | dry, not run |
| C-901 | yes | `bash scripts/131-landing-audit.sh` | dry, not run |
| C-902 | yes | `bash scripts/132-defaults-audit.sh` | dry, not run |
| C-903 | yes | `bash scripts/133-click-count.sh` | dry, not run |
| C-904 | yes | `bash scripts/134-exit-controls-audit.sh` | dry, not run |
| C-905 | yes | `bash scripts/135-demo-button.sh` | dry, not run |
| C-906 | yes | `serve ui-v2, then run scripts/dashboard_audit.js in the Browser pane` | dry, not run |
| C-907 | yes | `serve ui-v2, then run scripts/failure_paths_audit.js in the Browser pane` | dry, not run |
| C-908 | yes | `bash scripts/139-fee-disclosure.sh` | dry, not run |
| C-909 | yes | `bash scripts/140-phase9-redteam.sh` | dry, not run |
| C-1000 | yes | `bash scripts/143-flow-timing.sh` | dry, not run |
| C-1001 | yes | `bash scripts/142-cold-user-runs.sh` | dry, not run |
| C-1002 | yes | `bash scripts/144-claim-consistency.sh` | dry, not run |
| C-1100 | yes | `bash scripts/146-mainnet-facts.sh` | dry, not run |
| C-1101 | yes | `bash scripts/147-gas-inventory.sh` | dry, not run |
| C-1102 | yes | `bash scripts/148-mainnet-budget.sh` | dry, not run |
| C-1103 | yes | `bash scripts/149-mainnet-dryrun.sh` | dry, not run |
| C-1104 | yes | `bash scripts/151-deploy-plan.sh` | dry, not run |
| C-1105 | yes | `bash scripts/150d-call-discovered.sh` | dry, not run |
| C-1106 | yes | `bash scripts/150-reverse-engineer-196.sh` | dry, not run |
| C-1200 | yes | `bash scripts/153-mainnet-deploy.sh` | dry, not run |
| C-1201 | yes | `bash scripts/154-mainnet-loop.sh` | dry, not run |
| C-1202 | yes | `bash scripts/155-mainnet-refusal.sh` | dry, not run |
| C-1203 | yes | `bash scripts/156-mainnet-fee.sh` | dry, not run |
| C-1204 | yes | `bash scripts/157-mainnet-personal.sh` | dry, not run |
| C-1205 | yes | `bash scripts/158-mainnet-cost.sh` | dry, not run |
| C-1206 | yes | `bash scripts/159-mainnet-manifest.sh` | dry, not run |
| C-1300 | yes | `bash scripts/161-growth-counters.sh` | dry, not run |
| C-1301 | yes | `bash scripts/160-coordination-metering.sh` | dry, not run |
| C-1302 | yes | `bash scripts/161-growth-counters.sh` | dry, not run |
| C-1400 | yes | `bash scripts/164-differential-proof.sh` | dry, not run |
| C-1401 | yes | `bash scripts/166-vault-invariants.sh` | dry, not run |
| C-1402 | yes | `bash scripts/165-decision-trace.sh` | dry, not run |
| C-1403 | yes | `bash scripts/168-realized-pnl.sh && bash scripts/169-settle-with-real-move.sh` | dry, not run |
| C-1404 | yes | `bash scripts/168-realized-pnl.sh` | dry, not run |
| C-1405 | yes | `bash scripts/172-river-profit-target.sh` | dry, not run |
| C-1406 | yes | `bash scripts/174-learning-effect.sh` | dry, not run |
| C-1407 | yes | `cargo test -p learning` | dry, not run |
| C-1408 | yes | `bash scripts/176-phase14-audit.sh` | dry, not run |
| C-1500 | yes | `bash scripts/178-adversarial-fee-vault.sh` | dry, not run |
| C-1501 | yes | `bash scripts/179-protocol-version.sh` | dry, not run |
| C-1600 | yes | `bash scripts/183-reproduce.sh` | dry, not run |
| C-1601 | yes | `python3 scripts/181-repro-inventory.py` | dry, not run |
| C-1602 | yes | `bash scripts/184-mainnet-reverify.sh` | dry, not run |
| C-1603 | yes | `python3 scripts/185-fake-win-register.py` | dry, not run |
| C-1700 | yes | `python3 scripts/187-claim-tags.py` | dry, not run |
| C-1701 | yes | `python3 scripts/187-claim-tags.py` | dry, not run |
| C-1702 | yes | `python3 scripts/187-claim-tags.py` | dry, not run |
| C-1703 | yes | `python3 scripts/187-claim-tags.py` | dry, not run |
| C-1704 | yes | `bash scripts/144-claim-consistency.sh` | dry, not run |
| C-1800 | yes | `bash scripts/190-record-phase18.sh` | dry, not run |
| C-1802 | yes | `bash scripts/189-final-sweep.sh` | dry, not run |

## Summary

- rows: 126
- commands passed: 0
- commands failed: 0
- evidence artifacts missing: 0
- skipped (dry or no command): 126
