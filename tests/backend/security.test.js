import test from 'node:test';
import assert from 'node:assert';
import http from 'http';
import { WebSocket } from 'ws';
import { createApp } from '../../backend/src/app.js';
import { setupTerminalWebSocket } from '../../backend/src/terminal/websocket.js';
import { WebSocketServer } from 'ws';

function startFullServer() {
  return new Promise((resolve, reject) => {
    const app = createApp(0);
    const server = http.createServer(app);
    const wss = new WebSocketServer({ server, path: '/ws/terminal' });
    setupTerminalWebSocket(wss);

    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      resolve({ server, port });
    });
    server.on('error', reject);
  });
}

function requestHttp(port, options, body) {
  return new Promise((resolve, reject) => {
    const req = http.request(`http://127.0.0.1:${port}${options.path}`, {
      method: options.method || 'GET',
      headers: options.headers || {}
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

test('Segurança 1: WebSocket sem token é rejeitado (fechamento 1008)', async () => {
  const { server, port } = await startFullServer();
  try {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws/terminal`);
    const code = await new Promise((resolve) => {
      ws.on('close', (closeCode) => resolve(closeCode));
      ws.on('error', () => {});
    });
    assert.strictEqual(code, 1008);
  } finally {
    server.close();
  }
});

test('Segurança 2: Origin inválido é rejeitado pelo CORS', async () => {
  const { server, port } = await startFullServer();
  try {
    const res = await requestHttp(port, {
      path: '/api/health',
      headers: { 'Origin': 'http://evil-attacker-site.com' }
    });
    assert.strictEqual(res.status, 500); // Bloqueado pelo CORS com erro
  } finally {
    server.close();
  }
});

test('Segurança 3: Path traversal ../ em requisição é protegido', async () => {
  const { server, port } = await startFullServer();
  try {
    const res = await requestHttp(port, { path: '/api/../../../../etc/passwd' });
    assert.ok(res.status === 404 || res.status === 400);
  } finally {
    server.close();
  }
});

test('Segurança 4: Requisição não autenticada retorna 401', async () => {
  const { server, port } = await startFullServer();
  try {
    const res = await requestHttp(port, { path: '/api/system/metrics' });
    assert.strictEqual(res.status, 401);
  } finally {
    server.close();
  }
});

test('Segurança 5: Payload excessivo (>5MB) é rejeitado com 413', async () => {
  const { server, port } = await startFullServer();
  try {
    const bigBody = JSON.stringify({ data: 'A'.repeat(6 * 1024 * 1024) });
    const res = await requestHttp(port, {
      path: '/api/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, bigBody);
    assert.strictEqual(res.status, 413);
  } finally {
    server.close();
  }
});
