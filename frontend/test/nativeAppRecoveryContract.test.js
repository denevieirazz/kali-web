import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../src/apps/NativeAppWindow/NativeAppWindow.tsx', import.meta.url), 'utf8');

test('janela nativa recupera falhas transitórias sem fechar imediatamente o shell', () => {
  assert.match(source, /MAX_NATIVE_RECOVERY_ATTEMPTS = 3/);
  assert.match(source, /RECOVERABLE_NATIVE_ERRORS/);
  assert.match(source, /requestRecovery/);
  assert.match(source, /Recuperando aplicativo do Windows/);
  assert.match(source, /stableFor < NATIVE_STABLE_SESSION_MS/);
});

test('sessão estável ainda fecha a janela CloudOS quando o aplicativo realmente encerra', () => {
  assert.match(source, /else \{\s*closeWindow\(windowId\);\s*\}/s);
});
