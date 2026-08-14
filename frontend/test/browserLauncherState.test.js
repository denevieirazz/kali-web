import test from 'node:test';
import assert from 'node:assert/strict';
import {
  browserLauncherFailure,
  browserLauncherOpening,
  browserLauncherSuccess,
} from '../src/apps/Browser/browserLauncherState.js';

test('launcher inicia em loading sem solicitar fechamento', () => {
  const state = browserLauncherOpening();
  assert.equal(state.status, 'opening');
  assert.equal(state.shouldClose, false);
  assert.equal(state.code, null);
});

test('launcher sai de loading e fecha somente após janela WPF visível', () => {
  const state = browserLauncherSuccess({ opened: true, reused: false, windowVisible: true });
  assert.equal(state.status, 'success');
  assert.equal(state.shouldClose, true);
});

test('launcher não fecha quando Host responde sem janela visível', () => {
  const state = browserLauncherSuccess({ opened: true, reused: false, windowVisible: false });
  assert.equal(state.status, 'error');
  assert.equal(state.shouldClose, false);
  assert.equal(state.code, 'BROWSER_WINDOW_NOT_VISIBLE');
});

test('launcher sai de loading em erro e preserva código e mensagem nativos', () => {
  const error = Object.assign(new Error('Falha sanitizada do Host.'), { code: 'BROWSER_WINDOW_CREATE_FAILED' });
  const state = browserLauncherFailure(error);
  assert.equal(state.status, 'error');
  assert.equal(state.shouldClose, false);
  assert.equal(state.code, 'BROWSER_WINDOW_CREATE_FAILED');
  assert.equal(state.message, 'Falha sanitizada do Host.');
});
