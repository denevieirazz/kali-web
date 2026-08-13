import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import test from 'node:test';
import { createApp } from '../src/app.js';
import { config } from '../src/config/index.js';
import { getDb, resetLocalDatabase } from '../src/database/index.js';
import { hashPassword } from '../src/auth/security.js';
import { resetLegacyTokensForTests } from '../src/auth/legacyTokenStore.js';

function createTestHostApp() {
  return createApp(0, {
    environment: { NODE_ENV: 'test' },
    testHooks: { allowTestHostHeader: true }
  });
}

function startServer(app) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

function makeRequest(port, options, body) {
  return new Promise((resolve, reject) => {
    const request = http.request(`http://127.0.0.1:${port}${options.path}`, {
      method: options.method || 'GET',
      headers: options.headers || {}
    }, (response) => {
      let data = '';
      response.on('data', chunk => { data += chunk; });
      response.on('end', () => resolve({ status: response.statusCode, body: data, headers: response.headers }));
    });
    request.on('error', reject);
    if (body) request.write(body);
    request.end();
  });
}

function jsonRequest(port, path, body, token) {
  return makeRequest(port, {
    path,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {})
    }
  }, JSON.stringify(body));
}

test('recuperação troca credenciais, preserva identidade/dados e revoga sessões antigas', async () => {
  resetLocalDatabase();
  const { server, port } = await startServer(createApp(0));
  try {
    const created = await jsonRequest(port, '/api/setup/admin', {
      username: 'admin-original',
      displayName: 'Administrador Original',
      password: 'senha-original-segura',
      confirmPassword: 'senha-original-segura'
    });
    assert.equal(created.status, 201);
    assert.match(created.headers['cache-control'], /no-store/);
    const setup = JSON.parse(created.body);
    assert.match(setup.recoveryCode, /^CLOUDOS-[A-Za-z0-9_-]{43}$/);
    assert.equal(setup.recoveryCodeShownOnce, true);
    assert.equal(setup.user.displayName, 'Administrador Original');

    await new Promise((resolve, reject) => getDb().run(
      'INSERT INTO operations (id, type, status, progress, step, message) VALUES (?, ?, ?, ?, ?, ?)',
      ['operation-before-recovery', 'test', 'done', 100, 'done', 'preservar'],
      error => error ? reject(error) : resolve()
    ));

    const storedBefore = fs.readFileSync(config.databasePath, 'utf8');
    assert.equal(storedBefore.includes('senha-original-segura'), false);
    assert.equal(storedBefore.includes(setup.recoveryCode), false);
    const parsedBefore = JSON.parse(storedBefore);
    assert.equal(parsedBefore.version, 2);
    assert.equal(parsedBefore.users[0].password, undefined);
    assert.equal(parsedBefore.users[0].recoveryCode, undefined);
    assert.notEqual(parsedBefore.users[0].recovery_code_hash, setup.recoveryCode);

    const status = await makeRequest(port, { path: '/api/auth/recovery/status' });
    assert.equal(status.status, 200);
    assert.deepEqual(JSON.parse(status.body), { available: true, legacyAdmin: false });
    assert.equal(status.body.includes('admin-original'), false);

    const rejected = await jsonRequest(port, '/api/auth/recovery/reset', {
      recoveryCode: `CLOUDOS-${'x'.repeat(43)}`,
      newUsername: 'admin-renovado',
      password: 'senha-nova-muito-segura',
      confirmPassword: 'senha-nova-muito-segura'
    });
    assert.equal(rejected.status, 401);
    assert.equal(rejected.body.includes('admin-original'), false);

    const recovered = await jsonRequest(port, '/api/auth/recovery/reset', {
      recoveryCode: setup.recoveryCode,
      newUsername: 'admin-renovado',
      displayName: 'Administrador Renovado',
      password: 'senha-nova-muito-segura',
      confirmPassword: 'senha-nova-muito-segura'
    });
    assert.equal(recovered.status, 200);
    assert.match(recovered.headers['cache-control'], /no-store/);
    const recovery = JSON.parse(recovered.body);
    assert.equal(recovery.user.id, setup.user.id);
    assert.equal(recovery.user.username, 'admin-renovado');
    assert.equal(recovery.user.displayName, 'Administrador Renovado');
    assert.notEqual(recovery.recoveryCode, setup.recoveryCode);

    const oldSession = await makeRequest(port, {
      path: '/api/auth/session',
      headers: { Authorization: `Bearer ${setup.token}` }
    });
    assert.equal(oldSession.status, 403);

    const oldLogin = await jsonRequest(port, '/api/auth/login', {
      username: 'admin-original',
      password: 'senha-original-segura'
    });
    assert.equal(oldLogin.status, 401);

    const newLogin = await jsonRequest(port, '/api/auth/login', {
      username: 'admin-renovado',
      password: 'senha-nova-muito-segura'
    });
    assert.equal(newLogin.status, 200);
    assert.equal(JSON.parse(newLogin.body).recoveryCode, undefined);

    const operation = await new Promise((resolve, reject) => getDb().get(
      'SELECT * FROM operations WHERE id = ?',
      ['operation-before-recovery'],
      (error, row) => error ? reject(error) : resolve(row)
    ));
    assert.equal(operation.id, 'operation-before-recovery');

    const reusedOldCode = await jsonRequest(port, '/api/auth/recovery/reset', {
      recoveryCode: setup.recoveryCode,
      password: 'outra-senha-bem-segura',
      confirmPassword: 'outra-senha-bem-segura'
    });
    assert.equal(reusedOldCode.status, 401);

    const rotated = await jsonRequest(port, '/api/auth/recovery/rotate', {}, recovery.token);
    assert.equal(rotated.status, 200);
    const rotation = JSON.parse(rotated.body);
    assert.match(rotation.recoveryCode, /^CLOUDOS-[A-Za-z0-9_-]{43}$/);
    assert.notEqual(rotation.recoveryCode, recovery.recoveryCode);

    const invalidatedByRotation = await jsonRequest(port, '/api/auth/recovery/reset', {
      recoveryCode: recovery.recoveryCode,
      password: 'mais-uma-senha-segura',
      confirmPassword: 'mais-uma-senha-segura'
    });
    assert.equal(invalidatedByRotation.status, 401);
  } finally {
    server.close();
    resetLocalDatabase();
  }
});

test('primeiro login de administrador legado cadastra um único código de recuperação', async () => {
  resetLocalDatabase();
  const passwordHash = await hashPassword('senha-legada-segura');
  await new Promise((resolve, reject) => getDb().run(
    'INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?)',
    ['legacy-user-id', 'admin-legado', passwordHash, 'admin'],
    error => error ? reject(error) : resolve()
  ));

  const { server, port } = await startServer(createApp(0));
  try {
    const concurrentLogins = await Promise.all([1, 2].map(() => jsonRequest(port, '/api/auth/login', {
      username: 'admin-legado',
      password: 'senha-legada-segura'
    })));
    assert.ok(concurrentLogins.every(response => response.status === 200));
    const loginBodies = concurrentLogins.map(response => JSON.parse(response.body));
    const issuedCodes = loginBodies.map(body => body.recoveryCode).filter(Boolean);
    assert.equal(issuedCodes.length, 1);
    assert.match(issuedCodes[0], /^CLOUDOS-[A-Za-z0-9_-]{43}$/);

    const laterLogin = await jsonRequest(port, '/api/auth/login', {
      username: 'admin-legado',
      password: 'senha-legada-segura'
    });
    assert.equal(laterLogin.status, 200);
    assert.equal(JSON.parse(laterLogin.body).recoveryCode, undefined);

    const stored = fs.readFileSync(config.databasePath, 'utf8');
    assert.equal(stored.includes(issuedCodes[0]), false);
    assert.ok(JSON.parse(stored).users[0].recovery_code_hash);
  } finally {
    server.close();
    resetLocalDatabase();
  }
});

test('recuperação limita tentativas de forma genérica e persistente', async () => {
  resetLocalDatabase();
  const { server, port } = await startServer(createApp(0));
  try {
    const created = await jsonRequest(port, '/api/setup/admin', {
      username: 'admin-throttle',
      password: 'senha-throttle-segura',
      confirmPassword: 'senha-throttle-segura'
    });
    assert.equal(created.status, 201);

    const responses = [];
    for (let attempt = 0; attempt < config.recoveryMaxAttempts; attempt += 1) {
      responses.push(await jsonRequest(port, '/api/auth/recovery/reset', {
        recoveryCode: `CLOUDOS-${String(attempt).padStart(43, 'x')}`,
        password: 'senha-nova-throttle',
        confirmPassword: 'senha-nova-throttle'
      }));
    }
    assert.ok(responses.slice(0, -1).every(response => response.status === 401));
    assert.equal(responses.at(-1).status, 429);
    assert.ok(Number(responses.at(-1).headers['retry-after']) >= 1);
    assert.equal(responses.at(-1).body.includes('admin-throttle'), false);

    const correctWhileLimited = await jsonRequest(port, '/api/auth/recovery/reset', {
      recoveryCode: JSON.parse(created.body).recoveryCode,
      password: 'senha-nova-throttle',
      confirmPassword: 'senha-nova-throttle'
    });
    assert.equal(correctWhileLimited.status, 429);
  } finally {
    server.close();
    resetLocalDatabase();
  }
});

test('login limita força bruta sem enumerar nem persistir os dados tentados', async () => {
  resetLocalDatabase();
  const { server, port } = await startServer(createApp(0));
  try {
    const created = await jsonRequest(port, '/api/setup/admin', {
      username: 'admin-login-limit',
      password: 'senha-login-limit-segura',
      confirmPassword: 'senha-login-limit-segura'
    });
    assert.equal(created.status, 201);

    const missingAccount = await jsonRequest(port, '/api/auth/login', {
      username: 'usuario-que-nao-deve-ser-gravado',
      password: 'senha-que-nao-deve-ser-gravada'
    });
    const existingAccount = await jsonRequest(port, '/api/auth/login', {
      username: 'admin-login-limit',
      password: 'senha-incorreta-que-nao-deve-ser-gravada'
    });
    assert.equal(missingAccount.status, 401);
    assert.equal(existingAccount.status, 401);
    assert.equal(missingAccount.body, existingAccount.body);
    assert.match(missingAccount.headers['cache-control'], /no-store/);

    let limited;
    for (let attempt = 2; attempt < config.loginMaxAttempts; attempt += 1) {
      limited = await jsonRequest(port, '/api/auth/login', {
        username: `inexistente-${attempt}`,
        password: `tentativa-invalida-${attempt}`
      });
    }
    assert.equal(limited.status, 429);
    assert.ok(Number(limited.headers['retry-after']) >= 1);
    assert.equal(limited.body.includes('admin-login-limit'), false);

    const stored = fs.readFileSync(config.databasePath, 'utf8');
    assert.equal(stored.includes('usuario-que-nao-deve-ser-gravado'), false);
    assert.equal(stored.includes('senha-que-nao-deve-ser-gravada'), false);
    assert.deepEqual(Object.keys(JSON.parse(stored).security.login).sort(), [
      'failed_attempts', 'locked_until', 'window_started_at'
    ]);

    const correctWhileLimited = await jsonRequest(port, '/api/auth/login', {
      username: 'admin-login-limit',
      password: 'senha-login-limit-segura'
    });
    assert.equal(correctWhileLimited.status, 429);

    resetLocalDatabase();
    const recreated = await jsonRequest(port, '/api/setup/admin', {
      username: 'admin-login-clear',
      password: 'senha-login-clear-segura',
      confirmPassword: 'senha-login-clear-segura'
    });
    assert.equal(recreated.status, 201);
    const oneFailure = await jsonRequest(port, '/api/auth/login', {
      username: 'admin-login-clear',
      password: 'senha-incorreta-login-clear'
    });
    assert.equal(oneFailure.status, 401);
    assert.equal(getDb().getLoginThrottle().failedAttempts, 1);

    const successful = await jsonRequest(port, '/api/auth/login', {
      username: 'admin-login-clear',
      password: 'senha-login-clear-segura'
    });
    assert.equal(successful.status, 200);
    assert.equal(getDb().getLoginThrottle().failedAttempts, 0);
  } finally {
    server.close();
    resetLocalDatabase();
  }
});

test('recuperação sem alterar o username preserva o username original retornado pelo backend', async () => {
  resetLocalDatabase();
  const { server, port } = await startServer(createApp(0));
  try {
    const created = await jsonRequest(port, '/api/setup/admin', {
      username: 'admin-inalterado',
      displayName: 'Administrador Inalterado',
      password: 'senha-original-muito-segura',
      confirmPassword: 'senha-original-muito-segura'
    });
    assert.equal(created.status, 201);
    const setup = JSON.parse(created.body);

    const recovered = await jsonRequest(port, '/api/auth/recovery/reset', {
      recoveryCode: setup.recoveryCode,
      password: 'senha-nova-redefinida-123',
      confirmPassword: 'senha-nova-redefinida-123'
    });
    assert.equal(recovered.status, 200);
    const recovery = JSON.parse(recovered.body);
    assert.equal(recovery.user.username, 'admin-inalterado');
    assert.equal(recovery.user.displayName, 'Administrador Inalterado');
    assert.equal(recovery.user.id, setup.user.id);
    assert.match(recovery.recoveryCode, /^CLOUDOS-[A-Za-z0-9_-]{43}$/);
    assert.notEqual(recovery.recoveryCode, setup.recoveryCode);

    const loginNew = await jsonRequest(port, '/api/auth/login', {
      username: 'admin-inalterado',
      password: 'senha-nova-redefinida-123'
    });
    assert.equal(loginNew.status, 200);

    const loginOld = await jsonRequest(port, '/api/auth/login', {
      username: 'admin-inalterado',
      password: 'senha-original-muito-segura'
    });
    assert.equal(loginOld.status, 401);
  } finally {
    server.close();
    resetLocalDatabase();
  }
});

test('recuperação legada: detecta admin sem recovery_code_hash e emite token somente para host autorizado', async () => {
  resetLocalDatabase();
  resetLegacyTokensForTests();
  const passwordHash = await hashPassword('senha-legada-antiga');
  await new Promise((resolve, reject) => getDb().run(
    'INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?)',
    ['legacy-user-1', 'admin-legado', passwordHash, 'admin'],
    error => error ? reject(error) : resolve()
  ));

  const supervisorToken = 'supervisor-production-token-with-enough-entropy';
  const hostLeaseToken = 'host-lease-production-token-with-enough-entropy';
  const { server, port } = await startServer(createApp(0, {
    environment: {
      NODE_ENV: 'production',
      CLOUDOS_SUPERVISOR_TOKEN: supervisorToken,
      CLOUDOS_HOST_LEASE_TOKEN: hostLeaseToken
    }
  }));
  try {
    const statusRes = await makeRequest(port, { path: '/api/auth/recovery/status' });
    assert.equal(statusRes.status, 200);
    const status = JSON.parse(statusRes.body);
    assert.equal(status.available, false);
    assert.equal(status.legacyAdmin, true);

    const unauthorizedIssue = await jsonRequest(port, '/api/auth/legacy-recovery/issue-token', {});
    assert.equal(unauthorizedIssue.status, 403);

    const spoofedTestHost = await makeRequest(port, {
      path: '/api/auth/legacy-recovery/issue-token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CloudOS-Test-Host': '1'
      }
    }, '{}');
    assert.equal(spoofedTestHost.status, 403);

    const authorizedIssue = await makeRequest(port, {
      path: '/api/auth/legacy-recovery/issue-token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CloudOS-Supervisor-Token': supervisorToken
      }
    }, '{}');
    assert.equal(authorizedIssue.status, 200);
    const issued = JSON.parse(authorizedIssue.body);
    assert.match(issued.token, /^LEGACY-[A-F0-9]{24}$/);
    assert.equal(typeof issued.expiresIn, 'number');

    const authorizedLeaseIssue = await makeRequest(port, {
      path: '/api/auth/legacy-recovery/issue-token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CloudOS-Host-Token': hostLeaseToken
      }
    }, '{}');
    assert.equal(authorizedLeaseIssue.status, 200);
    assert.match(JSON.parse(authorizedLeaseIssue.body).token, /^LEGACY-[A-F0-9]{24}$/);
  } finally {
    server.close();
    resetLocalDatabase();
    resetLegacyTokensForTests();
  }
});

test('recuperação legada: redefine credenciais com token único e gera primeiro recovery code', async () => {
  resetLocalDatabase();
  resetLegacyTokensForTests();
  const passwordHash = await hashPassword('senha-legada-antiga');
  await new Promise((resolve, reject) => getDb().run(
    'INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?)',
    ['legacy-user-2', 'admin-antigo', passwordHash, 'admin'],
    error => error ? reject(error) : resolve()
  ));

  const { server, port } = await startServer(createTestHostApp());
  try {
    const issueRes = await makeRequest(port, {
      path: '/api/auth/legacy-recovery/issue-token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CloudOS-Test-Host': '1'
      }
    }, '{}');
    const { token: legacyToken } = JSON.parse(issueRes.body);

    const recoverRes = await jsonRequest(port, '/api/auth/legacy-recovery/reset', {
      legacyToken,
      password: 'nova-senha-segura-1234',
      confirmPassword: 'nova-senha-segura-1234'
    });
    assert.equal(recoverRes.status, 200);
    const recovered = JSON.parse(recoverRes.body);
    assert.equal(recovered.user.username, 'admin-antigo');
    assert.equal(recovered.user.id, 'legacy-user-2');
    assert.match(recovered.recoveryCode, /^CLOUDOS-[A-Za-z0-9_-]{43}$/);
    assert.equal(recovered.recoveryCodeShownOnce, true);

    const statusRes = await makeRequest(port, { path: '/api/auth/recovery/status' });
    const status = JSON.parse(statusRes.body);
    assert.equal(status.available, true);
    assert.equal(status.legacyAdmin, false);

    const loginOk = await jsonRequest(port, '/api/auth/login', {
      username: 'admin-antigo',
      password: 'nova-senha-segura-1234'
    });
    assert.equal(loginOk.status, 200);

    const loginOld = await jsonRequest(port, '/api/auth/login', {
      username: 'admin-antigo',
      password: 'senha-legada-antiga'
    });
    assert.equal(loginOld.status, 401);

    const secondIssue = await makeRequest(port, {
      path: '/api/auth/legacy-recovery/issue-token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CloudOS-Test-Host': '1'
      }
    }, '{}');
    assert.equal(secondIssue.status, 400);
  } finally {
    server.close();
    resetLocalDatabase();
    resetLegacyTokensForTests();
  }
});

test('recuperação legada: rejeita reutilização de token e token expirado', async () => {
  resetLocalDatabase();
  resetLegacyTokensForTests();
  const passwordHash = await hashPassword('senha-legada-antiga');
  await new Promise((resolve, reject) => getDb().run(
    'INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?)',
    ['legacy-user-3', 'admin-reuse', passwordHash, 'admin'],
    error => error ? reject(error) : resolve()
  ));

  const { server, port } = await startServer(createTestHostApp());
  try {
    const issueRes = await makeRequest(port, {
      path: '/api/auth/legacy-recovery/issue-token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CloudOS-Test-Host': '1'
      }
    }, '{}');
    const { token: singleUseToken } = JSON.parse(issueRes.body);

    const firstUse = await jsonRequest(port, '/api/auth/legacy-recovery/reset', {
      legacyToken: singleUseToken,
      password: 'senha-primeiro-uso-123',
      confirmPassword: 'senha-primeiro-uso-123'
    });
    assert.equal(firstUse.status, 200);

    const secondUse = await jsonRequest(port, '/api/auth/legacy-recovery/reset', {
      legacyToken: singleUseToken,
      password: 'senha-segundo-uso-123',
      confirmPassword: 'senha-segundo-uso-123'
    });
    assert.equal(secondUse.status, 401);

    resetLocalDatabase();
    await new Promise((resolve, reject) => getDb().run(
      'INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?)',
      ['legacy-user-4', 'admin-expired', passwordHash, 'admin'],
      error => error ? reject(error) : resolve()
    ));

    const { issueLegacyToken } = await import('../src/auth/legacyTokenStore.js');
    const expiredTokenData = issueLegacyToken({ ttlMs: -1000 });

    const expiredUse = await jsonRequest(port, '/api/auth/legacy-recovery/reset', {
      legacyToken: expiredTokenData.token,
      password: 'senha-expirada-123',
      confirmPassword: 'senha-expirada-123'
    });
    assert.equal(expiredUse.status, 401);
  } finally {
    server.close();
    resetLocalDatabase();
    resetLegacyTokensForTests();
  }
});

test('recuperação legada: bloqueia tentativas excessivas com rate limit e registra auditoria sem senhas', async () => {
  resetLocalDatabase();
  resetLegacyTokensForTests();
  const passwordHash = await hashPassword('senha-legada-antiga');
  await new Promise((resolve, reject) => getDb().run(
    'INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?)',
    ['legacy-user-5', 'admin-rate', passwordHash, 'admin'],
    error => error ? reject(error) : resolve()
  ));

  const { server, port } = await startServer(createTestHostApp());
  try {
    let rateLimited;
    for (let attempt = 0; attempt < config.recoveryMaxAttempts; attempt += 1) {
      rateLimited = await jsonRequest(port, '/api/auth/legacy-recovery/reset', {
        legacyToken: `LEGACY-FORGED-TOKEN-${attempt}`,
        password: 'senha-tentativa-invalida',
        confirmPassword: 'senha-tentativa-invalida'
      });
    }
    assert.equal(rateLimited.status, 429);
    assert.ok(Number(rateLimited.headers['retry-after']) >= 1);

    getDb().clearRecoveryThrottle();

    const issueRes = await makeRequest(port, {
      path: '/api/auth/legacy-recovery/issue-token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CloudOS-Test-Host': '1'
      }
    }, '{}');
    const { token: validToken } = JSON.parse(issueRes.body);

    const successfulRecovery = await jsonRequest(port, '/api/auth/legacy-recovery/reset', {
      legacyToken: validToken,
      password: 'senha-auditada-sucesso',
      confirmPassword: 'senha-auditada-sucesso'
    });
    assert.equal(successfulRecovery.status, 200);

    const operations = await new Promise((resolve, reject) => getDb().all(
      'SELECT * FROM operations WHERE type = ?',
      ['legacy-account-recovery'],
      (error, rows) => error ? reject(error) : resolve(rows)
    ));
    assert.ok(operations.length >= 1);
    const op = operations[0];
    assert.equal(op.target, 'admin-rate');
    assert.equal(op.status, 'completed');
    assert.equal('password' in op, false);
    assert.equal('token' in op, false);
    assert.equal('legacyToken' in op, false);
    assert.equal('recoveryCode' in op, false);
  } finally {
    server.close();
    resetLocalDatabase();
    resetLegacyTokensForTests();
  }
});
