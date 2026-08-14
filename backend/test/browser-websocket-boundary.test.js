import test from 'node:test';
import assert from 'node:assert/strict';
import { isAllowedWebSocketOrigin } from '../src/terminal/websocket.js';

function requestForPort(port) {
  return { socket: { localPort: port } };
}

test('browser externo em outra origem loopback não é aceito no WebSocket do terminal', () => {
  const request = requestForPort(43127);
  assert.equal(isAllowedWebSocketOrigin('http://127.0.0.1:43128', request), false);
  assert.equal(isAllowedWebSocketOrigin('http://localhost:43127', request), false);
  assert.equal(isAllowedWebSocketOrigin('https://example.com', request), false);
  assert.equal(isAllowedWebSocketOrigin('null', request), false);
});

test('somente a origem HTTP 127.0.0.1 da própria porta é aceita pelo fallback local', () => {
  const request = requestForPort(43127);
  assert.equal(isAllowedWebSocketOrigin('http://127.0.0.1:43127', request), true);
  assert.equal(isAllowedWebSocketOrigin('https://127.0.0.1:43127', request), false);
  assert.equal(isAllowedWebSocketOrigin('http://127.0.0.1:43126', request), false);
});

test('clientes sem Origin ainda dependem da autenticação JWT posterior', () => {
  const request = requestForPort(43127);
  assert.equal(isAllowedWebSocketOrigin(undefined, request), true);
});
