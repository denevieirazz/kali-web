import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../src/apps/TaskManager/TaskManager.tsx', import.meta.url), 'utf8');
const client = fs.readFileSync(new URL('../src/apps/TaskManager/linuxSystemCenterClient.ts', import.meta.url), 'utf8');
const model = fs.readFileSync(new URL('../src/apps/TaskManager/linuxSystemCenterModel.js', import.meta.url), 'utf8');

test('existing System Center exposes isolated data origins', () => {
  for (const marker of ["'linux-real'", "'cloudos-virtual'", "'host-windows'", 'data-system-center-source']) {
    assert.match(source, new RegExp(marker.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
});

test('System Center boots on Linux real and binds the selected source to the DOM attribute', () => {
  assert.match(source, /useState<SystemCenterSource>\('linux-real'\)/);
  assert.match(source, /data-system-center-source=\{source\}/);
  assert.match(source, /value=\{source\}/);
});

test('Linux readiness remains visible and loading has an explicit terminal state', () => {
  assert.match(source, /linuxAvailable \? 'WSL Core v2' : 'Linux indisponível'/);
  assert.match(source, /setLinuxLoading\(true\)/);
  assert.match(source, /setLinuxLoading\(false\)/);
  assert.match(source, /role="alert"/);
});

test('Linux polling is completion-driven instead of overlapping interval requests', () => {
  assert.match(source, /await refreshLinux\(\)/);
  assert.match(source, /window\.setTimeout\(\(\) => void poll\(\), LINUX_SYSTEM_CENTER_POLL_MS\)/);
  assert.match(source, /LatestRequestGate/);
  assert.match(source, /gateRef\.current\.dispose/);
  assert.match(source, /request\.current\(\)/);
});

test('process and metrics responses are committed independently', () => {
  assert.match(source, /const processTask = linuxSystemCenterClient\.processes/);
  assert.match(source, /const metricsTask = linuxSystemCenterClient\.metrics/);
  assert.match(source, /setLinuxProcesses\(page\.processes/);
  assert.match(source, /setLinuxMetrics\(metrics\)/);
  assert.match(source, /setLinuxMetricsError/);
  assert.doesNotMatch(source, /const \[page,\s*metrics\]\s*=\s*await Promise\.all/);
});

test('HTTP client normalizes unknown Linux payloads before exposing typed data', () => {
  assert.match(client, /apiClient<unknown>/);
  assert.match(client, /normalizeLinuxStatus/);
  assert.match(client, /normalizeLinuxProcessPage/);
  assert.match(client, /normalizeLinuxMetrics/);
  assert.match(model, /normalizeLinuxProcessInfo/);
  assert.match(model, /normalizeCgroupCapabilities/);
});

test('malformed Linux row is locally contained and cannot replace the whole System Center', () => {
  assert.match(source, /class LinuxProcessRowBoundary extends Component/);
  assert.match(source, /getDerivedStateFromError/);
  assert.match(source, /data-linux-row-error/);
  assert.match(source, /<LinuxProcessRowBoundary/);
});

test('System Center data path does not read a dimensions property', () => {
  for (const scoped of [source, client, model]) assert.doesNotMatch(scoped, /\.dimensions\b/);
});

test('signals require visual confirmation and only explicit supported signals exist', () => {
  assert.match(source, /window\.confirm/);
  for (const signal of ['SIGINT', 'SIGTERM', 'SIGKILL']) assert.match(source, new RegExp(signal));
});

test('cgroup UI distinguishes read-only, available and actually applied', () => {
  assert.match(source, /somente leitura/);
  assert.match(source, /controle real disponível/);
  assert.match(source, /Limite real aplicado/);
  assert.match(source, /result\.assignment/);
});
