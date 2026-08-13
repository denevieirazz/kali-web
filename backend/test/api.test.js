import test from 'node:test';
import assert from 'node:assert';
import http from 'http';
import { createApp } from '../src/app.js';
import jwt from 'jsonwebtoken';
import { config } from '../src/config/index.js';

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

test('health do supervisor fica oculto e valida token/identidade da instância', async () => {
  const supervisorToken = 'supervisor-test-token-with-enough-entropy';
  const runtimeRunId = '4dbfc480-bf7d-4fa6-b10f-1390434603d2';
  const app = createApp(23456, {
    environment: {
      NODE_ENV: 'production',
      CLOUDOS_SUPERVISOR_TOKEN: supervisorToken,
      CLOUDOS_RUN_ID: runtimeRunId
    }
  });
  app._cloudosInstanceId = '8c96830d-5d46-4f06-b492-7f4e426a9da2';
  const { server, port } = await startServer(app);
  try {
    const hidden = await makeRequest(port, { path: '/_cloudos/supervisor/health' });
    assert.strictEqual(hidden.status, 404);
    const valid = await makeRequest(port, {
      path: '/_cloudos/supervisor/health',
      headers: { 'X-CloudOS-Supervisor-Token': supervisorToken }
    });
    assert.strictEqual(valid.status, 200);
    const json = JSON.parse(valid.body);
    assert.strictEqual(json.protocol, 1);
    assert.strictEqual(json.port, 23456);
    assert.strictEqual(json.runId, runtimeRunId);
    assert.strictEqual(json.instanceId, app._cloudosInstanceId);

    const hiddenShutdown = await makeRequest(port, {
      path: '/_cloudos/supervisor/shutdown',
      method: 'POST'
    });
    assert.strictEqual(hiddenShutdown.status, 404);

    const shutdownEvent = new Promise(resolve => app.once('cloudos:shutdown', resolve));
    const acceptedShutdown = await makeRequest(port, {
      path: '/_cloudos/supervisor/shutdown',
      method: 'POST',
      headers: { 'X-CloudOS-Supervisor-Token': supervisorToken }
    });
    assert.strictEqual(acceptedShutdown.status, 202);
    await shutdownEvent;
  } finally {
    server.close();
  }
});

test('CORS não aceita porta loopback arbitrária', async () => {
  const app = createApp(12345);
  const { server, port } = await startServer(app);
  try {
    const rejected = await makeRequest(port, {
      path: '/api/health',
      headers: { Origin: 'http://127.0.0.1:59999' }
    });
    assert.strictEqual(rejected.status, 403);
    const ownOrigin = await makeRequest(port, {
      path: '/api/health',
      headers: { Origin: 'http://127.0.0.1:12345' }
    });
    assert.strictEqual(ownOrigin.status, 200);
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

test('rotas de host, WSL e aplicativos exigem autenticação', async () => {
  const app = createApp(0);
  const { server, port } = await startServer(app);
  try {
    for (const route of ['/api/host/capabilities', '/api/wsl/distributions', '/api/apps']) {
      const res = await makeRequest(port, { path: route });
      assert.strictEqual(res.status, 401, route);
    }
  } finally {
    server.close();
  }
});

test('mutações administrativas do WSL rejeitam usuário sem papel admin', async () => {
  const app = createApp(0);
  const { server, port } = await startServer(app);
  try {
    const token = jwt.sign({ userId: 'user-1', username: 'user', role: 'user' }, config.jwtSecret, { expiresIn: '5m' });
    const res = await makeRequest(port, {
      path: '/api/wsl/update',
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' }
    }, '{}');
    assert.strictEqual(res.status, 403);
  } finally {
    server.close();
  }
});

test('reset local exige sessão autenticada', async () => {
  const app = createApp(0);
  const { server, port } = await startServer(app);
  try {
    const res = await makeRequest(port, {
      path: '/api/setup/reset',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ confirm: true }));
    assert.strictEqual(res.status, 401);
  } finally {
    server.close();
  }
});
