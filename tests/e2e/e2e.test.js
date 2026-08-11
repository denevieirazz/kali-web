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

function requestGet(port, path) {
  return new Promise((resolve, reject) => {
    http.get(`http://127.0.0.1:${port}${path}`, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve({ status: res.statusCode, data }));
    }).on('error', reject);
  });
}

test('E2E: Backend inicializa, serve rotas e provê endpoint runtime', async () => {
  const app = createApp(18080);
  const { server, port } = await startServer(app);

  try {
    const health = await requestGet(port, '/api/health');
    assert.strictEqual(health.status, 200);
    const healthJson = JSON.parse(health.data);
    assert.strictEqual(healthJson.status, 'ok');

    const runtime = await requestGet(port, '/api/runtime');
    assert.strictEqual(runtime.status, 200);
    const runtimeJson = JSON.parse(runtime.data);
    assert.strictEqual(runtimeJson.host, '127.0.0.1');
    assert.strictEqual(runtimeJson.backendPort, 18080);
  } finally {
    server.close();
  }
});
