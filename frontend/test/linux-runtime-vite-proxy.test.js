import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocket, WebSocketServer } from 'ws';
import { createServer as createViteServer } from 'vite';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const frontendRoot = path.resolve(__dirname, '..');

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      server.removeListener('error', reject);
      const address = server.address();
      resolve(address && typeof address === 'object' ? address.port : 0);
    });
  });
}

function closeHttpServer(server) {
  return new Promise(resolve => server.close(() => resolve()));
}

function receiveWebSocket(url) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url, { handshakeTimeout: 3000 });
    const timer = setTimeout(() => {
      try { socket.terminate(); } catch {}
      reject(new Error('timeout waiting for proxied websocket payload'));
    }, 4000);
    socket.once('message', data => {
      clearTimeout(timer);
      const text = data.toString();
      socket.close();
      resolve(text);
    });
    socket.once('error', error => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

test('Vite dev server forwards POC1 capability HTTP and WebSocket paths unchanged', async () => {
  const runtimeDir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-poc1-vite-proxy-'));
  const previousRuntimeDir = process.env.CLOUDOS_RUNTIME_DIR;
  const expectedPrefix = '/__cloudos/linux-runtime/poc1/integration-session/integration-capability/';
  const backend = http.createServer((req, res) => {
    if (!req.url?.startsWith(expectedPrefix)) {
      res.writeHead(404).end();
      return;
    }
    res.writeHead(200, {
      'content-type': 'text/plain; charset=utf-8',
      'x-cloudos-proxy-test': 'http-pass',
    });
    res.end(`HTTP:${req.url}`);
  });
  const wss = new WebSocketServer({ noServer: true });
  backend.on('upgrade', (req, socket, head) => {
    if (!req.url?.startsWith(expectedPrefix)) {
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, client => {
      client.send(`WS:${req.url}`);
    });
  });

  let vite = null;
  try {
    const backendPort = await listen(backend);
    assert.ok(backendPort > 0);
    fs.writeFileSync(path.join(runtimeDir, 'backend-port.json'), JSON.stringify({ backendPort }), 'utf8');
    process.env.CLOUDOS_RUNTIME_DIR = runtimeDir;

    vite = await createViteServer({
      configFile: path.join(frontendRoot, 'vite.config.ts'),
      root: frontendRoot,
      logLevel: 'silent',
      server: { host: '127.0.0.1', port: 0, strictPort: false },
    });
    await vite.listen();
    const address = vite.httpServer?.address();
    const frontendPort = address && typeof address === 'object' ? address.port : 0;
    assert.ok(frontendPort > 0);

    const httpPath = `${expectedPrefix}js/Client.js?cap=1`;
    const response = await fetch(`http://127.0.0.1:${frontendPort}${httpPath}`, {
      signal: AbortSignal.timeout(4000),
    });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('x-cloudos-proxy-test'), 'http-pass');
    assert.equal(await response.text(), `HTTP:${httpPath}`);

    const wsPath = `${expectedPrefix}?path=${encodeURIComponent(expectedPrefix)}`;
    const wsPayload = await receiveWebSocket(`ws://127.0.0.1:${frontendPort}${wsPath}`);
    assert.equal(wsPayload, `WS:${wsPath}`);
  } finally {
    if (vite) await vite.close();
    for (const client of wss.clients) client.terminate();
    await new Promise(resolve => wss.close(() => resolve()));
    if (backend.listening) await closeHttpServer(backend);
    if (previousRuntimeDir === undefined) delete process.env.CLOUDOS_RUNTIME_DIR;
    else process.env.CLOUDOS_RUNTIME_DIR = previousRuntimeDir;
    fs.rmSync(runtimeDir, { recursive: true, force: true });
  }
});
