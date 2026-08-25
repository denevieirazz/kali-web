import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createApp } from '../src/app.js';
import { resetLocalDatabase } from '../src/database/index.js';

function startServer(app) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, '127.0.0.1', () => {
      const address = server.address();
      resolve({ server, port: address.port });
    });
    server.on('error', reject);
  });
}

function request(port, path, { method = 'GET', token, body } = {}) {
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : JSON.stringify(body);
    const headers = {};
    if (payload !== null) {
      headers['Content-Type'] = 'application/json';
      headers['Content-Length'] = Buffer.byteLength(payload);
    }
    if (token) headers.Authorization = `Bearer ${token}`;

    const req = http.request({ host: '127.0.0.1', port, path, method, headers }, res => {
      let raw = '';
      res.on('data', chunk => { raw += chunk; });
      res.on('end', () => {
        let json = null;
        try { json = raw ? JSON.parse(raw) : null; } catch {}
        resolve({ status: res.statusCode, json, raw });
      });
    });
    req.on('error', reject);
    if (payload !== null) req.write(payload);
    req.end();
  });
}

test('setup admin is public only before first administrator exists', async () => {
  resetLocalDatabase();
  const { server, port } = await startServer(createApp(0, { environment: { NODE_ENV: 'test' } }));

  try {
    const created = await request(port, '/api/setup/admin', {
      method: 'POST',
      body: {
        username: 'admin',
        displayName: 'Administrador',
        password: 'SenhaInicial8',
        confirmPassword: 'SenhaInicial8'
      }
    });
    assert.equal(created.status, 201);
    assert.ok(created.json?.token);
    const originalToken = created.json.token;

    const takeover = await request(port, '/api/setup/admin', {
      method: 'POST',
      body: {
        username: 'admin',
        displayName: 'Atacante',
        password: 'SenhaTomada8',
        confirmPassword: 'SenhaTomada8',
        allowUpdate: true
      }
    });
    assert.equal(takeover.status, 401, 'existing administrator cannot be replaced without a session');

    const originalLogin = await request(port, '/api/auth/login', {
      method: 'POST',
      body: { username: 'admin', password: 'SenhaInicial8' }
    });
    assert.equal(originalLogin.status, 200, 'anonymous takeover did not mutate the administrator password');

    const authenticatedUpdate = await request(port, '/api/setup/admin', {
      method: 'POST',
      token: originalToken,
      body: {
        username: 'admin',
        displayName: 'Administrador Atualizado',
        password: 'SenhaNovaSegura8',
        confirmPassword: 'SenhaNovaSegura8',
        allowUpdate: true
      }
    });
    assert.equal(authenticatedUpdate.status, 201);
    assert.ok(authenticatedUpdate.json?.token);

    const staleSession = await request(port, '/api/auth/session', { token: originalToken });
    assert.equal(staleSession.status, 403, 'credential replacement revokes the old administrator session');

    const newLogin = await request(port, '/api/auth/login', {
      method: 'POST',
      body: { username: 'admin', password: 'SenhaNovaSegura8' }
    });
    assert.equal(newLogin.status, 200);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
