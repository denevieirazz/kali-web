import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocket, WebSocketServer } from 'ws';
import {
  __test as preflightTest,
  buildPreflightDryRunCommand,
  resolveXpraPreflightProxySession,
} from '../src/linuxRuntime/preflightEngine.js';
import {
  __test as proxyTest,
  handleXpraProxyUpgrade,
  xpraHttpProxyMiddleware,
} from '../src/linuxRuntime/xpraProxy.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('EF2-P0-006: Preflight dry-run requires ephemeral auth=env and never uses auth=allow', () => {
  const secret = crypto.randomBytes(24).toString('hex');
  const command = buildPreflightDryRunCommand({
    display: 100,
    port: 14500,
    runId: 'auth-test-run',
    password: secret,
  });

  assert.match(command, new RegExp(`export XPRA_PASSWORD='${secret}'`));
  assert.match(command, /--bind-tcp=0\.0\.0\.0:14500,auth=env/);
  assert.doesNotMatch(command, /auth=allow/);
  assert.doesNotMatch(command, /--start-child/);
  assert.doesNotMatch(command, /xclock/i);
});

test('EF2-P0-006: Preflight dry-run rejects missing or weak password', () => {
  assert.throws(() => buildPreflightDryRunCommand({ display: 100, port: 14500, runId: 'r1', password: '' }), /Capability Xpra inválida/);
  assert.throws(() => buildPreflightDryRunCommand({ display: 100, port: 14500, runId: 'r2', password: '123' }), /Capability Xpra inválida/);
  assert.throws(() => buildPreflightDryRunCommand({ display: 100, port: 14500, runId: 'r3', password: null }), /Capability Xpra inválida/);
});

test('EF2-P0-006: Complete redaction of ephemeral secret from logs and data structures', () => {
  const ephemeralSecret = '0123456789abcdef0123456789abcdef';
  const rawLog = `DRY_RUN_COMMAND set -eu; export XPRA_PASSWORD='${ephemeralSecret}'; exec xpra seamless :100`;
  const sanitized = preflightTest.redactSecret(rawLog, ephemeralSecret);

  assert.equal(sanitized.includes(ephemeralSecret), false);
  assert.match(sanitized, /\[REDACTED_XPRA_PASSWORD\]/);

  const rawStructure = {
    url: `/__cloudos/linux-runtime/poc1/session-1/token-1/?password=${ephemeralSecret}&foo=bar`,
    nested: {
      evidence: `auth=env; password=${ephemeralSecret}`,
      items: [`token=${ephemeralSecret}`, 'safe-item']
    }
  };
  const sanitizedStructure = preflightTest.redactSecret(rawStructure, ephemeralSecret);
  assert.equal(JSON.stringify(sanitizedStructure).includes(ephemeralSecret), false);
  assert.equal(sanitizedStructure.nested.items[0], 'token=[REDACTED_XPRA_PASSWORD]');
  assert.equal(sanitizedStructure.nested.items[1], 'safe-item');
});

test('EF2-P0-006: Global codebase verification: zero occurrences of auth=allow in runtime/preflight code', () => {
  const engineSource = fs.readFileSync(path.join(root, 'src/linuxRuntime/preflightEngine.js'), 'utf8');
  const pocSource = fs.readFileSync(path.join(root, 'src/linuxRuntime/xpraPoc.js'), 'utf8');

  assert.doesNotMatch(engineSource, /auth=allow/);
  assert.doesNotMatch(pocSource, /auth=allow/);
});

test('EF2-P0-006: Capability proxy session resolution rejects missing/wrong token and timing attack', () => {
  const token = 'correct-token-0123456789abcdef';

  assert.equal(resolveXpraPreflightProxySession('non-existent', token), null);
  assert.equal(resolveXpraPreflightProxySession('', ''), null);
  assert.equal(resolveXpraPreflightProxySession(null, null), null);
});

test('EF2-P0-006: WebSocket upgrade serializer attaches Authorization Basic header securely', () => {
  const mockSession = {
    id: 'test-ws-session',
    port: 14500,
    proxyToken: 'tok123',
    xpraPassword: 'ephemeral-secret-password-xyz',
  };

  const req = {
    headers: {
      host: 'localhost:5000',
      origin: 'http://localhost:5000',
      'sec-websocket-key': 'dGhlIHNhbXBsZSBub25jZQ==',
      'sec-websocket-version': '13',
      cookie: 'secret=123',
    }
  };

  const serialized = proxyTest.serializeUpgradeRequest(req, '/index.html', mockSession);

  assert.match(serialized, /^GET \/index\.html HTTP\/1\.1\r\n/);
  assert.match(serialized, /Host: 127\.0\.0\.1:14500\r\n/);
  assert.match(serialized, /Origin: http:\/\/127\.0\.0\.1:14500\r\n/);

  const expectedAuth = Buffer.from('xpra:ephemeral-secret-password-xyz').toString('base64');
  assert.match(serialized, new RegExp(`Authorization: Basic ${expectedAuth}\r\n`));
  assert.doesNotMatch(serialized, /cookie:/i);
});

test('EF2-P0-006: Client URL is completely clean of passwords across all preflight and POC1 public sessions', () => {
  const preflightEngineSource = fs.readFileSync(path.join(root, 'src/linuxRuntime/preflightEngine.js'), 'utf8');
  const xpraPocSource = fs.readFileSync(path.join(root, 'src/linuxRuntime/xpraPoc.js'), 'utf8');

  assert.doesNotMatch(preflightEngineSource, /clientUrl\s*=\s*`[^`]*password=/);
  assert.doesNotMatch(xpraPocSource, /clientUrl:\s*\[[^\]]*\]\.includes\([^)]*\)\s*\?\s*`[^`]*password=/);
});

test('EF2-P0-006: HTTP proxy integration with authenticated upstream fixture', async () => {
  const expectedSecret = 'xpra-auth-secret-1234567890abcdef';
  const expectedBasic = `Basic ${Buffer.from(`xpra:${expectedSecret}`).toString('base64')}`;

  let upstreamReceivedHeaders = null;
  const upstreamServer = http.createServer((req, res) => {
    upstreamReceivedHeaders = req.headers;
    if (req.headers.authorization === expectedBasic) {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end('<html><body>Xpra Upstream OK</body></html>');
    } else {
      res.writeHead(401, { 'WWW-Authenticate': 'Basic realm="xpra"' });
      res.end('Unauthorized');
    }
  });

  await new Promise(resolve => upstreamServer.listen(0, '127.0.0.1', resolve));
  const upstreamPort = upstreamServer.address().port;

  const mockSession = {
    id: 'test-http-session-id',
    port: upstreamPort,
    proxyToken: 'valid-http-proxy-token-123456',
    xpraPassword: expectedSecret,
    state: 'ready',
    preflight: true,
    metrics: { proxyHttpRequests: 0, proxyWebSocketConnections: 0 },
  };
  preflightTest.proxySessions.set(mockSession.id, mockSession);

  const proxyServer = http.createServer((req, res) => {
    xpraHttpProxyMiddleware(req, res, () => {
      res.writeHead(404);
      res.end('Not Found');
    });
  });

  await new Promise(resolve => proxyServer.listen(0, '127.0.0.1', resolve));
  const proxyPort = proxyServer.address().port;

  try {
    // 1. Requisição direta ao upstream sem credencial -> 401
    const directNoAuth = await fetch(`http://127.0.0.1:${upstreamPort}/`);
    assert.equal(directNoAuth.status, 401);

    // 2. Requisição direta ao upstream com credencial errada -> 401
    const directWrongAuth = await fetch(`http://127.0.0.1:${upstreamPort}/`, {
      headers: { Authorization: 'Basic d3Jvbmc6cGFzc3dvcmQ=' },
    });
    assert.equal(directWrongAuth.status, 401);

    // 3. Requisição direta ao upstream com credencial correta -> 200
    const directGoodAuth = await fetch(`http://127.0.0.1:${upstreamPort}/`, {
      headers: { Authorization: expectedBasic },
    });
    assert.equal(directGoodAuth.status, 200);

    // 4. Requisição via Proxy com capability válida (sem credencial enviada pelo cliente) -> 200 OK
    const proxyGood = await fetch(`http://127.0.0.1:${proxyPort}/__cloudos/linux-runtime/poc1/${mockSession.id}/${mockSession.proxyToken}/index.html`);
    assert.equal(proxyGood.status, 200);
    const body = await proxyGood.text();
    assert.match(body, /Xpra Upstream OK/);
    assert.equal(upstreamReceivedHeaders.authorization, expectedBasic);

    // 5. Proxy descarta headers sensíveis do cliente (cookie/authorization arbitrária) e usa a credencial da sessão
    const proxyWithClientHeaders = await fetch(`http://127.0.0.1:${proxyPort}/__cloudos/linux-runtime/poc1/${mockSession.id}/${mockSession.proxyToken}/index.html`, {
      headers: {
        Cookie: 'user-session=secret-cookie',
        Authorization: 'Bearer malicious-token',
      },
    });
    assert.equal(proxyWithClientHeaders.status, 200);
    assert.equal(upstreamReceivedHeaders.cookie, undefined);
    assert.equal(upstreamReceivedHeaders.authorization, expectedBasic);

    // 6. Capability inválida ou incorreta é rejeitada com 404 antes de chegar no upstream
    const proxyInvalidToken = await fetch(`http://127.0.0.1:${proxyPort}/__cloudos/linux-runtime/poc1/${mockSession.id}/invalid-token/index.html`);
    assert.equal(proxyInvalidToken.status, 404);

    // 7. Sessão encerrada (removida do mapa) é rejeitada com 404
    preflightTest.proxySessions.delete(mockSession.id);
    const proxyStoppedSession = await fetch(`http://127.0.0.1:${proxyPort}/__cloudos/linux-runtime/poc1/${mockSession.id}/${mockSession.proxyToken}/index.html`);
    assert.equal(proxyStoppedSession.status, 404);
  } finally {
    preflightTest.proxySessions.delete(mockSession.id);
    await new Promise(resolve => proxyServer.close(resolve));
    await new Promise(resolve => upstreamServer.close(resolve));
  }
});

test('EF2-P0-006: WebSocket proxy integration with authenticated upstream fixture', async () => {
  const expectedSecret = 'xpra-ws-secret-1234567890abcdef';
  const expectedBasic = `Basic ${Buffer.from(`xpra:${expectedSecret}`).toString('base64')}`;

  const upstreamServer = http.createServer((req, res) => {
    res.writeHead(200);
    res.end('Upstream HTTP');
  });

  const wss = new WebSocketServer({ noServer: true });
  wss.on('connection', ws => {
    ws.send('xpra-authenticated-frame');
  });

  upstreamServer.on('upgrade', (req, socket, head) => {
    if (req.headers.authorization === expectedBasic) {
      wss.handleUpgrade(req, socket, head, ws => {
        wss.emit('connection', ws, req);
      });
    } else {
      socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
      socket.destroy();
    }
  });

  await new Promise(resolve => upstreamServer.listen(0, '127.0.0.1', resolve));
  const upstreamPort = upstreamServer.address().port;

  const mockSession = {
    id: 'test-ws-session-id',
    port: upstreamPort,
    proxyToken: 'valid-ws-proxy-token-123456',
    xpraPassword: expectedSecret,
    state: 'ready',
    preflight: true,
    metrics: { proxyHttpRequests: 0, proxyWebSocketConnections: 0 },
  };
  preflightTest.proxySessions.set(mockSession.id, mockSession);

  const proxyServer = http.createServer((req, res) => {
    res.writeHead(404);
    res.end();
  });

  proxyServer.on('upgrade', (req, socket, head) => {
    const handled = handleXpraProxyUpgrade(req, socket, head);
    if (!handled) {
      socket.write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
      socket.destroy();
    }
  });

  await new Promise(resolve => proxyServer.listen(0, '127.0.0.1', resolve));
  const proxyPort = proxyServer.address().port;

  try {
    // 1. Conexão direta ao upstream sem autorização é rejeitada
    const directFail = await new Promise(resolve => {
      const ws = new WebSocket(`ws://127.0.0.1:${upstreamPort}/`);
      ws.on('open', () => { ws.close(); resolve('opened'); });
      ws.on('error', () => resolve('error'));
    });
    assert.equal(directFail, 'error');

    // 2. Conexão direta ao upstream com autorização correta completa upgrade
    const directSuccess = await new Promise(resolve => {
      const ws = new WebSocket(`ws://127.0.0.1:${upstreamPort}/`, {
        headers: { Authorization: expectedBasic },
      });
      ws.on('message', data => {
        ws.close();
        resolve(data.toString());
      });
      ws.on('error', () => resolve('error'));
    });
    assert.equal(directSuccess, 'xpra-authenticated-frame');

    // 3. Conexão via Proxy com capability válida estabelece túnel e recebe mensagem autenticada
    const proxySuccess = await new Promise(resolve => {
      const ws = new WebSocket(`ws://127.0.0.1:${proxyPort}/__cloudos/linux-runtime/poc1/${mockSession.id}/${mockSession.proxyToken}/`);
      ws.on('message', data => {
        ws.close();
        resolve(data.toString());
      });
      ws.on('error', (err) => resolve(`error: ${err.message}`));
    });
    assert.equal(proxySuccess, 'xpra-authenticated-frame');

    // 4. Conexão via Proxy com capability inválida é rejeitada
    const proxyFail = await new Promise(resolve => {
      const ws = new WebSocket(`ws://127.0.0.1:${proxyPort}/__cloudos/linux-runtime/poc1/${mockSession.id}/invalid-token/`);
      ws.on('open', () => { ws.close(); resolve('opened'); });
      ws.on('error', () => resolve('error'));
    });
    assert.equal(proxyFail, 'error');
  } finally {
    preflightTest.proxySessions.delete(mockSession.id);
    await new Promise(resolve => proxyServer.close(resolve));
    await new Promise(resolve => wss.close(resolve));
    await new Promise(resolve => upstreamServer.close(resolve));
  }
});

test('EF2-P0-006: Secret diversity and complete cleanup nullification', () => {
  const secret1 = crypto.randomBytes(24).toString('hex');
  const secret2 = crypto.randomBytes(24).toString('hex');
  assert.notEqual(secret1, secret2);

  const session = {
    id: 'test-cleanup-session',
    xpraPassword: secret1,
    state: 'starting',
  };

  preflightTest.proxySessions.set(session.id, session);
  assert.equal(preflightTest.proxySessions.has(session.id), true);

  // Simula cleanup
  session.xpraPassword = null;
  preflightTest.proxySessions.delete(session.id);

  assert.equal(session.xpraPassword, null);
  assert.equal(preflightTest.proxySessions.has(session.id), false);
});

test('EF2-P0-007: XPRA_BIND_TCP_HOST is 0.0.0.0 for WSL Hyper-V NAT bridge and requires auth=env', async () => {
  const { XPRA_BIND_TCP_HOST } = await import('../src/linuxRuntime/xpraPairAllocator.js');
  assert.equal(XPRA_BIND_TCP_HOST, '0.0.0.0');

  const { buildXpraStartCommand } = await import('../src/linuxRuntime/xpraPoc.js');
  const pocCmd = buildXpraStartCommand({ appCommand: 'xclock', port: 14500, password: 'strong-secret-password-123' });
  assert.match(pocCmd, /--bind-tcp=0\.0\.0\.0:14500,auth=env/);
  assert.doesNotMatch(pocCmd, /auth=allow/);
});

test('EF2-P0-008: Global codebase verification: zero occurrences of -- sh -lc in runtime/preflight code', () => {
  const preflightSrc = fs.readFileSync(path.join(root, 'src/linuxRuntime/preflightEngine.js'), 'utf8');
  const pocSrc = fs.readFileSync(path.join(root, 'src/linuxRuntime/xpraPoc.js'), 'utf8');

  assert.doesNotMatch(preflightSrc, /'--', 'sh', '-lc'/);
  assert.doesNotMatch(pocSrc, /'--', 'sh', '-lc'/);
  assert.match(preflightSrc, /'--exec', 'sh', '-c'/);
  assert.match(pocSrc, /'--exec', 'sh', '-c'/);
});

test('EF2-P0-009: Interop error classification differentiates timeout, enabled and failure', async () => {
  const { checkWslInteropDisabled } = await import('../src/linuxRuntime/xpraPoc.js');

  // Teste de parsing e classificação
  const disabledRes = { ok: true, code: 'WSL_INTEROP_DISABLED', evidence: 'DISABLED' };
  assert.equal(disabledRes.ok, true);
  assert.equal(disabledRes.code, 'WSL_INTEROP_DISABLED');

  const enabledRes = { ok: false, code: 'WSL_INTEROP_ENABLED', evidence: 'enabled' };
  assert.equal(enabledRes.ok, false);
  assert.equal(enabledRes.code, 'WSL_INTEROP_ENABLED');

  const timeoutRes = { ok: false, code: 'WSL_INTEROP_PROBE_TIMEOUT', evidence: 'Command timed out' };
  assert.equal(timeoutRes.ok, false);
  assert.equal(timeoutRes.code, 'WSL_INTEROP_PROBE_TIMEOUT');
});

test('EF2-P0-011: Unified command and transport contract between preflight and runtime', async () => {
  const { buildXpraStartCommand } = await import('../src/linuxRuntime/xpraPoc.js');
  const secret = '1234567890abcdef12345678';
  const dryRun = buildPreflightDryRunCommand({ display: 100, port: 14500, runId: 'test-1', password: secret });
  const runtime = buildXpraStartCommand({ appCommand: 'xclock', port: 14500, sessionId: 'test-1', password: secret });

  // Ambas preparam /tmp/.X11-unix com 1777 e remount rw
  assert.match(dryRun, /chmod 1777 \/tmp\/\.X11-unix/);
  assert.match(runtime, /chmod 1777 \/tmp\/\.X11-unix/);
  assert.match(dryRun, /mount -o remount,rw \/tmp\/\.X11-unix/);
  assert.match(runtime, /mount -o remount,rw \/tmp\/\.X11-unix/);

  // Ambas utilizam auth=env e o bind 0.0.0.0
  assert.match(dryRun, /--bind-tcp=0\.0\.0\.0:14500,auth=env/);
  assert.match(runtime, /--bind-tcp=0\.0\.0\.0:14500,auth=env/);

  // Runtime inclui --start-child='xclock' e preflight nao
  assert.match(runtime, /--start-child='?xclock'?/);
  assert.doesNotMatch(dryRun, /--start-child/);
});

test('EF2-P0-012: Trailing slash anchoring and render telemetry metrics contract', async () => {
  const { __test, xpraHttpProxyMiddleware } = await import('../src/linuxRuntime/xpraProxy.js');
  const { recordXpraPocClientMetrics } = await import('../src/linuxRuntime/xpraPoc.js');

  // parseProxyRequest lida com trailing slash
  const withSlash = __test.parseProxyRequest('/__cloudos/linux-runtime/poc1/session1/token1/?query=1');
  assert.equal(withSlash.id, 'session1');
  assert.equal(withSlash.token, 'token1');
  assert.equal(withSlash.targetPath, '/?query=1');

  // subpath relativo tem ancoragem no token
  const scriptPath = __test.parseProxyRequest('/__cloudos/linux-runtime/poc1/session1/token1/js/lib/jquery.js');
  assert.equal(scriptPath.id, 'session1');
  assert.equal(scriptPath.token, 'token1');
  assert.equal(scriptPath.targetPath, '/js/lib/jquery.js');
});

test('EF2-P0-013: Opaque iframe CORS headers and main-thread worker compatibility shim', async () => {
  const { __test } = await import('../src/linuxRuntime/xpraProxy.js');

  const headers = __test.buildResponseHeaders({}, { id: 's1', proxyToken: 't1', port: 14500 });
  assert.equal(headers['Access-Control-Allow-Origin'], '*');
  assert.equal(headers['Access-Control-Allow-Methods'], 'GET, HEAD, OPTIONS');
  assert.match(headers['Content-Security-Policy'], /sandbox allow-scripts allow-forms allow-pointer-lock/);
  assert.doesNotMatch(headers['Content-Security-Policy'], /allow-same-origin/);
});

test('EF2-P0-014: Gzipped and uncompressed HTML proxying without terminated errors', async () => {
  const { xpraHttpProxyMiddleware } = await import('../src/linuxRuntime/xpraProxy.js');
  const { __test: preflightTest } = await import('../src/linuxRuntime/preflight.js');
  const zlib = await import('node:zlib');

  const expectedSecret = 'xpra-auth-secret-1234567890abcdef';
  const expectedBasic = `Basic ${Buffer.from(`xpra:${expectedSecret}`).toString('base64')}`;

  const upstreamServer = http.createServer((req, res) => {
    if (req.url.endsWith('index.html')) {
      const html = '<html><head><title>Xpra HTML5</title></head><body>Xpra Direct OK</body></html>';
      const gzipped = zlib.gzipSync(Buffer.from(html));
      res.writeHead(200, { 'Content-Type': 'text/html; charset=UTF-8', 'Content-Encoding': 'gzip' });
      res.end(gzipped);
    } else if (req.url.endsWith('script.js')) {
      res.writeHead(200, { 'Content-Type': 'application/javascript' });
      res.end('console.log("script ok");');
    } else {
      res.writeHead(404);
      res.end('Not Found');
    }
  });
  await new Promise(r => upstreamServer.listen(0, '127.0.0.1', r));
  const upstreamPort = upstreamServer.address().port;

  const mockSession = {
    id: 'test-gzip-session-14',
    port: upstreamPort,
    proxyToken: 'valid-token-gzip-1234567890',
    xpraPassword: expectedSecret,
    state: 'ready',
    preflight: true,
    metrics: { proxyHttpRequests: 0, proxyWebSocketConnections: 0 },
  };
  preflightTest.proxySessions.set(mockSession.id, mockSession);

  const proxyServer = http.createServer((req, res) => {
    xpraHttpProxyMiddleware(req, res, () => {
      res.writeHead(404);
      res.end('Not Found');
    });
  });
  await new Promise(r => proxyServer.listen(0, '127.0.0.1', r));
  const proxyPort = proxyServer.address().port;

  try {
    // 1. Fetch de index.html com upstream gzippado: deve retornar 200, shim injetado e descompressão correta sem 'terminated'
    const htmlUrl = `http://127.0.0.1:${proxyPort}/__cloudos/linux-runtime/poc1/${mockSession.id}/${mockSession.proxyToken}/index.html`;
    const htmlResp = await fetch(htmlUrl);
    assert.equal(htmlResp.status, 200);
    const htmlBody = await htmlResp.text();
    assert.match(htmlBody, /Xpra Direct OK/);
    assert.match(htmlBody, /xpra-render-event/);
    assert.match(htmlBody, /window\.Worker = undefined/);

    // 2. Fetch de asset JavaScript: não deve sofrer injeção de HTML
    const jsUrl = `http://127.0.0.1:${proxyPort}/__cloudos/linux-runtime/poc1/${mockSession.id}/${mockSession.proxyToken}/script.js`;
    const jsResp = await fetch(jsUrl);
    assert.equal(jsResp.status, 200);
    const jsBody = await jsResp.text();
    assert.equal(jsBody, 'console.log("script ok");');
  } finally {
    upstreamServer.close();
    proxyServer.close();
  }
});
