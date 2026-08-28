import test from 'node:test';
import assert from 'node:assert/strict';
import { buildExternalInstanceProbeCommand } from '../src/apps/windowsExternalInstanceGuard.js';

test('probe de singleton consulta somente processos existentes e devolve JSON', () => {
  const command = buildExternalInstanceProbeCommand();
  assert.match(command, /CLOUDOS_EXTERNAL_INSTANCE_TARGET/);
  assert.match(command, /Get-Process -Name \$name/);
  assert.match(command, /candidate\.Path/);
  assert.match(command, /ConvertTo-Json -Compress/);
  assert.doesNotMatch(command, /Start-Process|Invoke-Expression|cmd\.exe|explorer\.exe/i);
});

test('probe não depende de try-finally fragmentado pelo join de PowerShell', () => {
  const command = buildExternalInstanceProbeCommand();
  assert.doesNotMatch(command, /finally/i);
  assert.match(command, /try \{ \$candidatePath = \[string\]\$candidate\.Path \} catch \{\}/);
});
