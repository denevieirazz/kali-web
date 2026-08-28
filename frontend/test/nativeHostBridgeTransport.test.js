import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const bridgePath = path.resolve(here, '../src/services/nativeHostBridge.ts');
const hostPolicyPath = path.resolve(here, '../../desktop/CloudOS.Host/Native/NativeLaunchContainmentPolicy.cs');
const source = fs.readFileSync(bridgePath, 'utf8');
const hostPolicySource = fs.readFileSync(hostPolicyPath, 'utf8');

function methodBody(name) {
  const start = source.indexOf(`async ${name}(`);
  assert.notStrictEqual(start, -1, `nativeHostBridge.${name} must remain async`);
  const next = source.indexOf('\n  async ', start + 1);
  return source.slice(start, next === -1 ? source.length : next);
}

function numericLiteral(value) {
  return Number(String(value).replaceAll('_', ''));
}

test('all native session operations establish the WebView host handshake first', () => {
  for (const method of ['launchApp', 'listSessions', 'operate', 'attachSession', 'layoutSession']) {
    const body = methodBody(method);
    assert.match(body, /await this\.requireConnection\(\)/, `${method} must handshake before sending a protected native request`);
  }
  assert.doesNotMatch(source, /detachSession|native\.session\.detach/);
});

test('native capture attach transport deadline stays beyond Host pending-attach containment', () => {
  const body = methodBody('attachSession');
  const attachTimeoutMatch = body.match(/'native\.session\.attach',[\s\S]*?\{ sessionId, bounds, visible \},[\s\S]*?([0-9][0-9_]*)\s*\)/s);
  const pendingTimeoutMatch = hostPolicySource.match(/PendingAttachTimeoutMilliseconds\s*=\s*([0-9][0-9_]*)/);
  assert.ok(attachTimeoutMatch, 'attachSession must pass an explicit transport timeout');
  assert.ok(pendingTimeoutMatch, 'Host pending-attach timeout must remain explicit');
  const attachTimeout = numericLiteral(attachTimeoutMatch[1]);
  const pendingTimeout = numericLiteral(pendingTimeoutMatch[1]);
  assert.ok(attachTimeout > pendingTimeout, `transport timeout ${attachTimeout} must exceed Host containment timeout ${pendingTimeout}`);
  assert.ok(attachTimeout <= 30_000, 'native attach must remain bounded');
});

test('bridge request removes pending state when postMessage fails synchronously', () => {
  assert.match(source, /try \{\s*this\.transport!\.postMessage\(/s);
  assert.match(source, /catch \(postError\) \{\s*window\.clearTimeout\(timer\);\s*this\.pending\.delete\(id\);/s);
  assert.match(source, /NATIVE_TRANSPORT_FAILED/);
});

test('one native sessions listener cannot break or mutate delivery to the remaining windows', () => {
  assert.match(source, /this\.lastSessions = snapshotSessions\(sessions\);/);
  assert.match(source, /for \(const listener of this\.eventListeners\) \{\s*try \{\s*listener\(snapshotSessions\(sessions\)\);\s*\} catch \{/s);
  assert.doesNotMatch(source, /listener\(sessions\);/);
});
