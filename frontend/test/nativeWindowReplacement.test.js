import test from 'node:test';
import assert from 'node:assert/strict';
import { nativeReplacementSession } from '../src/services/nativeWindowContract.js';

function session(overrides = {}) {
  return {
    sessionId: 'window-a',
    title: 'App',
    processId: 4242,
    minimized: false,
    maximized: false,
    contained: false,
    containmentMode: 'hidden-quarantine',
    visible: false,
    bounds: { x: 0, y: 0, width: 800, height: 600 },
    ...overrides
  };
}

test('substituição de HWND aceita somente uma sessão em quarentena do mesmo PID', () => {
  const replacement = session({ sessionId: 'window-b' });
  assert.equal(nativeReplacementSession([replacement], 'window-a', 4242), replacement);
});

test('substituição de HWND rejeita candidato de outro processo', () => {
  const replacement = session({ sessionId: 'window-b', processId: 5252 });
  assert.equal(nativeReplacementSession([replacement], 'window-a', 4242), null);
});

test('substituição de HWND rejeita sessão já contida', () => {
  const replacement = session({
    sessionId: 'window-b',
    contained: true,
    containmentMode: 'captured-surface',
    visible: true
  });
  assert.equal(nativeReplacementSession([replacement], 'window-a', 4242), null);
});

test('substituição de HWND falha fechado quando existem múltiplos candidatos do mesmo PID', () => {
  const first = session({ sessionId: 'window-b' });
  const second = session({ sessionId: 'window-c' });
  assert.equal(nativeReplacementSession([first, second], 'window-a', 4242), null);
});
