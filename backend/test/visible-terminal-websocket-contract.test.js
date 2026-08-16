import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const source = fs.readFileSync(path.resolve(here, '../src/terminal/websocket.js'), 'utf8');

test('WebSocket do Terminal mantém autenticação e rejeita start arbitrário', () => {
  assert.match(source, /verifySessionToken\(protocol\)/);
  assert.match(source, /msg\.executable \|\| msg\.args \|\| msg\.cwd \|\| msg\.env \|\| msg\.command/);
  assert.match(source, /ws\.close\(1008/);
});

test('modo WSL Core e fallback legado são reportados explicitamente', () => {
  assert.match(source, /backendMode = 'wsl-core-v2'/);
  assert.match(source, /type: 'backend', mode: backendMode, protocol: coreSession\.protocol, protection: coreSession\.protection/);
  assert.match(source, /wslCoreTerminalFallbackEnabled\(process\.env\)/);
  assert.match(source, /backendMode = 'legacy-pty'/);
  assert.match(source, /fallback legado explícito/);
});

test('lifecycle backend cobre input resize signal close disconnect e cleanup', () => {
  for (const token of ["msg.type === 'input'", "msg.type === 'resize'", "msg.type === 'signal'", "msg.type === 'close'", "ws.on('close'", "ws.on('error'", 'await activeCore.close()']) {
    assert.ok(source.includes(token), `missing lifecycle token: ${token}`);
  }
  assert.match(source, /\['interrupt', 'terminate', 'hangup'\]/);
});

test('fallback desligado é fail-closed', () => {
  assert.match(source, /if \(!wslCoreTerminalFallbackEnabled\(process\.env\)\)/);
  assert.match(source, /ws\.close\(1011, 'WSL Core falhou'\)/);
});
