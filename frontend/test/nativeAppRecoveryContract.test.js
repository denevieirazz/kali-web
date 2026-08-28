import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../src/apps/NativeAppWindow/NativeAppWindow.tsx', import.meta.url), 'utf8');

test('shell web não relança aplicativo Windows para recuperar troca de HWND', () => {
  assert.doesNotMatch(source, /MAX_NATIVE_RECOVERY_ATTEMPTS/);
  assert.doesNotMatch(source, /RECOVERY_DELAYS_MS/);
  assert.doesNotMatch(source, /requestRecovery/);
  assert.doesNotMatch(source, /recoveryEpoch/);
  assert.match(source, /session identity belongs to the Host\/Job/);
});

test('shell web envia somente geometria, visibilidade e foco para a superfície nativa', () => {
  assert.match(source, /data-renderer="native-windows"/);
  assert.match(source, /nativeHostBridge\.attachSession/);
  assert.match(source, /nativeHostBridge\.layoutSession/);
  assert.match(source, /nativeHostBridge\.operate\('focus'/);
  assert.match(source, /Windows renderiza o aplicativo/);
});

test('sessão nativa encerrada fecha a moldura sem relançar o Job', () => {
  assert.match(source, /if \(!current\) \{[\s\S]*closeWindow\(windowId\);/);
  assert.doesNotMatch(source, /Recuperando aplicativo do Windows/);
});
