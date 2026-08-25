import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  __test as preflightTest,
  evaluateOpaquePreflightCorrelation,
  finalizePhysicalPreflight,
  startPhysicalPreflight,
} from '../src/linuxRuntime/preflightEngine.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('EF2-P0-007: Fluxo correlacionado válido (SESSION + HTTP + WS + FRAME_ATTACH + NAVIGATION) produz PASS', () => {
  const mockSession = {
    id: 'preflight-test-1',
    state: 'ready',
    display: 100,
    port: 14500,
    metrics: {
      proxyHttpRequests: 2,
      proxyWebSocketConnections: 1,
    },
  };

  const evidence = {
    frameAttached: true,
    frameLoaded: true,
    loadMs: 150,
    signals: ['FRAME_ATTACH', 'NAVIGATION'],
  };

  const result = evaluateOpaquePreflightCorrelation({
    session: mockSession,
    evidence,
  });

  assert.equal(result.status, 'PASS');
  assert.equal(result.code, 'IFRAME_XPRA_CONNECTION_PASS');
  assert.equal(result.taxonomy, 'CORRELATED');
  assert.match(result.evidence, /httpRequests=2/);
  assert.match(result.evidence, /wsConnections=1/);
  assert.match(result.evidence, /loadMs=150ms/);
  assert.deepEqual(result.signals.sort(), ['CSP_SANDBOX', 'FRAME_ATTACH', 'HTTP', 'NAVIGATION', 'SESSION', 'WS'].sort());
});

test('EF2-P0-007: Client-only PASS sem requisições HTTP registradas pelo proxy é rejeitado (HTTP_PROXY_MISSING)', () => {
  const mockSession = {
    id: 'preflight-test-2',
    state: 'ready',
    display: 100,
    port: 14500,
    metrics: {
      proxyHttpRequests: 0,
      proxyWebSocketConnections: 1,
    },
  };

  const evidence = {
    status: 'PASS',
    frameAttached: true,
    frameLoaded: true,
    loadMs: 120,
  };

  const result = evaluateOpaquePreflightCorrelation({
    session: mockSession,
    evidence,
  });

  assert.equal(result.status, 'FAIL');
  assert.equal(result.taxonomy, 'HTTP');
  assert.equal(result.code, 'IFRAME_HTTP_PROXY_MISSING');
});

test('EF2-P0-007: Client-only PASS sem WebSocket upgrade registrado pelo proxy é rejeitado (WS_PROXY_MISSING)', () => {
  const mockSession = {
    id: 'preflight-test-3',
    state: 'ready',
    display: 100,
    port: 14500,
    metrics: {
      proxyHttpRequests: 3,
      proxyWebSocketConnections: 0,
    },
  };

  const evidence = {
    status: 'PASS',
    frameAttached: true,
    frameLoaded: true,
    loadMs: 120,
  };

  const result = evaluateOpaquePreflightCorrelation({
    session: mockSession,
    evidence,
  });

  assert.equal(result.status, 'FAIL');
  assert.equal(result.taxonomy, 'WS');
  assert.equal(result.code, 'IFRAME_WS_PROXY_MISSING');
});

test('EF2-P0-007: Sessão não-ready é rejeitada na correlação (SESSION_NOT_READY)', () => {
  const mockSession = {
    id: 'preflight-test-4',
    state: 'failed',
    display: 100,
    port: 14500,
    metrics: {
      proxyHttpRequests: 1,
      proxyWebSocketConnections: 1,
    },
  };

  const evidence = {
    frameAttached: true,
    frameLoaded: true,
    loadMs: 100,
  };

  const result = evaluateOpaquePreflightCorrelation({
    session: mockSession,
    evidence,
  });

  assert.equal(result.status, 'FAIL');
  assert.equal(result.taxonomy, 'SESSION');
  assert.equal(result.code, 'IFRAME_SESSION_NOT_READY');
});

test('EF2-P0-007: Ausência de anexo do frame é rejeitada (ATTACH_MISSING)', () => {
  const mockSession = {
    id: 'preflight-test-5',
    state: 'ready',
    display: 100,
    port: 14500,
    metrics: {
      proxyHttpRequests: 1,
      proxyWebSocketConnections: 1,
    },
  };

  const evidence = {
    frameAttached: false,
    frameLoaded: true,
    loadMs: 100,
  };

  const result = evaluateOpaquePreflightCorrelation({
    session: mockSession,
    evidence,
  });

  assert.equal(result.status, 'FAIL');
  assert.equal(result.taxonomy, 'FRAME_ATTACH');
  assert.equal(result.code, 'IFRAME_ATTACH_MISSING');
});

test('EF2-P0-007: Falha de navegação / loadMs inválido é rejeitada (NAVIGATION_FAILED)', () => {
  const mockSession = {
    id: 'preflight-test-6',
    state: 'ready',
    display: 100,
    port: 14500,
    metrics: {
      proxyHttpRequests: 1,
      proxyWebSocketConnections: 1,
    },
  };

  const evidence = {
    frameAttached: true,
    frameLoaded: false,
    loadMs: -1,
  };

  const result = evaluateOpaquePreflightCorrelation({
    session: mockSession,
    evidence,
  });

  assert.equal(result.status, 'FAIL');
  assert.equal(result.taxonomy, 'NAVIGATION');
  assert.equal(result.code, 'IFRAME_NAVIGATION_FAILED');
});

test('EF2-P0-007: finalizePhysicalPreflight rejeita runId incorreto ou inexistente', async () => {
  await assert.rejects(
    () => finalizePhysicalPreflight({ runId: 'non-existent-run-123', ownerId: 'cloudos-poc1-preflight' }),
    err => err.code === 'PREFLIGHT_RUN_NOT_FOUND',
  );
});

test('EF2-P0-007: Global codebase verification: zero occurrences of allow-same-origin in preflight iframe and zero contentDocument in preflight', () => {
  const frontendSource = fs.readFileSync(path.join(root, '../frontend/src/apps/LinuxRuntimePoc/LinuxRuntimePoc.tsx'), 'utf8');

  // Verify that onPreflightFrameLoad does not read contentDocument
  const preflightFnMatch = frontendSource.match(/function onPreflightFrameLoad[\s\S]*?^  \}/m);
  assert.ok(preflightFnMatch, 'onPreflightFrameLoad function not found');
  assert.doesNotMatch(preflightFnMatch[0], /contentDocument/);

  // Extract the preflight block
  const preflightStart = frontendSource.indexOf('title="CloudOS Linux Runtime Preflight');
  assert.ok(preflightStart > 0, 'Preflight iframe title not found');
  const preflightEnd = frontendSource.indexOf('/>', preflightStart);
  const preflightTag = frontendSource.slice(preflightStart, preflightEnd);
  assert.doesNotMatch(preflightTag, /allow-same-origin/);
});
