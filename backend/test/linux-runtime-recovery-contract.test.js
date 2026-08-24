import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../..');
const read = (...parts) => fs.readFileSync(path.join(repoRoot, ...parts), 'utf8');

test('Linux runtime recovery: launch retry is idempotent per CloudOS window and cleans sessions', () => {
  const frontend = read('frontend', 'src', 'apps', 'LinuxAppWindow', 'LinuxAppWindow.tsx');
  const routes = read('backend', 'src', 'linuxRuntime', 'routes.js');
  const runtime = read('backend', 'src', 'linuxRuntime', 'xpraPoc.js');

  assert.match(frontend, /reuseExisting:\s*true/);
  assert.match(frontend, /stopSessionBestEffort/);
  assert.match(frontend, /sessions\/\$\{encodeURIComponent\(sessionId\)\}\/stop/);
  assert.match(frontend, /sessions\/\$\{encodeURIComponent\(sessionId\)\}\/health/);
  assert.match(frontend, /failures\s*>=\s*2/);
  assert.match(frontend, /setRecoveryGeneration\(value => value \+ 1\)/);
  assert.doesNotMatch(frontend, /targetFilePath,\s*reconnectAttempt/);

  assert.match(routes, /reuseExisting:\s*req\.body\?\.reuseExisting === true/);
  assert.match(runtime, /reuseExisting = false/);
  assert.match(runtime, /s\.ownerId === owner[\s\S]*s\.app === appId[\s\S]*requestedFilePath/);
  assert.match(runtime, /existing\.leaseExpiresAt = Date\.now\(\) \+ LEASE_TTL_MS/);
});

test('Linux runtime recovery: backend restart never fabricates an Xpra credential', () => {
  const runtime = read('backend', 'src', 'linuxRuntime', 'xpraPoc.js');
  const start = runtime.indexOf('export async function restoreSessionsFromLedger');
  const end = runtime.indexOf('export async function resolvePocApp');
  const restoreBlock = runtime.slice(start, end);

  assert.ok(start >= 0 && end > start, 'restoreSessionsFromLedger deve existir antes de resolvePocApp');
  assert.doesNotMatch(restoreBlock, /xpraPassword/);
  assert.doesNotMatch(restoreBlock, /sessions\.set/);
  assert.match(restoreBlock, /stopLedgerEntry/);
  assert.match(restoreBlock, /probeWslServer/);
  assert.match(restoreBlock, /probeWindowsTcp/);
  assert.match(restoreBlock, /writeLedgerEntries\(remaining\)/);
});

test('Linux runtime recovery: WSLInterop probe failure remains fail-closed', () => {
  const runtime = read('backend', 'src', 'linuxRuntime', 'xpraPoc.js');
  assert.match(runtime, /code:\s*'WSL_INTEROP_CHECK_FAILED'/);
  assert.match(runtime, /evidence:\s*'CHECK_FAILED'/);
  assert.doesNotMatch(runtime, /WSL_INTEROP_ASSUMED_VALID/);
});

test('Linux runtime allocator isolates DISPLAY state and never removes another session files', () => {
  const runtime = read('backend', 'src', 'linuxRuntime', 'xpraPoc.js');
  const buildStart = runtime.indexOf('export function buildXpraStartCommand');
  const buildEnd = runtime.indexOf('async function execWsl');
  const buildBlock = runtime.slice(buildStart, buildEnd);
  const reserveStart = runtime.indexOf('async function reservePair');
  const reserveEnd = runtime.indexOf('function releasePort');
  const reserveBlock = runtime.slice(reserveStart, reserveEnd);

  assert.ok(buildStart >= 0 && buildEnd > buildStart);
  assert.match(buildBlock, /mount -t tmpfs[^'\"]*\/tmp/);
  assert.match(buildBlock, /mount -t tmpfs[^'\"]*\/run\/xpra/);
  assert.match(buildBlock, /--kill-child=KILL/);
  assert.doesNotMatch(buildBlock, /xpra stop :\$\{display\}/);
  assert.doesNotMatch(buildBlock, /rm -rf[^\n]*\/run\/xpra/);
  assert.doesNotMatch(buildBlock, /rm -f[^\n]*cloudos-\*-poc/);

  assert.ok(reserveStart >= 0 && reserveEnd > reserveStart);
  assert.match(reserveBlock, /probeWslTcpAvailable\(distro, port\)/);
  assert.match(reserveBlock, /if \(win\.ok \|\| !wslPortFree\) continue/);
  assert.doesNotMatch(reserveBlock, /probeWslServer/);
});
