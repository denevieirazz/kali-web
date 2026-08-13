import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  connectHostLease,
  createHostLeaseHandshake,
  HOST_LEASE_ACCEPTED_TYPE,
  HOST_LEASE_HANDSHAKE_TYPE,
  HOST_LEASE_PROTOCOL,
  parseHostLeaseAcknowledgement,
  readHostLeaseConfig
} from '../src/runtime/hostLease.js';

const validEnvironment = Object.freeze({
  CLOUDOS_NATIVE_HOST: '1',
  CLOUDOS_HOST_LEASE_PIPE: `CloudOS.Runtime.Lease.${'A'.repeat(48)}`,
  CLOUDOS_HOST_LEASE_TOKEN: Buffer.alloc(48, 7).toString('base64'),
  CLOUDOS_RUN_ID: '4dbfc480-bf7d-4fa6-b10f-1390434603d2',
  CLOUDOS_PARENT_PID: '4242'
});
const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

test('lease não altera o modo web/desenvolvimento', () => {
  assert.equal(readHostLeaseConfig({}), null);
  assert.equal(readHostLeaseConfig({ CLOUDOS_NATIVE_HOST: '0' }), null);
});

test('modo nativo exige pipe, token, sessão e PID válidos', () => {
  const config = readHostLeaseConfig(validEnvironment);
  assert.equal(config.pipeName, validEnvironment.CLOUDOS_HOST_LEASE_PIPE);
  assert.equal(config.runId, validEnvironment.CLOUDOS_RUN_ID);
  assert.equal(config.hostPid, 4242);
  assert.ok(Object.isFrozen(config));

  for (const field of [
    'CLOUDOS_HOST_LEASE_PIPE',
    'CLOUDOS_HOST_LEASE_TOKEN',
    'CLOUDOS_RUN_ID',
    'CLOUDOS_PARENT_PID'
  ]) {
    const invalid = { ...validEnvironment, [field]: '' };
    assert.throws(() => readHostLeaseConfig(invalid));
  }
});

test('handshake inclui protocolo, identidade e token sem campos extras', () => {
  const config = readHostLeaseConfig(validEnvironment);
  const line = createHostLeaseHandshake(config, 7331);
  assert.ok(line.endsWith('\n'));
  assert.deepEqual(JSON.parse(line), {
    protocol: HOST_LEASE_PROTOCOL,
    type: HOST_LEASE_HANDSHAKE_TYPE,
    pid: 7331,
    runId: validEnvironment.CLOUDOS_RUN_ID,
    token: validEnvironment.CLOUDOS_HOST_LEASE_TOKEN
  });
});

test('confirmação da lease é vinculada ao runId e PID do host', () => {
  const config = readHostLeaseConfig(validEnvironment);
  const valid = JSON.stringify({
    protocol: HOST_LEASE_PROTOCOL,
    type: HOST_LEASE_ACCEPTED_TYPE,
    runId: config.runId,
    hostPid: config.hostPid
  });
  assert.equal(parseHostLeaseAcknowledgement(valid, config).hostPid, 4242);
  assert.throws(() => parseHostLeaseAcknowledgement(valid.replace('4242', '4243'), config));
  assert.throws(() => parseHostLeaseAcknowledgement('{', config));
});

test('fechamento do pipe autenticado é reportado uma única vez', {
  skip: process.platform !== 'win32'
}, async () => {
  const suffix = `${process.pid.toString(16).toUpperCase().padStart(8, '0')}${'B'.repeat(40)}`;
  const environment = {
    ...validEnvironment,
    CLOUDOS_HOST_LEASE_PIPE: `CloudOS.Runtime.Lease.${suffix}`,
    CLOUDOS_PARENT_PID: String(process.pid)
  };
  const config = readHostLeaseConfig(environment);
  const path = `\\\\.\\pipe\\${config.pipeName}`;
  let serverSocket;
  const server = net.createServer((socket) => {
    serverSocket = socket;
    let request = '';
    socket.setEncoding('utf8');
    socket.on('data', (chunk) => {
      request += chunk;
      const newline = request.indexOf('\n');
      if (newline < 0) return;
      const handshake = JSON.parse(request.slice(0, newline));
      assert.equal(handshake.pid, process.pid);
      assert.equal(handshake.token, config.token);
      socket.write(`${JSON.stringify({
        protocol: HOST_LEASE_PROTOCOL,
        type: HOST_LEASE_ACCEPTED_TYPE,
        runId: config.runId,
        hostPid: config.hostPid
      })}\n`);
    });
  });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(path, resolve);
  });

  let lostCount = 0;
  let resolveLost;
  const lost = new Promise((resolve) => { resolveLost = resolve; });
  try {
    await connectHostLease(config, {
      onLost: () => {
        lostCount += 1;
        resolveLost();
      }
    });
    serverSocket.destroy();
    await lost;
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(lostCount, 1);
  } finally {
    serverSocket?.destroy();
    await new Promise((resolve) => server.close(resolve));
  }
});

test('backend nativo encerra quando a lease do Host desaparece', {
  skip: process.platform !== 'win32',
  timeout: 15_000
}, async () => {
  const suffix = `${process.pid.toString(16).toUpperCase().padStart(8, '0')}${'C'.repeat(40)}`;
  const pipeName = `CloudOS.Runtime.Lease.${suffix}`;
  const pipe = `\\\\.\\pipe\\${pipeName}`;
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-host-lease-'));
  const runtimeDirectory = path.join(temporaryRoot, 'runtime');
  const dataDirectory = path.join(temporaryRoot, 'data');
  const token = Buffer.alloc(48, 11).toString('base64');
  const runId = '62afbce6-1877-4dbb-97d1-35a37ebf46c2';
  let serverSocket;
  let child;
  let output = '';
  let resolveHandshake;
  const handshakeReceived = new Promise((resolve) => { resolveHandshake = resolve; });
  const server = net.createServer((socket) => {
    serverSocket = socket;
    let request = '';
    socket.setEncoding('utf8');
    socket.on('data', (chunk) => {
      request += chunk;
      const newline = request.indexOf('\n');
      if (newline < 0) return;
      const handshake = JSON.parse(request.slice(0, newline));
      assert.equal(handshake.pid, child.pid);
      assert.equal(handshake.runId, runId);
      assert.equal(handshake.token, token);
      socket.write(`${JSON.stringify({
        protocol: HOST_LEASE_PROTOCOL,
        type: HOST_LEASE_ACCEPTED_TYPE,
        runId,
        hostPid: process.pid
      })}\n`);
      resolveHandshake();
    });
  });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(pipe, resolve);
  });

  try {
    child = spawn(process.execPath, [path.join(repositoryRoot, 'backend', 'src', 'server.js')], {
      cwd: repositoryRoot,
      shell: false,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: {
        ...process.env,
        NODE_ENV: 'test',
        PORT: '0',
        HOST: '127.0.0.1',
        CLOUDOS_NATIVE_HOST: '1',
        CLOUDOS_HOST_LEASE_PIPE: pipeName,
        CLOUDOS_HOST_LEASE_TOKEN: token,
        CLOUDOS_RUN_ID: runId,
        CLOUDOS_PARENT_PID: String(process.pid),
        CLOUDOS_RUNTIME_DIR: runtimeDirectory,
        CLOUDOS_DATA_DIR: dataDirectory,
        CLOUDOS_FRONTEND_DIST: path.join(repositoryRoot, 'frontend', 'dist')
      }
    });
    child.stdout.on('data', (chunk) => { output += chunk; });
    child.stderr.on('data', (chunk) => { output += chunk; });

    await handshakeReceived;
    const runtimeFile = path.join(runtimeDirectory, 'backend-port.json');
    const deadline = Date.now() + 5000;
    while (!fs.existsSync(runtimeFile) && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    assert.ok(fs.existsSync(runtimeFile), `Manifesto do runtime não foi criado.\n${output}`);
    const manifest = JSON.parse(fs.readFileSync(runtimeFile, 'utf8'));
    assert.equal(manifest.pid, child.pid);
    assert.equal(manifest.leaseProtocol, HOST_LEASE_PROTOCOL);

    const exited = new Promise((resolve) => child.once('exit', (code, signal) => resolve({ code, signal })));
    serverSocket.destroy();
    const result = await exited;
    assert.deepEqual(result, { code: 0, signal: null }, output);
    assert.equal(fs.existsSync(runtimeFile), false);
  } finally {
    if (child && child.exitCode === null) child.kill();
    serverSocket?.destroy();
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
});
