import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const sourcePath = path.resolve(here, '../src/apps/NativeAppWindow/NativeAppWindow.tsx');
const source = fs.readFileSync(sourcePath, 'utf8');

test('NativeAppWindow mantém janela transitória dentro de grace menor que o pending-attach do Host', () => {
  assert.match(source, /const SESSION_REPLACEMENT_GRACE_MS = 8_000;/);
  assert.match(source, /const startReplacementGrace = useCallback\(/);
  assert.match(source, /replacementTimerRef\.current = window\.setTimeout\(/);
  assert.match(source, /closeWindow\(windowId\);/);
});

test('primeiro attach stale reconcilia SESSION_NOT_FOUND antes de declarar erro', () => {
  assert.match(source, /attachSession\(currentSessionId, bounds, visible\)/);
  assert.match(source, /attachError instanceof NativeHostError/);
  assert.match(source, /attachError\.code !== 'SESSION_NOT_FOUND'/);
  assert.match(source, /const result = await nativeHostBridge\.listSessions\(\);/);
  assert.match(source, /nativeReplacementSession\(\s*result\.sessions,\s*currentSessionId,/s);
  assert.match(source, /adoptReplacementSession\(replacement\);/);
  assert.match(source, /setStatus\('waiting'\);\s*startReplacementGrace\(currentSessionId\);/s);
});

test('layout stale reconcilia replacement do mesmo Job sem deixar erro antigo vencer a nova sessão', () => {
  const syncStart = source.indexOf('const syncSurface = useCallback');
  const syncEnd = source.indexOf('\n\n  useEffect(() => {', syncStart);
  const syncBody = source.slice(syncStart, syncEnd);
  assert.match(syncBody, /layoutSession\(currentSessionId, bounds, visible\)/);
  assert.match(syncBody, /layoutError instanceof NativeHostError/);
  assert.match(syncBody, /layoutError\.code !== 'SESSION_NOT_FOUND'/);
  assert.match(syncBody, /if \(disposedRef\.current \|\| sessionIdRef\.current !== currentSessionId\) return;/);
  assert.match(syncBody, /const result = await nativeHostBridge\.listSessions\(\);/);
  assert.match(syncBody, /nativeReplacementSession\(\s*result\.sessions,\s*currentSessionId,/s);
  assert.match(syncBody, /adoptReplacementSession\(replacement\);/);
  assert.match(syncBody, /attachedRef\.current = false;\s*setStatus\('waiting'\);\s*startReplacementGrace\(currentSessionId\);/s);
});

test('evento de remoção só rebinda candidato único do mesmo launch e não fecha imediatamente', () => {
  const eventEffect = source.slice(source.indexOf('const unsubscribe = nativeHostBridge.onSessionsChanged'));
  assert.match(eventEffect, /nativeReplacementSession\(/);
  assert.match(eventEffect, /adoptReplacementSession\(replacement\);/);
  assert.match(eventEffect, /startReplacementGrace\(currentSessionId\);/);
  assert.doesNotMatch(eventEffect, /if \(!current\) closeWindow\(/);
});

test('adoção de replacement invalida estado de capture anterior antes do novo attach', () => {
  const start = source.indexOf('const adoptReplacementSession = useCallback');
  assert.notStrictEqual(start, -1);
  const end = source.indexOf('\n\n  const syncSurface', start);
  const body = source.slice(start, end);
  assert.match(body, /clearReplacementTimer\(\);/);
  assert.match(body, /attachInFlightSessionRef\.current = null;/);
  assert.match(body, /attachedRef\.current = false;/);
  assert.match(body, /lastLayoutRef\.current = null;/);
  assert.match(body, /sessionIdRef\.current = replacement\.sessionId;/);
  assert.match(body, /setSessionId\(replacement\.sessionId\);/);
});

test('attach nativo é serializado por sessão para impedir corrida de WGC em resize/scroll', () => {
  assert.match(source, /const attachInFlightSessionRef = useRef<string \| null>\(null\);/);
  const syncStart = source.indexOf('const syncSurface = useCallback');
  const syncEnd = source.indexOf('\n\n  useEffect(() => {', syncStart);
  const syncBody = source.slice(syncStart, syncEnd);
  assert.match(syncBody, /if \(attachInFlightSessionRef\.current === currentSessionId\) return;/);
  assert.match(syncBody, /attachInFlightSessionRef\.current = currentSessionId;/);
  assert.match(syncBody, /finally \{\s*if \(attachInFlightSessionRef\.current === currentSessionId\)/s);
  assert.match(syncBody, /attachInFlightSessionRef\.current = null;/);
});

test('snapshot tardio do Host recupera containment que venceu depois do timeout do renderer', () => {
  const eventEffect = source.slice(source.indexOf('const unsubscribe = nativeHostBridge.onSessionsChanged'));
  assert.match(eventEffect, /current\.contained === true && !attachedRef\.current/);
  assert.match(eventEffect, /current\.containmentMode === 'captured-surface'/);
  assert.match(eventEffect, /current\.containmentMode === 'anchored-overlay'/);
  assert.match(eventEffect, /attachInFlightSessionRef\.current = null;/);
  assert.match(eventEffect, /attachedRef\.current = true;/);
  assert.match(eventEffect, /lastLayoutRef\.current = null;/);
  assert.match(eventEffect, /setStatus\('contained'\);/);
  assert.match(eventEffect, /syncSurface\(false\)/);
});
