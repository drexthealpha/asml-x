/**
 * A REAL, key-backed EIP-1193 provider for verifying the connect flow, per ADR-016.
 *
 * WHAT THIS IS NOT: a stub that returns a hardcoded address. That is task 9.1's named fake win,
 * verbatim: "a Connect button that sets local state without touching a provider." A stub would make
 * every gate in Phase 9 green and prove nothing.
 *
 * WHAT THIS IS: a wallet implementation with no user interface. It holds a real X Layer testnet
 * private key, derives its address from that key, answers `eth_chainId` by asking
 * https://testrpc.xlayer.tech rather than by returning a literal, and signs and broadcasts real
 * transactions that land in real blocks. The application under test cannot distinguish it from an
 * extension because it implements the same interface.
 *
 * The one thing it does not reproduce is the extension's confirmation popup, which ADR-016 records
 * and which task 9.4 accounts for explicitly rather than ignoring.
 *
 * REJECTION MODE: setting `window.__asmlReject = true` makes the next request fail with EIP-1193
 * code 4001, which is exactly what a wallet returns when a user clicks Reject. Task 9.8 uses it to
 * exercise the rejection path for real rather than by inspection.
 *
 * WRONG-CHAIN MODE: `window.__asmlChainOverride = '0x1'` makes `eth_chainId` report Ethereum
 * mainnet, so the wrong-network branch is reachable without asking a human to switch networks.
 */
(function installAsmlProvider(address, rpcUrl) {
  let requestId = 1;

  async function rpc(method, params) {
    const res = await fetch(rpcUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: requestId++, method, params: params || [] }),
    });
    const body = await res.json();
    if (body.error) {
      const e = new Error(body.error.message || "rpc error");
      e.code = body.error.code;
      throw e;
    }
    return body.result;
  }

  function rejected() {
    const e = new Error("User rejected the request.");
    e.code = 4001;
    return e;
  }

  const listeners = {};
  let authorised = false;

  const provider = {
    isAsmlHeadless: true,
    /** Stated in the object itself so any evidence dump records which provider produced it. */
    providerLabel: "asml-headless-eip1193 (real key, real RPC, no popup) per ADR-016",

    async request({ method, params }) {
      if (window.__asmlReject) throw rejected();

      switch (method) {
        case "eth_accounts":
          // Authorised accounts only. Before connect this is empty, which is what lets the landing
          // surface avoid prompting on load.
          return authorised ? [address] : [];

        case "eth_requestAccounts":
          authorised = true;
          // A REAL WALLET EMITS accountsChanged WHEN ACCOUNTS ARE FIRST AUTHORISED, and this
          // provider did not. The omission was invisible while only one component connected, because
          // that component gets the accounts as the return value. It surfaced the moment a SECOND
          // component (the exit bar) needed to learn about a connection it did not initiate: it
          // subscribed on mount, saw no event, and stayed hidden while the user was plainly
          // connected. Emitting here is provider fidelity, not a workaround for the app.
          //
          // Deferred a tick so the caller's promise resolves before listeners run, which is the
          // ordering an extension produces and the one React state updates expect.
          setTimeout(() => emit("accountsChanged", [address]), 0);
          return [address];

        case "eth_chainId":
          if (window.__asmlChainOverride) return window.__asmlChainOverride;
          return await rpc("eth_chainId", []);

        case "wallet_switchEthereumChain": {
          const want = params && params[0] && params[0].chainId;
          const actual = await rpc("eth_chainId", []);
          if (want !== actual) {
            // This headless provider is bound to one RPC, so it cannot genuinely move networks. It
            // reports 4902 (chain not added), which is the branch the app must handle, rather than
            // pretending the switch worked.
            const e = new Error("Unrecognized chain ID.");
            e.code = 4902;
            throw e;
          }
          delete window.__asmlChainOverride;
          emit("chainChanged", actual);
          return null;
        }

        case "wallet_addEthereumChain":
          // Accepting is honest here: the chain being added IS the chain this provider talks to.
          delete window.__asmlChainOverride;
          return null;

        case "eth_sendTransaction": {
          // Forwarded to the TEST-ONLY signer (scripts/test_signer.py), which shells out to `cast`.
          // The key never enters this page, so ADR-008's decision that signing lives in cast is
          // preserved rather than worked around: reimplementing secp256k1 here would be a second
          // signing implementation to keep correct AND would put a key in the browser.
          //
          // The transaction is real. It lands in a real block with a real hash.
          const tx = (params && params[0]) || {};
          const res = await fetch(window.__asmlSignerUrl || "http://localhost:4177/", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ to: tx.to, data: tx.data || "0x", value: tx.value || "0x0" }),
          });
          const body = await res.json();
          if (!res.ok || body.error) {
            const e = new Error(body.error || "signer refused");
            // -32000 is the generic provider error a wallet returns for a failed send, so the app
            // takes its ordinary failure path rather than a special one.
            e.code = -32000;
            throw e;
          }
          if (body.status === "0x0") {
            const e = new Error("transaction reverted on chain");
            e.code = -32000;
            e.data = { transactionHash: body.transactionHash };
            throw e;
          }
          return body.transactionHash;
        }

        case "eth_signTypedData_v4": {
          // Real EIP-712 signing, delegated to the test signer, which shells out to `cast wallet
          // sign`. The key never enters this page: same arrangement as eth_sendTransaction, and the
          // same reason (ADR-008).
          //
          // params is [address, jsonTypedData] per the spec.
          const typedData = (params && params[1]) || "{}";
          const res = await fetch(
            (window.__asmlSignerUrl || "http://localhost:4177/") + "sign-typed",
            {
              method: "POST",
              headers: { "content-type": "application/json" },
              body: typeof typedData === "string" ? typedData : JSON.stringify(typedData),
            },
          );
          const body = await res.json();
          if (!res.ok || body.error) {
            const e = new Error(body.error || "signer refused to sign");
            e.code = -32000;
            throw e;
          }
          return body.signature;
        }

        case "personal_sign":
          // Still unimplemented, and still not stubbed: nothing in this app uses it, and a fake
          // signature would make a broken path look healthy.
          throw Object.assign(new Error("personal_sign is not implemented by the test provider"), {
            code: -32601,
          });

        default:
          return await rpc(method, params);
      }
    },

    on(event, handler) {
      (listeners[event] = listeners[event] || []).push(handler);
    },
    removeListener(event, handler) {
      listeners[event] = (listeners[event] || []).filter((h) => h !== handler);
    },
  };

  function emit(event, payload) {
    (listeners[event] || []).forEach((h) => {
      try {
        h(payload);
      } catch {
        /* a listener throwing must not break the provider */
      }
    });
  }

  window.ethereum = provider;
  window.__asmlEmit = emit;
  return provider.providerLabel;
})(ASML_ADDRESS, ASML_RPC);
