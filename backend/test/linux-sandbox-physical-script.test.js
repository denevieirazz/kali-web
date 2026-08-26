import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const scriptPath = path.resolve(here, '../../scripts/audit-linux-sandbox.ps1');

test('physical Linux sandbox collector stays evidence-only and reads the real Xpra mount namespace', () => {
  const source = fs.readFileSync(scriptPath, 'utf8');
  assert.match(source, /cloudos-linux-runtime-poc1-sessions\.json/);
  assert.match(source, /wsl\.exe --system -u root -- cat \$mountInfoPath/);
  assert.match(source, /\/proc\/\$XpraPid\/mountinfo/);
  assert.match(source, /rootfs-readonly/);
  assert.match(source, /windows-mounts-hidden/);
  assert.match(source, /real-wsl-home-hidden/);
  assert.match(source, /contained-home-writable/);
  assert.match(source, /nosymfollow/);
  assert.match(source, /sandbox-report\.json/);
  assert.doesNotMatch(source, /Invoke-Expression|\biex\b|Start-Process|cmd\.exe|powershell\.exe/i);
});

test('physical Linux sandbox collector parses with PowerShell 7 on Windows CI', { skip: process.platform !== 'win32' }, () => {
  const parser = [
    '$tokens = $null',
    '$errors = $null',
    '[System.Management.Automation.Language.Parser]::ParseFile($env:CLOUDOS_SCRIPT_UNDER_TEST, [ref]$tokens, [ref]$errors) | Out-Null',
    'if ($errors.Count -gt 0) { $errors | ForEach-Object { [Console]::Error.WriteLine($_.Message) }; exit 1 }',
  ].join('; ');

  const result = spawnSync('pwsh.exe', ['-NoProfile', '-NonInteractive', '-Command', parser], {
    encoding: 'utf8',
    env: { ...process.env, CLOUDOS_SCRIPT_UNDER_TEST: scriptPath },
    timeout: 15_000,
  });

  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.status, 0, `${result.stdout || ''}\n${result.stderr || ''}`.trim());
});
