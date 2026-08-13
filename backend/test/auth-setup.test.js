import test from 'node:test';
import assert from 'node:assert';
import http from 'http';
import { createApp } from '../src/app.js';
import { resetLocalDatabase } from '../src/database/index.js';

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

test('Setup e Auth: Teste completo de primeiro acesso e autenticação', async () => {
  resetLocalDatabase();
  const app = createApp(0);
  const { server, port } = await startServer(app);

  try {
    // 1. Primeiro Acesso: GET /api/setup/status deve retornar setupRequired: true
    const status1 = await makeRequest(port, { path: '/api/setup/status' });
    assert.strictEqual(status1.status, 200);
    const jsonStatus1 = JSON.parse(status1.body);
    assert.strictEqual(jsonStatus1.setupRequired, true);

    // 2. Senha e confirmação diferentes devem ser rejeitados com 400
    const errMismatch = await makeRequest(port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'adminuser', password: 'password123', confirmPassword: 'differentpassword' }));
    assert.strictEqual(errMismatch.status, 400);

    // 3. Senha inválida (curta) deve ser rejeitada com 400
    const errShort = await makeRequest(port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'adminuser', password: '123', confirmPassword: '123' }));
    assert.strictEqual(errShort.status, 400);

    // 4. Criação do Administrador com sucesso (201 Created)
    const createRes = await makeRequest(port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'adminuser', password: 'securepassword123', confirmPassword: 'securepassword123' }));
    assert.strictEqual(createRes.status, 201);
    const createJson = JSON.parse(createRes.body);
    assert.ok(createJson.token);
    assert.strictEqual(createJson.user.username, 'adminuser');
    assert.strictEqual(createJson.user.role, 'admin');

    // Nenhuma senha deve ser retornada no JSON da API
    assert.strictEqual(createJson.user.password, undefined);
    assert.strictEqual(createJson.user.password_hash, undefined);

    // 5. Segunda criação deve ser rejeitada com HTTP 409 Conflict
    const createRes2 = await makeRequest(port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'adminuser2', password: 'securepassword123', confirmPassword: 'securepassword123' }));
    assert.strictEqual(createRes2.status, 409);

    // GET /api/setup/status agora deve retornar setupRequired: false
    const status2 = await makeRequest(port, { path: '/api/setup/status' });
    const jsonStatus2 = JSON.parse(status2.body);
    assert.strictEqual(jsonStatus2.setupRequired, false);

    // 6. Login com senha incorreta deve ser rejeitado com 401
    const badLogin = await makeRequest(port, {
      path: '/api/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'adminuser', password: 'wrongpassword' }));
    assert.strictEqual(badLogin.status, 401);

    // 7. Login correto deve retornar 200 OK e token válido
    const okLogin = await makeRequest(port, {
      path: '/api/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'adminuser', password: 'securepassword123' }));
    assert.strictEqual(okLogin.status, 200);
    const okLoginJson = JSON.parse(okLogin.body);
    assert.ok(okLoginJson.token);

    // 8. Restauração de Sessão via GET /api/auth/session
    const sessRes = await makeRequest(port, {
      path: '/api/auth/session',
      headers: { 'Authorization': `Bearer ${okLoginJson.token}` }
    });
    assert.strictEqual(sessRes.status, 200);
    const sessJson = JSON.parse(sessRes.body);
    assert.strictEqual(sessJson.authenticated, true);
    assert.strictEqual(sessJson.user.username, 'adminuser');

    // 9. Logout via POST /api/auth/logout
    const logoutRes = await makeRequest(port, {
      path: '/api/auth/logout',
      method: 'POST',
      headers: { 'Authorization': `Bearer ${okLoginJson.token}` }
    });
    assert.strictEqual(logoutRes.status, 200);

    // 10. Reset exige admin e revoga o token ao remover a conta correspondente
    const resetRes = await makeRequest(port, {
      path: '/api/setup/reset',
      method: 'POST',
      headers: { 'Authorization': `Bearer ${okLoginJson.token}`, 'Content-Type': 'application/json' }
    }, JSON.stringify({ confirm: true }));
    assert.strictEqual(resetRes.status, 200);

    const revokedSession = await makeRequest(port, {
      path: '/api/auth/session',
      headers: { 'Authorization': `Bearer ${okLoginJson.token}` }
    });
    assert.strictEqual(revokedSession.status, 403);

  } finally {
    server.close();
  }
});
