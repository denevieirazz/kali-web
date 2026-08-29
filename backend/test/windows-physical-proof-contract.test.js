import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '../..');
const proofScript = fs.readFileSync(
  path.join(repoRoot, 'scripts/run-windows-contained-runtime-physical-proof.ps1'),
  'utf8'
);
const collectorScript = fs.readFileSync(
  path.join(repoRoot, 'scripts/collect-windows-native-containment-evidence.ps1'),
  'utf8'
);

const automaticHostVariable = /(^|[^A-Za-z0-9_])\$host(?![A-Za-z0-9_])/im;

test('Windows physical proof scripts never shadow the PowerShell automatic $Host variable', () => {
  assert.doesNotMatch(proofScript, automaticHostVariable);
  assert.doesNotMatch(collectorScript, automaticHostVariable);
  assert.match(proofScript, /\$cloudOsHostProcess\s*=\s*Resolve-HostProcess/);
  assert.match(collectorScript, /\$cloudOsHostProcess\s*=\s*Get-Process\s+-Id\s+\$HostProcessId/);
});

test('EnumWindows diagnostics preserve native error information', () => {
  for (const source of [proofScript, collectorScript]) {
    assert.match(source, /DllImport\("user32\.dll", SetLastError = true\)/);
    assert.match(source, /Marshal\.GetLastWin32Error\(\)/);
    assert.match(source, /EnumWindows failed; nativeError=/);
  }
});

test('Absent evidence does not require desktop enumeration once every target PID is gone', () => {
  assert.match(collectorScript, /\$existingProcessCount\s*=\s*@\(\$processEvidence\s*\|\s*Where-Object Exists\)\.Count/);
  assert.match(
    collectorScript,
    /\$nativeWindows\s*=\s*if\s*\(\$ExpectedState\s+-eq\s+'Absent'\s+-and\s+\$existingProcessCount\s+-eq\s+0\)\s*\{\s*@\(\)\s*\}\s*else\s*\{[\s\S]*?CloudOSNativeContainmentEvidence\]::Enumerate/
  );
  assert.match(collectorScript, /Add-Assertion 'process\.target-absent-all'/);
  assert.match(collectorScript, /Add-Assertion 'hwnd\.target-zero'/);
});


test('physical proof reproduces the resize then reopen white-surface regression sequence', () => {
  assert.match(proofScript, /MoveResize1\s*=\s*\$null/);
  assert.match(proofScript, /mova e redimensione a janela interna/);
  assert.match(proofScript, /Read-ManualObservation -Stage 'move-resize1'/);
  assert.match(proofScript, /WhiteOrBlankSurfaceObserved/);
  assert.match(proofScript, /open2-after-resize-reopen/);
  assert.match(proofScript, /superfície branca\/vazia/);
});

test('physical proof makes dual-instance behavior explicit and fail closed', () => {
  assert.match(proofScript, /ValidateSet\('Skip', 'Supported', 'FailClosed'\)/);
  assert.match(proofScript, /DualInstanceExpectation/);
  assert.match(proofScript, /A segunda instância esperada não criou um novo HWND contido/);
  assert.match(proofScript, /O modo FailClosed criou\/adotou um novo HWND/);
  assert.match(proofScript, /FirstInstanceProcessIds/);
});

test('physical proof can verify unique per-launch Chromium profile tokens', () => {
  assert.match(proofScript, /RequireDistinctChromiumProfiles/);
  assert.match(proofScript, /--user-data-dir=/);
  assert.match(proofScript, /\[a-f0-9\]\{32\}/i);
  assert.match(proofScript, /Assert-And-RegisterChromiumProfiles/);
  assert.match(proofScript, /O perfil Chromium foi reutilizado entre launches/);
});

test('physical proof captures sanitized Host diagnostics and bounded reopen stress', () => {
  assert.match(proofScript, /ReopenStressCycles/);
  assert.match(proofScript, /ValidateRange\(0, 5\)/);
  assert.match(proofScript, /Save-DiagnosticDelta/);
  assert.match(proofScript, /browser-\$\(\[DateTime\]::UtcNow\.ToString\('yyyyMMdd'\)\)\.log/);
  assert.match(proofScript, /StressCycles \+=/);
});
