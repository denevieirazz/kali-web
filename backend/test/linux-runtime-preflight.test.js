import test from 'node:test';
import assert from 'node:assert/strict';
import { __test } from '../src/linuxRuntime/preflight.js';
import {
  chooseXpraPair,
  displayForPort,
  portForDisplay,
  validateLedgerPair,
} from '../src/linuxRuntime/xpraPairAllocator.js';

test('physical preflight dry run never launches xclock or any child application', () => {
  const command = __test.buildPreflightDryRunCommand({
    display: 149,
    port: 14549,
    runId: 'contract',
  });
  assert.match(command, /xpra seamless :149/);
  assert.match(command, /--bind-tcp=127\.0\.0\.1:14549,auth=allow/);
  assert.match(command, /--html=on/);
  assert.match(command, /--start-new-commands=no/);
  assert.match(command, /unset DISPLAY WAYLAND_DISPLAY PULSE_SERVER/);
  assert.doesNotMatch(command, /--start-child/);
  assert.doesNotMatch(command, /--exit-with-children/);
  assert.doesNotMatch(command, /xclock|xeyes|xterm|gedit|firefox|gimp/i);
  assert.doesNotMatch(command, /0\.0\.0\.0/);
});

test('shared allocator chooses the first matching free DISPLAY and localhost port pair', () => {
  const pair = chooseXpraPair({
    occupiedDisplays: [100, 149],
    freePorts: [14500, 14501, 14548, 14549],
  });
  assert.deepEqual(pair, { display: 101, port: 14501 });
  assert.equal(chooseXpraPair({
    occupiedDisplays: Array.from({ length: 50 }, (_, i) => 100 + i),
    freePorts: [14500, 14549],
  }), null);
});

test('physical preflight consumes the exact shared allocator decision used by runtime', () => {
  const displayScan = { occupied: [100, 101, 149] };
  const portScan = { free: [14500, 14501, 14502, 14549] };
  const shared = chooseXpraPair({
    occupiedDisplays: displayScan.occupied,
    freePorts: portScan.free,
  });
  assert.deepEqual(shared, { display: 102, port: 14502 });
  assert.deepEqual(__test.choosePair(displayScan, portScan), shared);
});

test('DISPLAY and port mapping is bijective across the complete POC1 range', () => {
  for (let port = 14500; port <= 14549; port += 1) {
    const display = displayForPort(port);
    assert.equal(display, 100 + (port - 14500));
    assert.equal(portForDisplay(display), port);
  }
  assert.equal(displayForPort(14499), null);
  assert.equal(displayForPort(14550), null);
  assert.equal(portForDisplay(99), null);
  assert.equal(portForDisplay(150), null);
});

test('ledger accepts only canonical DISPLAY/port pairs', () => {
  assert.deepEqual(validateLedgerPair({ display: 100, port: 14500 }), {
    ok: true,
    code: 'XPRA_LEDGER_PAIR_VALID',
    evidence: 'display=:100; port=14500',
  });
  const invalid = validateLedgerPair({ display: 149, port: 14500 });
  assert.equal(invalid.ok, false);
  assert.equal(invalid.code, 'XPRA_LEDGER_PAIR_INVALID');
  assert.match(invalid.evidence, /display=:149; port=14500/);
});

test('physical preflight requires the same Xpra CLI features needed by the real POC1', () => {
  assert.deepEqual(__test.requiredXpraFlags, [
    '--start-child',
    '--exit-with-children',
    '--session-name',
    '--bind-tcp',
    '--html',
    '--start-new-commands',
    '--bind',
  ]);
});

test('boundary summary marks downstream layers not reached after an exact upstream failure', () => {
  const summary = __test.boundarySummary({
    phase: 'complete',
    checks: [{
      id: 'wsl',
      layer: 'WSL',
      status: 'FAIL',
      code: 'WSL_NOT_FOUND',
      component: 'wsl.exe',
      cause: 'missing',
      evidence: 'C:\\Windows\\System32\\wsl.exe',
    }],
  });
  assert.equal(summary.WSL.status, 'FAIL');
  assert.equal(summary.WSL.code, 'WSL_NOT_FOUND');
  assert.equal(summary.DISTRO.status, 'FAIL');
  assert.equal(summary.DISTRO.code, 'DISTRO_NOT_REACHED');
  assert.match(summary.DISTRO.evidence, /blockedBy=WSL/);
});

test('GO is impossible when any preflight check failed', () => {
  assert.equal(__test.decisionFor({ checks: [{ status: 'PASS' }, { status: 'WARN' }] }), 'GO');
  assert.equal(__test.decisionFor({ checks: [{ status: 'PASS' }, { status: 'FAIL' }] }), 'NO_GO');
});
