import test from 'node:test';
import assert from 'node:assert';
import http from 'http';
import { createApp } from '../../backend/src/app.js';

function startServer(app) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, '127.0.0.1', () => {
      resolve({ server, port: server.address().port });
    });
    server.on('error', reject);
  });
}

function requestJson(port, path, method = 'GET', body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const dataString = body ? JSON.stringify(body) : null;
    const req = http.request(
      `http://127.0.0.1:${port}${path}`,
      {
        method,
        headers: {
          'Content-Type': 'application/json',
          ...(dataString ? { 'Content-Length': Buffer.byteLength(dataString) } : {}),
          ...headers,
        },
      },
      (res) => {
        let raw = '';
        res.on('data', (chunk) => (raw += chunk));
        res.on('end', () => {
          let json = null;
          try {
            json = JSON.parse(raw);
          } catch {}
          resolve({ status: res.statusCode, headers: res.headers, data: json, raw });
        });
      }
    );
    req.on('error', reject);
    if (dataString) req.write(dataString);
    req.end();
  });
}

test('1. CloudOS Backend & Health Check — Inicia e responde com status 200 OK sem erros', async () => {
  const app = createApp(18080);
  const { server, port } = await startServer(app);
  try {
    const res = await requestJson(port, '/api/health');
    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.data.status, 'ok');
  } finally {
    server.close();
  }
});

test('2. Dynamic Runtime Endpoint — Retorna host e portas isoladas em 127.0.0.1', async () => {
  const app = createApp(18080);
  const { server, port } = await startServer(app);
  try {
    const res = await requestJson(port, '/api/runtime');
    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.data.host, '127.0.0.1');
    assert.strictEqual(res.data.backendPort, 18080);
    assert.strictEqual(res.data.apiBase, 'http://127.0.0.1:18080');
    assert.strictEqual(res.data.webSocketBase, 'ws://127.0.0.1:18080');
  } finally {
    server.close();
  }
});

test('3. Setup & Auth Flow — Primeiro acesso cria admin e autentica token JWT', async () => {
  const app = createApp(18080);
  const { server, port } = await startServer(app);
  try {
    // Check initial status
    const statusRes = await requestJson(port, '/api/setup/status');
    assert.strictEqual(statusRes.status, 200);

    // Create admin account
    const uniqueUser = `testadmin_${Date.now()}`;
    const createRes = await requestJson(port, '/api/setup/admin', 'POST', {
      username: uniqueUser,
      password: 'password123',
      confirmPassword: 'password123',
    });

    if (createRes.status === 201) {
      assert.strictEqual(createRes.data.user.username, uniqueUser);
      assert.ok(createRes.data.token);

      // Verify token access to protected metrics
      const metricsRes = await requestJson(port, '/api/system/metrics', 'GET', null, {
        Authorization: `Bearer ${createRes.data.token}`,
      });
      assert.strictEqual(metricsRes.status, 200);
      assert.ok(metricsRes.data.cpu);
      assert.ok(metricsRes.data.memory);
    } else {
      // Admin already exists in local DB
      assert.strictEqual(createRes.status, 409);
    }
  } finally {
    server.close();
  }
});

test('4. Security: CORS & Origin Validation — Rejeita origens externas não permitidas', async () => {
  const app = createApp(18080);
  const { server, port } = await startServer(app);
  try {
    const res = await requestJson(port, '/api/health', 'GET', null, {
      Origin: 'http://malicious-site.com',
    });
    assert.strictEqual(res.status, 500);
  } finally {
    server.close();
  }
});

test('5. Security: Payload Limits — Rejeita payloads JSON excessivos com 413', async () => {
  const app = createApp(18080);
  const { server, port } = await startServer(app);
  try {
    const hugeString = 'x'.repeat(6 * 1024 * 1024);
    const res = await requestJson(port, '/api/auth/login', 'POST', { data: hugeString });
    assert.strictEqual(res.status, 413);
  } finally {
    server.close();
  }
});

test('6. WSL Service Isolation — Parsing e detecção segura com validação de allowlist', async () => {
  const { parseWslListOutput, validateAllowlisted } = await import('../../backend/src/wsl/distroService.js');

  const mockOutput = `  NAME                   STATE           VERSION\n* Ubuntu                 Running         2\n  kali-linux             Stopped         2\n`;
  const parsed = parseWslListOutput(mockOutput);

  assert.strictEqual(parsed.length, 2);
  assert.strictEqual(parsed[0].name, 'Ubuntu');
  assert.strictEqual(parsed[0].isDefault, true);
  assert.strictEqual(parsed[1].name, 'kali-linux');

  // Allowlist security check
  assert.strictEqual(validateAllowlisted('kali-linux && calc.exe'), false);
  assert.strictEqual(validateAllowlisted('../../../etc/passwd'), false);
  assert.strictEqual(validateAllowlisted('; rm -rf /'), false);
});
