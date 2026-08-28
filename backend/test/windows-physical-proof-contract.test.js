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
