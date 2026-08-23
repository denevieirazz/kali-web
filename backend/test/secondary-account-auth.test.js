process.env.NODE_ENV = 'test';
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createApp } from '../src/app.js';
import { resetLocalDatabase } from '../src/database/index.js';

function startServer(app) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
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
        resolve({ status: res.statusCode, json });
      });
    });
    req.on('error', reject);
    if (payload !== null) req.write(payload);
    req.end();
  });
}

const secondary = {
  username: 'secondary_user',
  displayName: 'Secondary User',
  password: 'SecondaryPass8',
  confirmPassword: 'SecondaryPass8'
};

test('secondary local accounts require an authenticated administrator', async () => {
  resetLocalDatabase();
  const { server, port } = await startServer(createApp(0, { environment: { NODE_ENV: 'test' } }));
  try {
    const admin = await request(port, '/api/setup/admin', {
      method: 'POST',
      body: {
        username: 'admin', displayName: 'Administrator',
        password: 'AdminPassword8', confirmPassword: 'AdminPassword8'
      }
    });
    assert.equal(admin.status, 201);
    assert.ok(admin.json?.token);

    const anonymous = await request(port, '/api/auth/accounts', { method: 'POST', body: secondary });
    assert.equal(anonymous.status, 401, 'anonymous callers cannot create a machine-local identity');

    const created = await request(port, '/api/auth/accounts', {
      method: 'POST', token: admin.json.token, body: secondary
    });
    assert.equal(created.status, 201);
    assert.equal(created.json?.user?.role, 'user');
    assert.ok(created.json?.recoveryCode);

    const userLogin = await request(port, '/api/auth/login', {
      method: 'POST', body: { username: secondary.username, password: secondary.password }
    });
    assert.equal(userLogin.status, 200);

    const standardUserDenied = await request(port, '/api/auth/accounts', {
      method: 'POST', token: userLogin.json.token,
      body: { ...secondary, username: 'third_user', displayName: 'Third User' }
    });
    assert.equal(standardUserDenied.status, 403, 'standard users cannot create other local identities');
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
