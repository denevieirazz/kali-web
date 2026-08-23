process.env.NODE_ENV = 'test';
import test from 'node:test';
import assert from 'node:assert';
import http from 'http';
import { createApp } from '../src/app.js';
import { resetLocalDatabase } from '../src/database/index.js';
import { streamProvisionDistro, getActiveDistro, setActiveDistro } from '../src/linuxRuntime/distroManager.js';
import { detectDistroPackageManager, buildInstallCommand } from '../src/linuxRuntime/packageManager.js';

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

test('OOBE E2E: 20 fluxos completos de validação física e lógica', async () => {
  resetLocalDatabase();
  const app = createApp(0, { environment: { NODE_ENV: 'test' } });
  const { server, port } = await startServer(app);

  try {
    // -------------------------------------------------------------
    // FLUXO 1: Status inicial - Primeiro boot deve exigir setup
    // -------------------------------------------------------------
    const res1 = await makeRequest(port, { path: '/api/setup/status' });
    assert.strictEqual(res1.status, 200, 'Flow 1: status endpoint HTTP 200');
    const json1 = JSON.parse(res1.body);
    assert.strictEqual(json1.setupRequired, true, 'Flow 1: setupRequired deve ser true no boot inicial');

    // -------------------------------------------------------------
    // FLUXO 2: Listagem de distros para a Tela 2
    // -------------------------------------------------------------
    const res2 = await makeRequest(port, { path: '/api/linux-runtime/distros' });
    assert.strictEqual(res2.status, 200, 'Flow 2: distros endpoint HTTP 200');
    const json2 = JSON.parse(res2.body);
    assert.ok(Array.isArray(json2.online), 'Flow 2: online distros array');
    assert.ok(json2.online.length >= 5, 'Flow 2: pelo menos 5 distros no catálogo');

    // -------------------------------------------------------------
    // FLUXO 3: Provisionamento SSE Real (Kali Linux - modo existing)
    // -------------------------------------------------------------
    const events3 = [];
    for await (const ev of streamProvisionDistro('kali-linux', 'existing')) {
      events3.push(ev);
    }
    assert.ok(events3.length >= 3, 'Flow 3: SSE gerou múltiplos eventos');
    assert.strictEqual(events3[events3.length - 1].done, true, 'Flow 3: último evento tem done: true');
    assert.strictEqual(events3[events3.length - 1].progress, 100, 'Flow 3: progresso atinge 100%');

    // -------------------------------------------------------------
    // FLUXO 4: Criação de conta sem senha (acesso direto)
    // -------------------------------------------------------------
    const res4 = await makeRequest(port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      username: 'usuario_sem_senha',
      displayName: 'Usuario Sem Senha',
      password: '',
      confirmPassword: '',
      allowUpdate: true
    }));
    assert.strictEqual(res4.status, 201, 'Flow 4: Conta sem senha criada com sucesso HTTP 201');
    const json4 = JSON.parse(res4.body);
    assert.ok(json4.token, 'Flow 4: Token JWT emitido');

    // -------------------------------------------------------------
    // FLUXO 5: Login imediato com a conta sem senha
    // -------------------------------------------------------------
    const res5 = await makeRequest(port, {
      path: '/api/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'usuario_sem_senha', password: '' }));
    assert.strictEqual(res5.status, 200, 'Flow 5: Login sem senha autenticado com sucesso HTTP 200');

    // -------------------------------------------------------------
    // FLUXO 6: Criação de conta com senha de 4 dígitos ('1234')
    // -------------------------------------------------------------
    const res6 = await makeRequest(port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      username: 'douglas',
      displayName: 'Douglas Vieira',
      password: '1234',
      confirmPassword: '1234',
      allowUpdate: true
    }));
    assert.strictEqual(res6.status, 201, 'Flow 6: Conta 4 dígitos criada com HTTP 201');
    const json6 = JSON.parse(res6.body);
    assert.ok(json6.token, 'Flow 6: Token JWT emitido');

    // -------------------------------------------------------------
    // FLUXO 7: Login com senha de 4 dígitos ('1234')
    // -------------------------------------------------------------
    const res7 = await makeRequest(port, {
      path: '/api/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'douglas', password: '1234' }));
    assert.strictEqual(res7.status, 200, 'Flow 7: Login com 4 dígitos autenticado HTTP 200');

    // -------------------------------------------------------------
    // FLUXO 8: Rejeição com senha < 4 dígitos ('123')
    // -------------------------------------------------------------
    const res8 = await makeRequest(port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      username: 'douglas',
      displayName: 'Douglas Vieira',
      password: '123',
      confirmPassword: '123',
      allowUpdate: true
    }));
    assert.strictEqual(res8.status, 400, 'Flow 8: Senha de 3 caracteres rejeitada com HTTP 400');
    assert.match(JSON.parse(res8.body).error, /4 caracteres/);

    // -------------------------------------------------------------
    // FLUXO 9: Rejeição quando confirmação não confere
    // -------------------------------------------------------------
    const res9 = await makeRequest(port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      username: 'douglas',
      displayName: 'Douglas Vieira',
      password: '1234',
      confirmPassword: '9999',
      allowUpdate: true
    }));
    assert.strictEqual(res9.status, 400, 'Flow 9: Senhas divergentes rejeitadas com HTTP 400');
    assert.match(JSON.parse(res9.body).error, /não confere/);

    // -------------------------------------------------------------
    // FLUXO 10: Provisionamento SSE para Ubuntu (modo new)
    // -------------------------------------------------------------
    const events10 = [];
    for await (const ev of streamProvisionDistro('ubuntu', 'new')) {
      events10.push(ev);
    }
    assert.ok(events10.length >= 3, 'Flow 10: Ubuntu stream gerou eventos');
    assert.strictEqual(events10[events10.length - 1].done, true, 'Flow 10: Ubuntu stream finalizou em done');

    // -------------------------------------------------------------
    // FLUXO 11: Provisionamento SSE para Debian (modo reinstall)
    // -------------------------------------------------------------
    const events11 = [];
    for await (const ev of streamProvisionDistro('debian', 'reinstall')) {
      events11.push(ev);
    }
    assert.ok(events11.length >= 3, 'Flow 11: Debian reinstall gerou eventos');
    assert.strictEqual(events11[events11.length - 1].done, true, 'Flow 11: Debian reinstall finalizou em done');

    // -------------------------------------------------------------
    // FLUXO 12: Troca e persistência de distro ativa
    // -------------------------------------------------------------
    setActiveDistro('ubuntu-24.04');
    assert.strictEqual(getActiveDistro(), 'ubuntu-24.04', 'Flow 12: activeDistro é ubuntu-24.04');

    const res12 = await makeRequest(port, {
      path: '/api/linux-runtime/distros/active',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ distro: 'kali-linux' }));
    assert.strictEqual(res12.status, 200, 'Flow 12: setActiveDistro HTTP 200');
    assert.strictEqual(getActiveDistro(), 'kali-linux', 'Flow 12: activeDistro atualizada para kali-linux');

    // -------------------------------------------------------------
    // FLUXO 13: Estrutura do CloudOS Home
    // -------------------------------------------------------------
    const res13 = await makeRequest(port, { path: '/api/linux-runtime/home' });
    assert.strictEqual(res13.status, 200, 'Flow 13: CloudOS Home HTTP 200');
    const json13 = JSON.parse(res13.body);
    assert.ok(json13.home.desktop, 'Flow 13: Home Desktop existe');
    assert.ok(json13.home.downloads, 'Flow 13: Home Downloads existe');
    assert.ok(json13.home.projects, 'Flow 13: Home Projects existe');

    // -------------------------------------------------------------
    // FLUXO 14: PackageManager - Abstração Multi-Distro (apt / dnf / pacman / apk)
    // -------------------------------------------------------------
    const aptCmd = buildInstallCommand('apt', 'firefox');
    assert.match(aptCmd, /apt-get install/);

    const dnfCmd = buildInstallCommand('dnf', 'firefox');
    assert.match(dnfCmd, /dnf install/);

    const pacmanCmd = buildInstallCommand('pacman', 'firefox');
    assert.match(pacmanCmd, /pacman -Sy/);

    const apkCmd = buildInstallCommand('apk', 'firefox');
    assert.match(apkCmd, /apk add/);

    // -------------------------------------------------------------
    // FLUXO 15: Unregister endpoint com validação de nome seguro
    // -------------------------------------------------------------
    const res15 = await makeRequest(port, {
      path: '/api/linux-runtime/distros/unregister',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ distro: 'invalid;rm -rf /' }));
    assert.strictEqual(res15.status, 400, 'Flow 15: Injeção em distro rejeitada com HTTP 400');

    // -------------------------------------------------------------
    // FLUXO 16: Setup Status agora reporta setupRequired: false
    // -------------------------------------------------------------
    const res16 = await makeRequest(port, { path: '/api/setup/status' });
    const json16 = JSON.parse(res16.body);
    assert.strictEqual(json16.setupRequired, false, 'Flow 16: setupRequired é false após configuração');

    // -------------------------------------------------------------
    // FLUXO 17: Verificação de Sessão JWT Ativa
    // -------------------------------------------------------------
    const res17 = await makeRequest(port, {
      path: '/api/auth/session',
      headers: { 'Authorization': `Bearer ${json6.token}` }
    });
    assert.strictEqual(res17.status, 200, 'Flow 17: Sessão válida HTTP 200');
    const json17 = JSON.parse(res17.body);
    assert.strictEqual(json17.authenticated, true);
    assert.strictEqual(json17.user.username, 'douglas');

    // -------------------------------------------------------------
    // FLUXO 18: Logout revoga acesso à sessão
    // -------------------------------------------------------------
    const res18 = await makeRequest(port, {
      path: '/api/auth/logout',
      method: 'POST',
      headers: { 'Authorization': `Bearer ${json6.token}` }
    });
    assert.strictEqual(res18.status, 200, 'Flow 18: Logout HTTP 200');

    // -------------------------------------------------------------
    // FLUXO 19: Criação de conta secundária após setup
    // -------------------------------------------------------------
    const res19 = await makeRequest(port, {
      path: '/api/auth/accounts',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      username: 'usuario_secundario',
      displayName: 'Usuario Secundario',
      password: '5678',
      confirmPassword: '5678'
    }));
    assert.strictEqual(res19.status, 201, 'Flow 19: Conta secundária criada com HTTP 201');
    const json19 = JSON.parse(res19.body);
    assert.ok(json19.recoveryCode, 'Flow 19: Código de recuperação emitido');
    assert.strictEqual(json19.user.role, 'user', 'Flow 19: Papel do usuário é user');

    // -------------------------------------------------------------
    // FLUXO 20: Login com a conta secundária ('5678')
    // -------------------------------------------------------------
    const res20 = await makeRequest(port, {
      path: '/api/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'usuario_secundario', password: '5678' }));
    assert.strictEqual(res20.status, 200, 'Flow 20: Login conta secundária HTTP 200');
    assert.ok(JSON.parse(res20.body).token, 'Flow 20: Sessão autenticada');

  } finally {
    server.close();
  }
});
