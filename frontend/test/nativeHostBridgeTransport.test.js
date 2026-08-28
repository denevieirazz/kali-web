import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const bridgePath = path.resolve(here, '../src/services/nativeHostBridge.ts');
const source = fs.readFileSync(bridgePath, 'utf8');

function methodBody(name) {
  const start = source.indexOf(`async ${name}(`);
  assert.notStrictEqual(start, -1, `nativeHostBridge.${name} must remain async`);
  const next = source.indexOf('\n  async ', start + 1);
  return source.slice(start, next === -1 ? source.length : next);
}

test('all native session operations establish the WebView host handshake first', () => {
  for (const method of ['launchApp', 'listSessions', 'operate', 'attachSession', 'layoutSession']) {
    const body = methodBody(method);
    assert.match(body, /await this\.requireConnection\(\)/, `${method} must handshake before sending a protected native request`);
  }
  assert.doesNotMatch(source, /detachSession|native\.session\.detach/);
});

test('native capture attach has response margin beyond Host pending-attach containment', () => {
  const body = methodBody('attachSession');
  assert.match(body, /'native\.session\.attach',[\s\S]*?\{ sessionId, bounds, visible \},[\s\S]*?20_000/s);
  assert.match(source, /private request<T = unknown>\(method: NativeRequestMethod, params: Record<string, unknown>, timeoutMs = 10_000\)/);
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
