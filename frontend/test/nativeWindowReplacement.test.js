import test from 'node:test';
import assert from 'node:assert/strict';
import { nativeReplacementSession, nativeSessionForLaunch } from '../src/services/nativeWindowContract.js';

function session(overrides = {}) {
  return {
    sessionId: 'window-a',
    title: 'App',
    processId: 4242,
    launchProcessId: 4242,
    minimized: false,
    maximized: false,
    contained: false,
    containmentMode: 'hidden-quarantine',
    visible: false,
    bounds: { x: 0, y: 0, width: 800, height: 600 },
    ...overrides
  };
}

test('substituição de HWND aceita descendente diferente dentro do mesmo launch Job', () => {
  const replacement = session({ sessionId: 'window-b', processId: 5252, launchProcessId: 4242 });
  assert.equal(nativeReplacementSession([replacement], 'window-a', 4242), replacement);
});

test('substituição de HWND aceita recriação no mesmo processo do mesmo launch Job', () => {
  const replacement = session({ sessionId: 'window-b' });
  assert.equal(nativeReplacementSession([replacement], 'window-a', 4242), replacement);
});

test('substituição de HWND rejeita candidato de outro launch Job mesmo com PID de janela coincidente', () => {
  const replacement = session({ sessionId: 'window-b', processId: 4242, launchProcessId: 6262 });
  assert.equal(nativeReplacementSession([replacement], 'window-a', 4242), null);
});

test('substituição de HWND rejeita candidato de outro launch Job', () => {
  const replacement = session({ sessionId: 'window-b', processId: 5252, launchProcessId: 6262 });
  assert.equal(nativeReplacementSession([replacement], 'window-a', 4242), null);
});

test('substituição de HWND rejeita sessão já contida', () => {
  const replacement = session({
    sessionId: 'window-b',
    processId: 5252,
    contained: true,
    containmentMode: 'captured-surface',
    visible: true
  });
  assert.equal(nativeReplacementSession([replacement], 'window-a', 4242), null);
});

test('substituição de HWND falha fechado quando existem múltiplos candidatos do mesmo launch Job', () => {
  const first = session({ sessionId: 'window-b', processId: 5252 });
  const second = session({ sessionId: 'window-c', processId: 5353 });
  assert.equal(nativeReplacementSession([first, second], 'window-a', 4242), null);
});

test('Host legado continua aceitando fallback pelo PID quando launchProcessId não existe', () => {
  const replacement = session({ sessionId: 'window-b', launchProcessId: undefined });
  assert.equal(nativeReplacementSession([replacement], 'window-a', 4242), replacement);
});

test('resolução inicial encontra descendente pelo launchProcessId', () => {
  const child = session({ sessionId: 'window-child', processId: 5252, launchProcessId: 4242 });
  assert.equal(nativeSessionForLaunch([child], { pid: 4242 }), child);
});

test('resolução inicial não usa PID físico quando Host informa outro launch Job', () => {
  const foreign = session({ sessionId: 'window-foreign', processId: 4242, launchProcessId: 6262 });
  assert.equal(nativeSessionForLaunch([foreign], { pid: 4242 }), null);
});

test('resolução inicial mantém fallback por PID para Host legado sem launchProcessId', () => {
  const legacy = session({ sessionId: 'window-legacy', launchProcessId: undefined });
  assert.equal(nativeSessionForLaunch([legacy], { pid: 4242 }), legacy);
});

test('resolução inicial falha fechado quando o launch Job possui múltiplas janelas candidatas', () => {
  const first = session({ sessionId: 'window-first', processId: 5252, launchProcessId: 4242 });
  const second = session({ sessionId: 'window-second', processId: 5353, launchProcessId: 4242 });
  assert.equal(nativeSessionForLaunch([first, second], { pid: 4242 }), null);
});

test('resolução inicial de Host legado falha fechado quando o mesmo PID possui múltiplas janelas', () => {
  const first = session({ sessionId: 'window-first', launchProcessId: undefined });
  const second = session({ sessionId: 'window-second', launchProcessId: undefined });
  assert.equal(nativeSessionForLaunch([first, second], { pid: 4242 }), null);
});

test('sessionId opaco retornado pelo Host vence ambiguidade do mesmo launch Job', () => {
  const first = session({ sessionId: 'window-first', processId: 5252, launchProcessId: 4242 });
  const exact = session({ sessionId: 'window-exact', processId: 5353, launchProcessId: 4242 });
  assert.equal(nativeSessionForLaunch([first, exact], { pid: 4242, sessionId: 'window-exact' }), exact);
});
