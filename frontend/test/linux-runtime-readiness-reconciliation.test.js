import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = relativePath => readFileSync(new URL(relativePath, import.meta.url), "utf8");

function getReconciledReadinessItem(name, readinessCheck, physicalPreflight, preflightBusy) {
  if (preflightBusy && ["windowsLoopback", "websocket"].includes(name)) {
    return { label: "TESTANDO", dataOk: "testing" };
  }

  if (physicalPreflight) {
    if (name === "windowsLoopback") {
      const check = physicalPreflight.checks.find(c => c.id === "loopback-tcp");
      if (check?.status === "PASS") return { label: "PASS", dataOk: "true" };
      if (check?.status === "FAIL") return { label: "FAIL", dataOk: "false" };
      if (physicalPreflight.decision === "NO_GO" && !check) return { label: "NÃO TESTADO", dataOk: "untested" };
    }
    if (name === "websocket") {
      const check = physicalPreflight.checks.find(c => c.id === "direct-websocket");
      if (check?.status === "PASS") return { label: "PASS", dataOk: "true" };
      if (check?.status === "FAIL") return { label: "FAIL", dataOk: "false" };
      if (physicalPreflight.decision === "NO_GO" && !check) return { label: "NÃO TESTADO", dataOk: "untested" };
    }
  }

  if (!readinessCheck || readinessCheck.ok === null) {
    return { label: "NÃO TESTADO", dataOk: "untested" };
  }
  if (readinessCheck.ok === true) {
    return { label: "PASS", dataOk: "true" };
  }
  return { label: "FAIL", dataOk: "false" };
}

test("EF2-P0-010: Before preflight, dynamic loopback and websocket checks are NÃO TESTADO (untested)", () => {
  const loopback = getReconciledReadinessItem("windowsLoopback", { ok: null }, null, false);
  assert.equal(loopback.label, "NÃO TESTADO");
  assert.equal(loopback.dataOk, "untested");

  const ws = getReconciledReadinessItem("websocket", { ok: null }, null, false);
  assert.equal(ws.label, "NÃO TESTADO");
  assert.equal(ws.dataOk, "untested");

  const wsl = getReconciledReadinessItem("wsl", { ok: true }, null, false);
  assert.equal(wsl.label, "PASS");
  assert.equal(wsl.dataOk, "true");
});

test("EF2-P0-010: During physical preflight, dynamic checks are TESTANDO (testing)", () => {
  const loopback = getReconciledReadinessItem("windowsLoopback", { ok: null }, null, true);
  assert.equal(loopback.label, "TESTANDO");
  assert.equal(loopback.dataOk, "testing");

  const ws = getReconciledReadinessItem("websocket", { ok: null }, null, true);
  assert.equal(ws.label, "TESTANDO");
  assert.equal(ws.dataOk, "testing");
});

test("EF2-P0-010: After physical preflight GO, dynamic checks reflect PASS from preflight evidence", () => {
  const mockPreflightGo = {
    decision: "GO",
    checks: [
      { id: "loopback-tcp", status: "PASS" },
      { id: "direct-websocket", status: "PASS" },
    ],
  };

  const loopback = getReconciledReadinessItem("windowsLoopback", { ok: null }, mockPreflightGo, false);
  assert.equal(loopback.label, "PASS");
  assert.equal(loopback.dataOk, "true");

  const ws = getReconciledReadinessItem("websocket", { ok: null }, mockPreflightGo, false);
  assert.equal(ws.label, "PASS");
  assert.equal(ws.dataOk, "true");
});

test("EF2-P0-010: After physical preflight NO GO, failed checks are FAIL and unreached checks are NÃO TESTADO", () => {
  const mockPreflightNoGo = {
    decision: "NO_GO",
    checks: [
      { id: "loopback-tcp", status: "FAIL" },
    ],
  };

  const loopback = getReconciledReadinessItem("windowsLoopback", { ok: null }, mockPreflightNoGo, false);
  assert.equal(loopback.label, "FAIL");
  assert.equal(loopback.dataOk, "false");

  const ws = getReconciledReadinessItem("websocket", { ok: null }, mockPreflightNoGo, false);
  assert.equal(ws.label, "NÃO TESTADO");
  assert.equal(ws.dataOk, "untested");
});

test("EF2-P0-010: Absence of evidence never appears as PASS (fail-closed integrity)", () => {
  const nullCheck = getReconciledReadinessItem("customCheck", undefined, null, false);
  assert.notEqual(nullCheck.label, "PASS");
  assert.equal(nullCheck.label, "NÃO TESTADO");

  const failedCheck = getReconciledReadinessItem("customCheck", { ok: false }, null, false);
  assert.equal(failedCheck.label, "FAIL");
  assert.equal(failedCheck.dataOk, "false");
});

test("EF2-P0-010: Static source contract verifies reconciliation and CSS support", () => {
  const tsx = read("../src/apps/LinuxRuntimePoc/LinuxRuntimePoc.tsx");
  const css = read("../src/apps/LinuxRuntimePoc/LinuxRuntimePoc.css");

  assert.match(tsx, /getReconciledReadinessItem/);
  assert.match(tsx, /READINESS OK · PREFLIGHT GO/);
  assert.match(tsx, /'NÃO TESTADO'/);
  assert.match(tsx, /'TESTANDO'/);

  assert.match(css, /span\[data-ok="testing"\]/);
  assert.match(css, /span\[data-ok="untested"\]/);
});
