import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = relativePath => readFileSync(new URL(relativePath, import.meta.url), 'utf8');

test('Kali Tool Center does not expose arbitrary command execution endpoints', () => {
  const component = read('../src/apps/KaliToolCenter/KaliToolCenter.tsx');
  assert.doesNotMatch(component, /\/api\/security\/(?:execute|run|command|shell)/i);
  assert.doesNotMatch(component, /(?:\.argv\b|\bargv\s*:|\bexecutablePath\s*:|\bshellCommand\s*:)/);
  assert.match(component, /\/api\/security\/tools/);
  assert.match(component, /cloudos-terminal/);
});

test('GUI launch continues through opaque catalog IDs', () => {
  const component = read('../src/apps/KaliToolCenter/KaliToolCenter.tsx');
  assert.match(component, /\/api\/apps\/\$\{encodeURIComponent\(app\.id\)\}\/launch/);
  assert.doesNotMatch(component, /app\.path|app\.command|app\.executable/);
});

test('Tool Center is registered without replacing one of the 12 pinned apps', () => {
  const registry = read('../src/core/appRegistry.ts');
  const apps = read('../src/core/fs/apps.ts');
  assert.match(registry, /'kali-tool-center'/);
  assert.match(apps, /kali-tool-center\.obx/);

  const browserIndex = apps.indexOf('msedge.obx');
  const kaliIndex = apps.indexOf('kali-tool-center.obx');
  assert.ok(browserIndex >= 0, 'browser manifest must remain registered');
  assert.ok(kaliIndex > browserIndex, 'Kali Tool Center must be registered after the existing pinned browser entry');
});
