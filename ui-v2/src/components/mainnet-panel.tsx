/**
 * Mainnet proof, task 12.7.
 *
 * PASS: every mainnet hash is reachable in ONE CLICK from this surface and from the JUDGE-GUIDE.
 * So every row here is an anchor to the explorer, not a hash a reader has to copy and paste.
 *
 * THINKING: #12 design thinking (a judge should not have to assemble a URL), #60 map-territory.
 *
 * PATTERNS APPLIED (evidence/ui-study.md):
 * - `orderbook-row.tsx:34` 12px `tabular-nums` rows at `py-0.5 px-2` with a hairline separator, so
 *   a column of hashes aligns and can be scanned rather than read.
 * - `orderbook-panel.tsx:151-153` distinct sentences for distinct situations: a missing manifest
 *   renders an error naming the file, never an empty panel that reads as "no mainnet activity".
 * - `orderbook-panel.tsx:121-137` controls live in the labels they affect; each row's link IS the
 *   hash, so there is no separate "view" affordance to hunt for.
 *
 * THE EXPLORER URL FORM IS THE CANONICAL ONE, for BOTH addresses and transactions.
 *
 * Task 11.1 loaded an ADDRESS url in a real browser and found `/x-layer/address/<addr>` redirects to
 * `/x-layer/evm/address/<addr>`. Task 12.7 then loaded a TRANSACTION url and found the same thing:
 * `/x-layer/tx/<hash>` redirects to `/x-layer/evm/tx/<hash>`. The second was missed on the first
 * pass because fixing the address form felt like the whole lesson, and it was half of it.
 *
 * `curl -L` follows both redirects silently and reports 200, so neither stale form looks wrong from
 * a shell. Redirects stop being served without warning, so the manifest carries the post-redirect
 * form for both and this component uses them verbatim.
 *
 * EVERYTHING COMES FROM `data/mainnet.json`, which `scripts/159-mainnet-manifest.sh` generates by
 * scraping hashes out of the Phase 12 evidence files. A hash cannot appear here unless an evidence
 * document recorded it, and the panel computes nothing.
 */

import { useEffect, useState } from "react";
import { Panel, PanelEmpty, PanelError } from "./primitives";

interface MainnetContract {
  name: string;
  address: string;
}

interface MainnetTx {
  hash: string;
  what: string;
  source: string;
}

interface MainnetManifest {
  chainId: number;
  chainName: string;
  explorerTx: string;
  explorerAddress: string;
  contracts: MainnetContract[];
  transactions: MainnetTx[];
}

function short(h: string): string {
  return h.length > 20 ? `${h.slice(0, 10)}...${h.slice(-8)}` : h;
}

export function MainnetPanel() {
  const [m, setM] = useState<MainnetManifest | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void fetch("data/mainnet.json", { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(setM)
      .catch((e) => setError(String(e.message ?? e)));
  }, []);

  if (error) {
    return (
      <Panel title="Mainnet" meta="chain 196">
        <PanelError source="data/mainnet.json" reason={error} />
      </Panel>
    );
  }
  if (!m) {
    return (
      <Panel title="Mainnet" meta="chain 196">
        <PanelEmpty what="the mainnet manifest" />
      </Panel>
    );
  }

  return (
    <Panel title="Mainnet" meta={`${m.chainName}, chain ${m.chainId}`}>
      <div className="flex-1 min-h-0 overflow-y-auto">
        <div className="px-2 py-1.5">
          <p className="text-xs text-[var(--text-weak)]">
            This is not a testnet demo. Every hash below is on X Layer mainnet and opens in the
            explorer in one click.
          </p>
        </div>

        <div className="px-2 py-1 text-3xs uppercase tracking-wider text-[var(--text-weak)] border-b hairline">
          Transactions ({m.transactions.length})
        </div>
        {m.transactions.map((t) => (
          <div
            key={t.hash}
            className="grid grid-cols-[auto_minmax(0,1fr)] gap-2 px-2 py-0.5 border-b hairline last:border-b-0 hover:bg-[var(--fill-hover)]"
          >
            <a
              className="num text-2xs"
              style={{ color: "var(--status-info)" }}
              href={`${m.explorerTx}${t.hash}`}
              target="_blank"
              rel="noreferrer noopener"
              data-testid="mainnet-tx"
              data-hash={t.hash}
            >
              {short(t.hash)}
            </a>
            <span className="text-2xs truncate text-[var(--text-weak)]">{t.what}</span>
          </div>
        ))}

        <div className="px-2 py-1 text-3xs uppercase tracking-wider text-[var(--text-weak)] border-b hairline">
          Contracts ({m.contracts.length})
        </div>
        {m.contracts.map((c) => (
          <div
            key={c.address}
            className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-2 py-0.5 border-b hairline last:border-b-0 hover:bg-[var(--fill-hover)]"
          >
            <span className="text-2xs text-[var(--text-weak)]">{c.name}</span>
            <a
              className="num text-2xs"
              style={{ color: "var(--status-info)" }}
              href={`${m.explorerAddress}${c.address}`}
              target="_blank"
              rel="noreferrer noopener"
              data-testid="mainnet-contract"
              data-address={c.address}
            >
              {short(c.address)}
            </a>
          </div>
        ))}

        <p className="px-2 py-2 text-3xs text-[var(--text-weak)]">
          Generated by scripts/159-mainnet-manifest.sh from the Phase 12 evidence files. A hash cannot
          appear here unless an evidence document recorded it.
        </p>
      </div>
    </Panel>
  );
}
