import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const wizardPath = path.resolve(here, '../src/components/Setup/SetupWizard.tsx');
const source = fs.readFileSync(wizardPath, 'utf8');

test('OOBE provisioning uses the authenticated fetch stream instead of native EventSource', () => {
  assert.match(source, /import \{ apiClient, streamApiEvents \} from '\.\.\/\.\.\/services\/apiClient';/);
  assert.doesNotMatch(source, /new EventSource\(/);
  assert.match(source, /streamApiEvents<ProvisionEvent>\(streamUrl, \{/);
  assert.match(source, /signal: controller\.signal/);
});

test('OOBE provisioning is cancellable and fails closed if the stream ends without done', () => {
  assert.match(source, /provisioningControllerRef\.current\?\.abort\(\)/);
  assert.match(source, /if \(!completed && !controller\.signal\.aborted\)/);
  assert.match(source, /terminou antes da confirmação de sucesso/);
  assert.match(source, /if \(data\.done === true\) \{\s*finishStep\(\);/s);
});

test('destructive distro unregister has a timeout compatible with real WSL latency', () => {
  const unregister = source.match(/apiClient\('\/api\/linux-runtime\/distros\/unregister',[\s\S]*?\}\);/)?.[0] || '';
  assert.match(unregister, /timeoutMs:\s*60_000/);
});
