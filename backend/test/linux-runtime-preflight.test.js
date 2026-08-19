import test from 'node:test';
import assert from 'node:assert/strict';
import { __test } from '../src/linuxRuntime/preflight.js';

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

test('physical preflight chooses only a matching free display and localhost port pair', () => {
  const pair = __test.choosePair(
    { occupied: [149, 148] },
    { free: [14500, 14547, 14548, 14549] },
  );
  assert.deepEqual(pair, { display: 147, port: 14547 });
  assert.equal(__test.choosePair({ occupied: Array.from({ length: 50 }, (_, i) => 100 + i) }, { free: [14500] }), null);
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
