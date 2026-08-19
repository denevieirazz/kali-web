import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'http';
import bcrypt from 'bcryptjs';
import { v4 as uuidv4 } from 'uuid';
import { createApp } from '../src/app.js';
import { getDb, resetLocalDatabase } from '../src/database/index.js';
import { MIN_PASSWORD_LENGTH, MAX_PASSWORD_LENGTH, validateNewPassword, validatePassword } from '../src/auth/security.js';

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

test('EF2-P0-004: Password policy unit validation', () => {
  assert.equal(MIN_PASSWORD_LENGTH, 8);
  assert.equal(MAX_PASSWORD_LENGTH, 128);

  // 1. Boundary: 7 chars rejected, 8 chars accepted
  assert.match(validateNewPassword('1234567', '1234567').error, /8 e 128/);
  assert.equal(validateNewPassword('12345678', '12345678').error, null);

  // 2. Boundary: 128 chars accepted, 129 chars rejected
  const p128 = 'a'.repeat(128);
  const p129 = 'a'.repeat(129);
  assert.equal(validateNewPassword(p128, p128).error, null);
  assert.match(validateNewPassword(p129, p129).error, /8 e 128/);

  // 3. Control characters rejected
  assert.match(validateNewPassword('pass\x00word12', 'pass\x00word12').error, /caracteres de controle/);
  assert.match(validateNewPassword('pass\tword12', 'pass\tword12').error, /caracteres de controle/);
  assert.match(validateNewPassword('pass\nword12', 'pass\nword12').error, /caracteres de controle/);

  // 4. Unicode, spaces and passphrases accepted without arbitrary composition rules
  assert.equal(validateNewPassword('CaféComPão#2026', 'CaféComPão#2026').error, null);
  assert.equal(validateNewPassword('senha super longa com espacos', 'senha super longa com espacos').error, null);
  assert.equal(validateNewPassword('correct horse battery staple', 'correct horse battery staple').error, null);

  // 5. Non-matching confirmation rejected
  assert.match(validateNewPassword('SenhaSegura123', 'OutraSenha123').error, /não confere/);

  // 6. Invalid input types rejected
  assert.match(validateNewPassword(null, null).error, /texto válido/);
  assert.match(validateNewPassword(12345678, 12345678).error, /texto válido/);
});

test('EF2-P0-004: HTTP Setup, Reset and Legacy Login Compatibility', async () => {
  resetLocalDatabase();
  const app = createApp(0);
  const { server, port } = await startServer(app);

  try {
    // 1. Setup rejects password shorter than 8 characters
    const shortSetup = await makeRequest(port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'admin', password: '1234567', confirmPassword: '1234567' }));
    assert.strictEqual(shortSetup.status, 400);
    assert.match(JSON.parse(shortSetup.body).error, /8 e 128/);

    // 2. Setup rejects password with control characters
    const ctrlSetup = await makeRequest(port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'admin', password: 'admin\x00password', confirmPassword: 'admin\x00password' }));
    assert.strictEqual(ctrlSetup.status, 400);
    assert.match(JSON.parse(ctrlSetup.body).error, /caracteres de controle/);

    // 3. Setup accepts strong password >= 8 characters
    const validSetup = await makeRequest(port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'admin', password: 'SenhaValida#2026', confirmPassword: 'SenhaValida#2026' }));
    assert.strictEqual(validSetup.status, 201);
    const validJson = JSON.parse(validSetup.body);
    assert.ok(validJson.token);
    assert.ok(validJson.recoveryCode);

    // 4. Recovery reset rejects password < 8 characters
    const shortRecovery = await makeRequest(port, {
      path: '/api/auth/recovery/reset',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      recoveryCode: validJson.recoveryCode,
      password: 'curta',
      confirmPassword: 'curta'
    }));
    assert.strictEqual(shortRecovery.status, 400);
    assert.match(JSON.parse(shortRecovery.body).error, /8 e 128/);

    // 5. Recovery reset accepts strong password >= 8 characters
    const okRecovery = await makeRequest(port, {
      path: '/api/auth/recovery/reset',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      recoveryCode: validJson.recoveryCode,
      password: 'NovaSenhaForte@2026',
      confirmPassword: 'NovaSenhaForte@2026'
    }));
    assert.strictEqual(okRecovery.status, 200);
    const okRecoveryJson = JSON.parse(okRecovery.body);
    assert.ok(okRecoveryJson.token);

    // 6. Login with new strong password works
    const loginOk = await makeRequest(port, {
      path: '/api/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'admin', password: 'NovaSenhaForte@2026' }));
    assert.strictEqual(loginOk.status, 200);
  } finally {
    server.close();
  }
});

test('EF2-P0-004: Legacy Account with Short Password Continues Authenticating Normally', async () => {
  resetLocalDatabase();
  const db = getDb();

  // Inserir diretamente uma conta legada que foi criada no passado com senha de 4 caracteres ("1234")
  const legacyUserId = uuidv4();
  const legacyPasswordHash = bcrypt.hashSync('1234', 4);
  await new Promise((resolve, reject) => {
    db.run(
      'INSERT INTO users (id, username, display_name, password_hash, recovery_code_hash, auth_version, role) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [legacyUserId, 'legacyuser', 'Legacy User', legacyPasswordHash, null, 1, 'admin'],
      (err) => err ? reject(err) : resolve()
    );
  });

  const app = createApp(0);
  const { server, port } = await startServer(app);

  try {
    // Login da conta legada com senha curta ("1234") DEVE passar com 200 OK
    const legacyLogin = await makeRequest(port, {
      path: '/api/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'legacyuser', password: '1234' }));
    assert.strictEqual(legacyLogin.status, 200);
    const legacyJson = JSON.parse(legacyLogin.body);
    assert.ok(legacyJson.token);
    assert.strictEqual(legacyJson.user.username, 'legacyuser');

    // Login com senha errada falha com 401
    const badLogin = await makeRequest(port, {
      path: '/api/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'legacyuser', password: 'wrong' }));
    assert.strictEqual(badLogin.status, 401);
  } finally {
    server.close();
  }
});
