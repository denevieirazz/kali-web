import test from 'node:test';
import assert from 'node:assert';
import http from 'http';
import { createApp } from '../src/app.js';

function startServer(app) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, '127.0.0.1', () => {
      const addr = server.address();
      resolve({ server, port: addr.port });
    });
    server.on('error', reject);
  });
}

function makeRequest(port, options, body) {
  return new Promise((resolve, reject) => {
    const req = http.request(`http://127.0.0.1:${port}${options.path}`, {
      method: options.method || 'GET',
      headers: options.headers || {}
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        resolve({ status: res.statusCode, body: data, headers: res.headers });
      });
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

test('GET /api/health retorna status ok', async () => {
  const app = createApp(0);
  const { server, port } = await startServer(app);
  try {
    const res = await makeRequest(port, { path: '/api/health' });
    assert.strictEqual(res.status, 200);
    const json = JSON.parse(res.body);
    assert.strictEqual(json.status, 'ok');
  } finally {
    server.close();
  }
});

test('GET /api/runtime retorna configuração válida', async () => {
  const app = createApp(12345);
  const { server, port } = await startServer(app);
  try {
    const res = await makeRequest(port, { path: '/api/runtime' });
    assert.strictEqual(res.status, 200);
    const json = JSON.parse(res.body);
    assert.strictEqual(json.host, '127.0.0.1');
    assert.strictEqual(json.backendPort, 12345);
    assert.ok(json.apiBase.startsWith('http://127.0.0.1:'));
    assert.ok(json.webSocketBase.startsWith('ws://127.0.0.1:'));
  } finally {
    server.close();
  }
});

test('POST /api/auth/login rejeita requisição vazia com 400', async () => {
  const app = createApp(0);
  const { server, port } = await startServer(app);
  try {
    const res = await makeRequest(port, {
      path: '/api/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({}));
    assert.strictEqual(res.status, 400);
  } finally {
    server.close();
  }
});

test('GET /api/system/metrics retorna 401 sem token', async () => {
  const app = createApp(0);
  const { server, port } = await startServer(app);
  try {
    const res = await makeRequest(port, { path: '/api/system/metrics' });
    assert.strictEqual(res.status, 401);
  } finally {
    server.close();
  }
});

test('GET /api/system/metrics retorna 403 com token inválido', async () => {
  const app = createApp(0);
  const { server, port } = await startServer(app);
  try {
    const res = await makeRequest(port, {
      path: '/api/system/metrics',
      headers: { 'Authorization': 'Bearer token_invalido_12345' }
    });
    assert.strictEqual(res.status, 403);
  } finally {
    server.close();
  }
});

test('GET /api/operations/inexistente retorna 401 sem token', async () => {
  const app = createApp(0);
  const { server, port } = await startServer(app);
  try {
    const res = await makeRequest(port, { path: '/api/operations/inexistente' });
    assert.strictEqual(res.status, 401);
  } finally {
    server.close();
  }
});

test('Payload excessivo retorna 413', async () => {
  const app = createApp(0);
  const { server, port } = await startServer(app);
  try {
    const bigBody = JSON.stringify({ data: 'x'.repeat(6 * 1024 * 1024) });
    const res = await makeRequest(port, {
      path: '/api/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, bigBody);
    assert.strictEqual(res.status, 413);
  } finally {
    server.close();
  }
});
