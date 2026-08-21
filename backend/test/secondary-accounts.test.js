process.env.NODE_ENV = process.env.NODE_ENV || 'test';
import test from 'node:test';
import assert from 'node:assert';
import http from 'http';
import { createApp } from '../src/app.js';
import { getDb, resetLocalDatabase } from '../src/database/index.js';

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

test('Contas secundárias: ciclo de vida, validações, isolamento e bloqueio de WSL Files', async () => {
  resetLocalDatabase();
  const app = createApp(0, {
    environment: { NODE_ENV: 'test' }
  });
  const { server, port } = await startServer(app);

  try {
    // 1. Tentar criar conta secundária antes do setup deve falhar com 400
    const premature = await makeRequest(port, {
      path: '/api/auth/accounts',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'user1', password: 'password123', confirmPassword: 'password123' }));
    assert.strictEqual(premature.status, 400);

    // 2. Concluir setup com conta administradora
    const adminSetup = await makeRequest(port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'rootadmin', displayName: 'Root Admin', password: 'adminpassword123', confirmPassword: 'adminpassword123' }));
    assert.strictEqual(adminSetup.status, 201);
    const adminData = JSON.parse(adminSetup.body);
    const adminToken = adminData.token;
    assert.strictEqual(adminData.user.role, 'admin');

    // 3. Tentar criar conta secundária com senhas divergentes
    const mismatch = await makeRequest(port, {
      path: '/api/auth/accounts',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'alice', password: 'password123', confirmPassword: 'differentpassword' }));
    assert.strictEqual(mismatch.status, 400);

    // 4. Tentar criar conta secundária com senha fraca / curta
    const weak = await makeRequest(port, {
      path: '/api/auth/accounts',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'alice', password: '123', confirmPassword: '123' }));
    assert.strictEqual(weak.status, 400);

    // 5. Criar conta secundária válida para Alice (role: user)
    const createAlice = await makeRequest(port, {
      path: '/api/auth/accounts',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'alice', displayName: 'Alice User', password: 'alicepassword123', confirmPassword: 'alicepassword123' }));
    assert.strictEqual(createAlice.status, 201);
    const aliceData = JSON.parse(createAlice.body);
    assert.strictEqual(aliceData.user.username, 'alice');
    assert.strictEqual(aliceData.user.role, 'user');
    assert.ok(aliceData.recoveryCode);
    assert.strictEqual(aliceData.recoveryCodeShownOnce, true);
    // Redaction: senha e hashes não devem constar no retorno
    assert.strictEqual(aliceData.user.password, undefined);
    assert.strictEqual(aliceData.user.password_hash, undefined);
    assert.strictEqual(aliceData.user.recovery_code_hash, undefined);

    // 6. Tentar duplicar usuário (case-insensitive) deve falhar com 400
    const duplicate = await makeRequest(port, {
      path: '/api/auth/accounts',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'ALICE', password: 'alicepassword123', confirmPassword: 'alicepassword123' }));
    assert.strictEqual(duplicate.status, 400);

    // 7. Criar conta secundária para Bob
    const createBob = await makeRequest(port, {
      path: '/api/auth/accounts',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'bob', displayName: 'Bob User', password: 'bobpassword123', confirmPassword: 'bobpassword123' }));
    assert.strictEqual(createBob.status, 201);
    const bobData = JSON.parse(createBob.body);
    assert.strictEqual(bobData.user.username, 'bob');
    assert.strictEqual(bobData.user.role, 'user');
    assert.notStrictEqual(bobData.user.id, aliceData.user.id);
    assert.notStrictEqual(bobData.recoveryCode, aliceData.recoveryCode);

    // 8. Autenticar Alice
    const loginAlice = await makeRequest(port, {
      path: '/api/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'alice', password: 'alicepassword123' }));
    assert.strictEqual(loginAlice.status, 200);
    const aliceSession = JSON.parse(loginAlice.body);
    const aliceToken = aliceSession.token;
    assert.strictEqual(aliceSession.user.role, 'user');

    // 9. Verificar sessão de Alice
    const sessionRes = await makeRequest(port, {
      path: '/api/auth/session',
      headers: { Authorization: `Bearer ${aliceToken}` }
    });
    assert.strictEqual(sessionRes.status, 200);
    const sessionData = JSON.parse(sessionRes.body);
    assert.strictEqual(sessionData.user.username, 'alice');
    assert.strictEqual(sessionData.user.role, 'user');

    // 10. Bloqueio de WSL Files para contas secundárias (Alice)
    const wslFilesAlice = await makeRequest(port, {
      path: '/api/files/wsl/list',
      method: 'POST',
      headers: {
        Authorization: `Bearer ${aliceToken}`,
        'Content-Type': 'application/json',
        'x-cloudos-file-actor': 'user-ui'
      }
    }, JSON.stringify({ path: [] }));
    assert.strictEqual(wslFilesAlice.status, 403);
    const wslAliceJson = JSON.parse(wslFilesAlice.body);
    assert.strictEqual(wslAliceJson.error.code, 'FILES_SECONDARY_USER_BLOCKED');

    // 11. Conta principal (Admin) mantém acesso sem bloqueio por role
    const wslFilesAdmin = await makeRequest(port, {
      path: '/api/files/wsl/list',
      method: 'POST',
      headers: {
        Authorization: `Bearer ${adminToken}`,
        'Content-Type': 'application/json',
        'x-cloudos-file-actor': 'user-ui'
      }
    }, JSON.stringify({ path: [] }));
    // Não deve ser 403 FILES_SECONDARY_USER_BLOCKED (pode ser 200 ou 503 unavailable dependendo do WSL mock)
    assert.notStrictEqual(wslFilesAdmin.status, 403);

    // 12. Recuperação de conta secundária com código de recuperação de Alice
    const resetAlice = await makeRequest(port, {
      path: '/api/auth/recovery/reset',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      username: 'alice',
      recoveryCode: aliceData.recoveryCode,
      password: 'newalicepassword123',
      confirmPassword: 'newalicepassword123'
    }));
    assert.strictEqual(resetAlice.status, 200);
    const resetAliceData = JSON.parse(resetAlice.body);
    assert.strictEqual(resetAliceData.user.username, 'alice');
    assert.ok(resetAliceData.recoveryCode);
    assert.notStrictEqual(resetAliceData.recoveryCode, aliceData.recoveryCode);

    // 13. Tentar usar código antigo invalidado deve falhar
    const resetOldCode = await makeRequest(port, {
      path: '/api/auth/recovery/reset',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      username: 'alice',
      recoveryCode: aliceData.recoveryCode,
      password: 'newalicepassword456',
      confirmPassword: 'newalicepassword456'
    }));
    assert.strictEqual(resetOldCode.status, 401);

    // 14. Autenticar com a nova senha de Alice
    const loginAliceNew = await makeRequest(port, {
      path: '/api/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'alice', password: 'newalicepassword123' }));
    assert.strictEqual(loginAliceNew.status, 200);

    // 15. Auditoria: verificar que operações foram gravadas sem segredos
    const db = getDb();
    const ops = await new Promise((resolve, reject) => {
      db.all('SELECT * FROM operations', [], (err, rows) => err ? reject(err) : resolve(rows || []));
    });
    assert.ok(ops.some(op => op.type === 'secondary-account-creation' && op.target === 'alice'));
    assert.ok(ops.some(op => op.type === 'account-recovery' && op.target === 'alice'));
    for (const op of ops) {
      assert.strictEqual(op.password, undefined);
      assert.strictEqual(op.recovery_code, undefined);
    }
  } finally {
    server.close();
  }
});
