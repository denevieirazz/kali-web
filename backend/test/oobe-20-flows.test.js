process.env.NODE_ENV = 'test';
import test from 'node:test';
import assert from 'node:assert';
import http from 'http';
import childProcess from 'node:child_process';
import { syncBuiltinESMExports } from 'node:module';
import { promisify } from 'node:util';

let forcedWslStatusError = null;

function deterministicWslResult(args = []) {
  if (args[0] === '--status') {
    if (forcedWslStatusError) throw forcedWslStatusError;
    return {
      stdout: 'Default Distribution: kali-linux\nDefault Version: 2\n',
      stderr: '',
    };
  }

  if (args[0] === '-l' && args[1] === '-v') {
    return {
      stdout: '  NAME            STATE           VERSION\n* kali-linux      Running         2\n',
      stderr: '',
    };
  }

  if (args[0] === '--list' && args[1] === '--online') {
    return {
      stdout: [
        'The following is a list of valid distributions that can be installed.',
        'NAME                 FRIENDLY NAME',
        'kali-linux           Kali Linux',
        'Ubuntu               Ubuntu',
        'Ubuntu-24.04         Ubuntu 24.04 LTS',
        'Debian               Debian GNU/Linux',
        'Alpine               Alpine Linux',
      ].join('\n'),
      stderr: '',
    };
  }

  throw new Error(`Unexpected physical WSL command in OOBE contract test: ${args.join(' ')}`);
}

function deterministicExecFile(_file, args, options, callback) {
  if (typeof options === 'function') callback = options;
  queueMicrotask(() => {
    try {
      const result = deterministicWslResult(args);
      callback?.(null, result.stdout, result.stderr);
    } catch (error) {
      callback?.(error, '', '');
    }
  });
  return {
    once() { return this; },
    unref() {},
  };
}

deterministicExecFile[promisify.custom] = async (_file, args) => deterministicWslResult(args);

// OOBE CI validates the provisioning contract, not the physical Windows/WSL host.
// Load only distroManager with a deterministic WSL command boundary, then restore
// the builtin immediately so the rest of the backend keeps its normal dependencies.
const originalExecFile = childProcess.execFile;
childProcess.execFile = deterministicExecFile;
syncBuiltinESMExports();
const distroManager = await import('../src/linuxRuntime/distroManager.js');
childProcess.execFile = originalExecFile;
syncBuiltinESMExports();

const [{ createApp }, { resetLocalDatabase }, { buildInstallCommand }] = await Promise.all([
  import('../src/app.js'),
  import('../src/database/index.js'),
  import('../src/linuxRuntime/packageManager.js'),
]);

const { streamProvisionDistro, getActiveDistro, setActiveDistro } = distroManager;

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

test('OOBE E2E: 20 fluxos completos de validação lógica com fronteira WSL determinística', { concurrency: false }, async () => {
  resetLocalDatabase();
  const app = createApp(0, { environment: { NODE_ENV: 'test' } });
  const { server, port } = await startServer(app);

  try {
    // FLUXO 1: Primeiro boot exige setup.
    const res1 = await makeRequest(port, { path: '/api/setup/status' });
    assert.strictEqual(res1.status, 200, 'Flow 1: status endpoint HTTP 200');
    const json1 = JSON.parse(res1.body);
    assert.strictEqual(json1.setupRequired, true, 'Flow 1: setupRequired deve ser true no boot inicial');

    // FLUXO 2: Catálogo de distros disponível para a Tela 2.
    const res2 = await makeRequest(port, { path: '/api/linux-runtime/distros' });
    assert.strictEqual(res2.status, 200, 'Flow 2: distros endpoint HTTP 200');
    const json2 = JSON.parse(res2.body);
    assert.ok(Array.isArray(json2.online), 'Flow 2: online distros array');
    assert.ok(json2.online.length >= 5, 'Flow 2: pelo menos 5 distros no catálogo');

    // FLUXO 3: Provisionamento SSE termina somente em done: true.
    const events3 = [];
    for await (const ev of streamProvisionDistro('kali-linux', 'existing')) events3.push(ev);
    assert.ok(events3.length >= 3, 'Flow 3: SSE gerou múltiplos eventos');
    assert.strictEqual(events3.at(-1).done, true, 'Flow 3: último evento tem done: true');
    assert.strictEqual(events3.at(-1).progress, 100, 'Flow 3: progresso atinge 100%');

    // FLUXO 4: Conta nova sem senha é rejeitada.
    const res4 = await makeRequest(port, {
      path: '/api/setup/admin', method: 'POST', headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'usuario_sem_senha', displayName: 'Usuario Sem Senha', password: '', confirmPassword: '', allowUpdate: true }));
    assert.strictEqual(res4.status, 400, 'Flow 4: Conta sem senha rejeitada com HTTP 400');
    assert.match(JSON.parse(res4.body).error, /8 caracteres/);

    // FLUXO 5: Criação de administrador com senha válida.
    const strongPassword = 'Senha1234';
    const res5 = await makeRequest(port, {
      path: '/api/setup/admin', method: 'POST', headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'douglas', displayName: 'Douglas Vieira', password: strongPassword, confirmPassword: strongPassword, allowUpdate: true }));
    assert.strictEqual(res5.status, 201, 'Flow 5: Conta com senha segura criada com HTTP 201');
    const json5 = JSON.parse(res5.body);
    assert.ok(json5.token, 'Flow 5: Token JWT emitido');
    assert.ok(json5.recoveryCode, 'Flow 5: Código de recuperação emitido');

    // FLUXO 6: Login imediato com a senha válida.
    const res6 = await makeRequest(port, {
      path: '/api/auth/login', method: 'POST', headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'douglas', password: strongPassword }));
    assert.strictEqual(res6.status, 200, 'Flow 6: Login autenticado com sucesso HTTP 200');

    // FLUXO 7: Atualização para senha de 7 caracteres é rejeitada.
    const res7 = await makeRequest(port, {
      path: '/api/setup/admin', method: 'POST', headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'douglas', displayName: 'Douglas Vieira', password: '1234567', confirmPassword: '1234567', allowUpdate: true }));
    assert.strictEqual(res7.status, 400, 'Flow 7: Senha de 7 caracteres rejeitada com HTTP 400');
    assert.match(JSON.parse(res7.body).error, /8 caracteres/);

    // FLUXO 8: Senha extremamente curta também é rejeitada.
    const res8 = await makeRequest(port, {
      path: '/api/setup/admin', method: 'POST', headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'douglas', displayName: 'Douglas Vieira', password: '123', confirmPassword: '123', allowUpdate: true }));
    assert.strictEqual(res8.status, 400, 'Flow 8: Senha de 3 caracteres rejeitada com HTTP 400');
    assert.match(JSON.parse(res8.body).error, /8 caracteres/);

    // FLUXO 9: Confirmação divergente é rejeitada quando a senha já atende o mínimo.
    const res9 = await makeRequest(port, {
      path: '/api/setup/admin', method: 'POST', headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'douglas', displayName: 'Douglas Vieira', password: 'abcdefgh', confirmPassword: 'abcdefgi', allowUpdate: true }));
    assert.strictEqual(res9.status, 400, 'Flow 9: Senhas divergentes rejeitadas com HTTP 400');
    assert.match(JSON.parse(res9.body).error, /não confere/);

    // FLUXO 10: Provisionamento SSE para Ubuntu (modo new).
    const events10 = [];
    for await (const ev of streamProvisionDistro('ubuntu', 'new')) events10.push(ev);
    assert.ok(events10.length >= 3, 'Flow 10: Ubuntu stream gerou eventos');
    assert.strictEqual(events10.at(-1).done, true, 'Flow 10: Ubuntu stream finalizou em done');

    // FLUXO 11: Provisionamento SSE para Debian (modo reinstall).
    const events11 = [];
    for await (const ev of streamProvisionDistro('debian', 'reinstall')) events11.push(ev);
    assert.ok(events11.length >= 3, 'Flow 11: Debian reinstall gerou eventos');
    assert.strictEqual(events11.at(-1).done, true, 'Flow 11: Debian reinstall finalizou em done');

    // FLUXO 12: Troca e persistência de distro ativa exige a sessão administrativa após o setup.
    setActiveDistro('ubuntu-24.04');
    assert.strictEqual(getActiveDistro(), 'ubuntu-24.04', 'Flow 12: activeDistro é ubuntu-24.04');
    const res12 = await makeRequest(port, {
      path: '/api/linux-runtime/distros/active', method: 'POST', headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${json5.token}`
      }
    }, JSON.stringify({ distro: 'kali-linux' }));
    assert.strictEqual(res12.status, 200, 'Flow 12: setActiveDistro HTTP 200');
    assert.strictEqual(getActiveDistro(), 'kali-linux', 'Flow 12: activeDistro atualizada para kali-linux');

    // FLUXO 13: Estrutura do CloudOS Home.
    const res13 = await makeRequest(port, { path: '/api/linux-runtime/home' });
    assert.strictEqual(res13.status, 200, 'Flow 13: CloudOS Home HTTP 200');
    const json13 = JSON.parse(res13.body);
    assert.ok(json13.home.desktop, 'Flow 13: Home Desktop existe');
    assert.ok(json13.home.downloads, 'Flow 13: Home Downloads existe');
    assert.ok(json13.home.projects, 'Flow 13: Home Projects existe');

    // FLUXO 14: PackageManager multi-distro.
    assert.match(buildInstallCommand('apt', 'firefox'), /apt-get install/);
    assert.match(buildInstallCommand('dnf', 'firefox'), /dnf install/);
    assert.match(buildInstallCommand('pacman', 'firefox'), /pacman -Sy/);
    assert.match(buildInstallCommand('apk', 'firefox'), /apk add/);

    // FLUXO 15: Mesmo autenticado, unregister rejeita nome inseguro.
    const res15 = await makeRequest(port, {
      path: '/api/linux-runtime/distros/unregister', method: 'POST', headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${json5.token}`
      }
    }, JSON.stringify({ distro: 'invalid;rm -rf /' }));
    assert.strictEqual(res15.status, 400, 'Flow 15: Injeção em distro rejeitada com HTTP 400');

    // FLUXO 16: Setup concluído após criação válida.
    const res16 = await makeRequest(port, { path: '/api/setup/status' });
    const json16 = JSON.parse(res16.body);
    assert.strictEqual(json16.setupRequired, false, 'Flow 16: setupRequired é false após configuração');

    // FLUXO 17: Sessão JWT válida.
    const res17 = await makeRequest(port, {
      path: '/api/auth/session', headers: { 'Authorization': `Bearer ${json5.token}` }
    });
    assert.strictEqual(res17.status, 200, 'Flow 17: Sessão válida HTTP 200');
    const json17 = JSON.parse(res17.body);
    assert.strictEqual(json17.authenticated, true);
    assert.strictEqual(json17.user.username, 'douglas');

    // FLUXO 18: Logout confirma o encerramento do lado cliente.
    const res18 = await makeRequest(port, {
      path: '/api/auth/logout', method: 'POST', headers: { 'Authorization': `Bearer ${json5.token}` }
    });
    assert.strictEqual(res18.status, 200, 'Flow 18: Logout HTTP 200');

    // FLUXO 19: Conta secundária exige senha segura e autorização administrativa.
    const secondaryPassword = 'Secundaria5678';
    const res19 = await makeRequest(port, {
      path: '/api/auth/accounts', method: 'POST', headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${json5.token}`
      }
    }, JSON.stringify({ username: 'usuario_secundario', displayName: 'Usuario Secundario', password: secondaryPassword, confirmPassword: secondaryPassword }));
    assert.strictEqual(res19.status, 201, 'Flow 19: Conta secundária criada com HTTP 201');
    const json19 = JSON.parse(res19.body);
    assert.ok(json19.recoveryCode, 'Flow 19: Código de recuperação emitido');
    assert.strictEqual(json19.user.role, 'user', 'Flow 19: Papel do usuário é user');

    // FLUXO 20: Login da conta secundária.
    const res20 = await makeRequest(port, {
      path: '/api/auth/login', method: 'POST', headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ username: 'usuario_secundario', password: secondaryPassword }));
    assert.strictEqual(res20.status, 200, 'Flow 20: Login conta secundária HTTP 200');
    assert.ok(JSON.parse(res20.body).token, 'Flow 20: Sessão autenticada');
  } finally {
    server.close();
  }
});

test('OOBE provisioning permanece fail-closed quando o probe WSL falha', { concurrency: false }, async () => {
  forcedWslStatusError = new Error('simulated WSL unavailable');
  try {
    await assert.rejects(
      async () => {
        for await (const _event of streamProvisionDistro('kali-linux', 'existing')) {
          // Consume until the deterministic status probe fails.
        }
      },
      (error) => {
        assert.strictEqual(error.code, 'WSL_STATUS_FAILED');
        assert.strictEqual(error.statusCode, 503);
        assert.match(error.message, /WSL 2/);
        return true;
      }
    );
  } finally {
    forcedWslStatusError = null;
  }
});
