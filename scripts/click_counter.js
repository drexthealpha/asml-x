/**
 * Task 9.4 click counter. Installed in the page BEFORE the flow starts.
 *
 * PASS: three or fewer clicks from a connected wallet to a running agent, "counting every click
 * including wallet confirmations that the app triggers".
 *
 * THE NAMED FAKE WIN is "counting only in-app clicks and ignoring wallet confirmations", and its
 * counter is that the evidence must list them individually. So this instruments BOTH:
 *
 *   1. A capturing `click` listener on document, which sees every real user click before any
 *      handler can stop propagation. Counting `onClick` props would miss clicks the app swallows.
 *
 *   2. A wrapper around `window.ethereum.request`, which records every call the app makes that a
 *      real wallet would put behind a confirmation UI. With an extension each of these IS a user
 *      interaction: `eth_sendTransaction` shows a confirm dialog, `eth_signTypedData_v4` shows a
 *      sign dialog. The headless provider approves them programmatically, so counting the CALLS is
 *      how the extension's clicks are accounted for while task 9.0 is outstanding (ADR-016).
 *
 * Methods that a wallet answers WITHOUT prompting are listed explicitly and excluded, rather than
 * excluded by omission: `eth_chainId`, `eth_accounts`, `eth_call` and `net_version` are silent
 * reads. `eth_requestAccounts` DOES prompt, but connection happens before this counter starts,
 * because the task counts "from a connected wallet".
 */
(() => {
  const PROMPTS = new Set([
    "eth_sendTransaction",
    "eth_signTypedData_v4",
    "eth_signTypedData",
    "personal_sign",
    "eth_sign",
    "wallet_switchEthereumChain",
    "wallet_addEthereumChain",
    "eth_requestAccounts",
  ]);

  // Silent, and named so the exclusion is a decision rather than an oversight.
  const SILENT = new Set(["eth_chainId", "eth_accounts", "eth_call", "net_version", "eth_blockNumber"]);

  const log = [];
  window.__asmlClicks = log;

  document.addEventListener(
    "click",
    (e) => {
      const el = e.target instanceof Element ? e.target.closest("button, a, [role=button]") : null;
      log.push({
        kind: "app-click",
        at: Date.now(),
        testId: el ? el.getAttribute("data-testid") : null,
        text: el ? (el.textContent || "").trim().slice(0, 60) : "(non-control)",
      });
    },
    true, // capture: seen before any handler can stop it
  );

  const p = window.ethereum;
  if (p && !p.__asmlCounted) {
    const original = p.request.bind(p);
    p.request = async (args) => {
      const m = args && args.method;
      if (PROMPTS.has(m)) {
        log.push({ kind: "wallet-prompt", at: Date.now(), method: m });
      } else if (!SILENT.has(m)) {
        log.push({ kind: "wallet-other", at: Date.now(), method: m });
      }
      return original(args);
    };
    p.__asmlCounted = true;
  }

  window.__asmlCountSummary = () => {
    const appClicks = log.filter((l) => l.kind === "app-click").length;
    const walletPrompts = log.filter((l) => l.kind === "wallet-prompt").length;
    return {
      total: appClicks + walletPrompts,
      appClicks,
      walletPrompts,
      // Every interaction, individually, because the task's counter requires the evidence to list
      // them rather than report a number.
      entries: log.map((l) =>
        l.kind === "app-click"
          ? `app-click: ${l.testId || "?"} "${l.text}"`
          : `${l.kind}: ${l.method}`,
      ),
    };
  };

  return "click counter installed";
})()
