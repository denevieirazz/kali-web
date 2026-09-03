import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { publicNetworkAssessmentPresets } from '../src/security/networkAssessment.js';

const source = readFileSync(new URL('../src/security/networkAssessment.js', import.meta.url), 'utf8');

const EXPECTED = [
  'discover', 'fullProfile', 'services', 'commonPorts', 'webSurface', 'remoteAccess',
  'windowsServices', 'fileSharing', 'databases', 'infrastructure', 'printersIot',
  'development', 'mailServices',
];

test('guided network catalog exposes the reviewed one-click presets', () => {
  const presets = publicNetworkAssessmentPresets();
  const ids = new Set(presets.map(item => item.id));
  for (const id of EXPECTED) assert.equal(ids.has(id), true, `missing ${id}`);

  const full = presets.find(item => item.id === 'fullProfile');
  assert.ok(full);
  assert.equal(full.requiresSingleHost, true);
  assert.equal(full.scope, 'single-private-host');
  assert.ok(Array.isArray(full.ports));
  assert.ok(full.ports.length >= 40 && full.ports.length <= 64);
  assert.equal(new Set(full.ports).size, full.ports.length);
  assert.ok(full.ports.every(port => Number.isInteger(port) && port >= 1 && port <= 65535));
});

test('all targeted one-click service checks remain single-host only', () => {
  const presets = publicNetworkAssessmentPresets();
  for (const preset of presets) {
    if (preset.id === 'discover') continue;
    assert.equal(preset.requiresSingleHost, true, `${preset.id} must reject CIDR ranges`);
    assert.equal(preset.scope, 'single-private-host');
  }
});

test('guided presets stay bounded and do not add exploit or credential automation', () => {
  assert.match(source, /'-sT'/);
  assert.match(source, /'-sV'/);
  assert.match(source, /'--version-light'/);
  assert.match(source, /'--max-retries'/);
  assert.doesNotMatch(source, /['"]--script(?:-args)?['"]/);
  assert.doesNotMatch(source, /['"]-A['"]/);
  assert.doesNotMatch(source, /['"]-O['"]/);
  assert.doesNotMatch(source, /['"]-sS['"]/);
  assert.doesNotMatch(source, /brute|password|credential|exploit/i);
});
