import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { EventEmitter } from 'node:events';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createApp } from '../src/app.js';
import { createDetachedLauncher, launchDetached } from '../src/wsl/distroService.js';

class FakeChild extends EventEmitter {
  constructor(pid) {
    super();
    this.pid = pid;
    this.unrefCalls = 0;
  }

  unref() {
    this.unrefCalls += 1;
  }
}

function startServer(app) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, '127.0.0.1', () => {
      resolve({ server, port: server.address().port });
    });
    server.on('error', reject);
  });
}

function requestHealth(port) {
  return new Promise((resolve, reject) => {
    const request = http.get(`http://127.0.0.1:${port}/api/health`, (response) => {
      response.resume();
      response.on('end', () => resolve(response.statusCode));
    });
    request.on('error', reject);
  });
}

test('launcher só resolve depois do evento spawn e chama unref uma vez', async () => {
  const child = new FakeChild(4242);
  const launcher = createDetachedLauncher(() => child);
  let settled = false;
  const result = launcher('fixture.exe', ['--safe']).finally(() => { settled = true; });

  await Promise.resolve();
  assert.equal(settled, false);
  assert.equal(child.unrefCalls, 0);

  child.emit('spawn');
  assert.equal(await result, 4242);
  assert.equal(child.unrefCalls, 1);
});

test('falha antes do spawn é assíncrona, genérica e não revela executável nem argumentos', async () => {
  const executable = 'C:\\segredo\\programa-inexistente.exe';
  const argumentSecret = 'CLOUDOS-SENTINEL-ARGUMENT-SECRET';
  const child = new FakeChild(undefined);
  const rawError = Object.assign(new Error(`spawn ${executable} ${argumentSecret}`), {
    code: 'ENOENT',
    path: executable,
    spawnargs: [argumentSecret]
  });
  const launcher = createDetachedLauncher(() => {
    queueMicrotask(() => child.emit('error', rawError));
    return child;
  });

  const result = launcher(executable, [argumentSecret]);
  assert.equal(typeof result?.then, 'function');
  await assert.rejects(result, (error) => {
    assert.equal(error.message, 'Não foi possível iniciar o processo solicitado.');
    assert.equal(error.code, 'PROCESS_LAUNCH_FAILED');
    assert.equal(error.reason, 'EXECUTABLE_NOT_FOUND');
    assert.equal(Object.hasOwn(error, 'cause'), false);
    assert.equal(error.path, undefined);
    assert.equal(error.spawnargs, undefined);
    assert.equal(String(error).includes(executable), false);
    assert.equal(String(error).includes(argumentSecret), false);
    assert.equal(String(error.stack).includes(argumentSecret), false);
    return true;
  });
});

test('exceção síncrona do spawn também vira rejeição sanitizada', async () => {
  const argumentSecret = 'CLOUDOS-SYNC-SPAWN-SECRET';
  const launcher = createDetachedLauncher(() => {
    throw Object.assign(new Error(`raw ${argumentSecret}`), { code: 'EACCES' });
  });

  const result = launcher('blocked.exe', [argumentSecret]);
  assert.equal(typeof result?.then, 'function');
  await assert.rejects(result, (error) => {
    assert.equal(error.code, 'PROCESS_LAUNCH_FAILED');
    assert.equal(error.reason, 'ACCESS_DENIED');
    assert.equal(String(error).includes(argumentSecret), false);
    assert.equal(Object.hasOwn(error, 'cause'), false);
    return true;
  });
});

test('pid inválido após spawn é rejeitado sem confirmar lançamento', async () => {
  const child = new FakeChild(undefined);
  const launcher = createDetachedLauncher(() => child);
  const result = launcher('fixture.exe', []);

  child.emit('spawn');
  await assert.rejects(result, (error) => {
    assert.equal(error.code, 'PROCESS_LAUNCH_FAILED');
    assert.equal(error.reason, 'SPAWN_FAILED');
    return true;
  });
  assert.equal(child.unrefCalls, 0);
});

test('falha de unref é sanitizada e não confirma o PID', async () => {
  const child = new FakeChild(6161);
  child.unref = () => {
    throw new Error('raw unref failure with internal details');
  };
  const launcher = createDetachedLauncher(() => child);
  const result = launcher('fixture.exe', []);

  child.emit('spawn');
  await assert.rejects(result, (error) => {
    assert.equal(error.code, 'PROCESS_LAUNCH_FAILED');
    assert.equal(error.reason, 'SPAWN_FAILED');
    assert.equal(String(error).includes('internal details'), false);
    assert.equal(Object.hasOwn(error, 'cause'), false);
    return true;
  });
});

test('erro tardio permanece tratado depois que o processo foi confirmado', async () => {
  const child = new FakeChild(5151);
  const launcher = createDetachedLauncher(() => child);
  const result = launcher('fixture.exe', []);

  child.emit('spawn');
  assert.equal(await result, 5151);
  assert.doesNotThrow(() => child.emit('error', new Error('late process error')));
});

test('falha real de executável ausente não derruba o backend', async () => {
  const missingExecutable = path.join(
    os.tmpdir(),
    `cloudos-missing-${crypto.randomUUID()}.exe`
  );
  const app = createApp(0);
  const { server, port } = await startServer(app);

  try {
    await assert.rejects(
      launchDetached(missingExecutable, ['CLOUDOS-SENTINEL-NOT-EXPOSED']),
      error => error.code === 'PROCESS_LAUNCH_FAILED'
        && error.reason === 'EXECUTABLE_NOT_FOUND'
    );
    assert.equal(await requestHealth(port), 200);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
