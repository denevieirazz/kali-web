import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n?/g, '\n');
const session = read('src/apps/CloudOSTerminal/TerminalSession.tsx');
const workspace = read('src/apps/CloudOSTerminal/CloudOSTerminal.tsx');
const transport = read('src/apps/CloudOSTerminal/terminalSessionTransport.js');

test('Terminal visível preserva workspace existente e usa transporte lifecycle com teardown visual drenado', () => {
  assert.match(workspace, /workspace\.tabs\.map/);
  assert.match(workspace, /workspace\.splitId/);
  assert.match(workspace, /closeTab\(/);
  for (const token of [
    /createTerminalTransport/,
    /transport\?\.dispose\(\)/,
    /inputSubscription\?\.dispose\(\)/,
    /resizeSubscription\?\.dispose\(\)/,
    /resizeObserver\?\.disconnect\(\)/,
    /disposeTerminalAfterViewportSettles\(terminal\)/,
  ]) assert.match(session, token);
  assert.doesNotMatch(session, /try \{ terminal\.dispose\(\); \} catch/, 'TerminalSession não pode voltar ao dispose visual imediato');
});

test('UI expõe somente distro modo e estado, nunca segredo porta ou PID', () => {
  assert.match(session, /Linux:/); assert.match(session, /Transporte:/); assert.match(session, /Estado:/); assert.match(session, /data-backend-mode/);
  assert.doesNotMatch(session, /corePid|terminalPid|bootstrapDiagnostic|\.port\b|secret/i);
});

test('Terminal não adiciona Enter ao input e Ctrl+C é sinal explícito', () => {
  assert.match(session, /transport\?\.input\(data\)/); assert.match(transport, /data === '\\x03'/); assert.match(transport, /type: 'signal', signal: 'interrupt'/);
  assert.doesNotMatch(session, /data\s*\+\s*['"`]\\r|data\s*\+\s*['"`]\\n/);
});

test('connected depende da mensagem backend e fallback tem estado próprio', () => {
  assert.match(transport, /message\.type === 'backend'/); assert.match(transport, /mode === WSL_CORE_MODE/); assert.match(transport, /emitStatus\('connected'\)/);
  assert.match(transport, /'legacy-fallback'/); assert.match(transport, /message\.protocol !== WSL_CORE_PROTOCOL/); assert.match(transport, /message\.protection !== WSL_CORE_PROTECTION/);
});
