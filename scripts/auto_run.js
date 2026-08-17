/**
 * Cold-run driver, task 10.2. Injected into the BUILD ARTIFACT only, during a timing run.
 *
 * It starts the flow from the first rendered frame, so the first_paint to activated interval
 * measures the product rather than how long the tester took to reach for the mouse. The first
 * attempt at this task drove the flow from a console command issued 15 seconds after load, and that
 * 15 seconds landed inside the measurement.
 *
 * EVERY RUN THIS PRODUCES IS SCRIPTED, and the evidence says so. A script does not hesitate and a
 * person does, so this measures the SYSTEM's floor: the time when the decision cost is zero. It is a
 * lower bound on a human number and is never published as one. What it is good for is regression
 * detection, because it repeats to the millisecond.
 *
 * Gated on a sessionStorage flag so a normal visitor never triggers it.
 */
(function () {
  if (sessionStorage.getItem("asmlAutoRun") !== "1") return;

  var wait = function (ms) {
    return new Promise(function (r) {
      setTimeout(r, ms);
    });
  };

  window.__asmlSignerUrl = "http://" + location.hostname + ":4177/";
  window.__asmlAutoResult = "running";

  (async function () {
    var t0 = performance.now();

    var btn = null;
    for (var i = 0; i < 60; i++) {
      btn = document.querySelector('[data-testid="wallet-connect"]');
      if (btn) break;
      await wait(100);
    }
    if (!btn) {
      window.__asmlAutoResult = { error: "no connect button appeared" };
      return;
    }
    btn.click();

    var dep = null;
    for (var j = 0; j < 60; j++) {
      await wait(500);
      dep = document.querySelector('[data-testid="deposit-activate"]');
      if (dep && !dep.disabled) break;
    }
    if (!dep || dep.disabled) {
      window.__asmlAutoResult = { error: "the activate control never became enabled" };
      return;
    }
    dep.click();

    for (var k = 0; k < 90; k++) {
      await wait(1000);
      if (
        document.querySelector('[data-testid="last-tx"]') ||
        document.querySelector('[data-testid="tx-error"]')
      ) {
        break;
      }
    }

    window.__asmlAutoResult = {
      driverMs: Math.round(performance.now() - t0),
      marks: window.__asmlFlowMarks ? window.__asmlFlowMarks() : null,
      tx: (document.querySelector('[data-testid="last-tx"]') || {}).textContent || null,
      err: (document.querySelector('[data-testid="tx-error"]') || {}).innerText || null,
    };
    sessionStorage.removeItem("asmlAutoRun");
  })();
})();
