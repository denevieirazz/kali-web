import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SecureFrameCodec,
  WSL_CORE_PROTOCOL,
  WSL_CORE_PROTECTION,
  buildBootstrapArgs,
  connectLoopbackWithReadiness,
  deriveChannelMaterial,
  parseBootstrapRecord,
  sanitizeBootstrapStderr,
  validateLinuxCorePath,
  wslCoreTerminalEnabled,
  wslCoreTerminalFallbackEnabled
} from '../src/terminal/wslCoreAdapter.js';

const secret = Buffer.alloc(32, 7);
const clientNonce = Buffer.alloc(32, 8);
const serverNonce = Buffer.alloc(32, 9);

function body(frame) {
  const size = frame.readUInt32BE(0);
  assert.equal(size, frame.length - 4);
  return frame.subarray(4);
}

test('WSL core terminal usa protocolo protegido v2', () => {
  assert.equal(WSL_CORE_PROTOCOL, 2);
  assert.equal(WSL_CORE_PROTECTION, 'aes-256-gcm-seq');
  const material = deriveChannelMaterial(secret, clientNonce, serverNonce);
  const client = new SecureFrameCodec(material, 'client');
  const server = new SecureFrameCodec(material, 'server');
  const decoded = server.decodeBody(body(client.encode({ type: 'request', id: 'one', payload: { method: 'health' } })));
  assert.equal(decoded.type, 'request');
  assert.equal(decoded.id, 'one');
});

test('frame adulterado é rejeitado', () => {
  const material = deriveChannelMaterial(secret, clientNonce, serverNonce);
  const client = new SecureFrameCodec(material, 'client');
  const server = new SecureFrameCodec(material, 'server');
  const protectedBody = Buffer.from(body(client.encode({ type: 'request', id: 'tamper' })));
  protectedBody[protectedBody.length - 1] ^= 0x40;
  assert.throws(() => server.decodeBody(protectedBody), (error) => error?.code === 'FRAME_INTEGRITY');
});

test('replay e sequência fora de ordem são rejeitados', () => {
  const material = deriveChannelMaterial(secret, clientNonce, serverNonce);
  const client = new SecureFrameCodec(material, 'client');
  const frameBody = Buffer.from(body(client.encode({ type: 'request', id: 'seq' })));
  const replayServer = new SecureFrameCodec(material, 'server');
  replayServer.decodeBody(frameBody);
  assert.throws(() => replayServer.decodeBody(frameBody), (error) => error?.code === 'FRAME_SEQUENCE');

  const reordered = Buffer.from(frameBody);
  reordered.writeBigUInt64BE(2n, 0);
  const sequenceServer = new SecureFrameCodec(material, 'server');
  assert.throws(() => sequenceServer.decodeBody(reordered), (error) => error?.code === 'FRAME_SEQUENCE');
});

test('bootstrap usa argv separado e path Linux validado', () => {
  assert.deepEqual(
    buildBootstrapArgs('kali-linux', '/tmp/cloudos-core-abc123'),
    ['--distribution', 'kali-linux', '--exec', '/tmp/cloudos-core-abc123', 'serve']
  );
  assert.equal(validateLinuxCorePath('/tmp/cloudos-core-abc123'), '/tmp/cloudos-core-abc123');
  assert.throws(() => buildBootstrapArgs('kali-linux;whoami', '/tmp/core'));
  assert.throws(() => validateLinuxCorePath('relative/core'));
  assert.throws(() => validateLinuxCorePath('/tmp/core;whoami'));
});

test('fallback do Terminal é explicitamente controlado por feature flags', () => {
  assert.equal(wslCoreTerminalEnabled({ CLOUDOS_WSL_CORE_TERMINAL: '1' }), true);
  assert.equal(wslCoreTerminalEnabled({ CLOUDOS_WSL_CORE_TERMINAL: '0' }), false);
  assert.equal(wslCoreTerminalFallbackEnabled({ CLOUDOS_WSL_CORE_TERMINAL_FALLBACK: '1' }), true);
  assert.equal(wslCoreTerminalFallbackEnabled({}), false);
});

test('linha bootstrap Node valida protocolo porta e PID antes da conexão', () => {
  const parsed = parseBootstrapRecord('{"protocol":2,"port":43123,"pid":321,"distro":{"id":"kali"}}');
  assert.equal(parsed.protocol, 2);
  assert.equal(parsed.port, 43123);
  assert.equal(parsed.pid, 321);
  assert.throws(() => parseBootstrapRecord('{"protocol":2,"port":0,"pid":321}'), (error) => error?.code === 'BOOTSTRAP_INVALID');
  assert.throws(() => parseBootstrapRecord('not-json'), (error) => error?.code === 'BOOTSTRAP_INVALID');
});

test('readiness de loopback repete apenas erro transitório e preserva diagnóstico', async () => {
  let attempts = 0;
  const fakeSocket = { setNoDelay() {}, destroy() {} };
  const result = await connectLoopbackWithReadiness(43123, {
    timeoutMs: 1000,
    attemptTimeoutMs: 100,
    sleep: async () => {},
    connector: async () => {
      attempts += 1;
      if (attempts < 3) {
        const error = new Error('refused');
        error.code = 'ECONNREFUSED';
        throw error;
      }
      return fakeSocket;
    },
    diagnostic: { stage: 'connect-readiness', distribution: 'kali-linux', protocol: 2, corePid: 55 }
  });
  assert.equal(result.socket, fakeSocket);
  assert.equal(result.diagnostic.portAvailable, true);
  assert.equal(result.diagnostic.connectAttempts, 3);
  assert.equal(result.diagnostic.lastSocketCode, 'ECONNREFUSED');
  assert.equal(result.diagnostic.stage, 'connected');
});

test('readiness não repete erro não transitório', async () => {
  let attempts = 0;
  await assert.rejects(
    connectLoopbackWithReadiness(43123, {
      timeoutMs: 1000,
      connector: async () => {
        attempts += 1;
        const error = new Error('access denied');
        error.code = 'EACCES';
        throw error;
      },
      diagnostic: { distribution: 'kali-linux', protocol: 2 }
    }),
    (error) => error?.code === 'CHANNEL_CONNECT_FATAL' && error?.diagnostic?.lastSocketCode === 'EACCES'
  );
  assert.equal(attempts, 1);
});

test('bootstrap encerrado falha antes de nova tentativa de porta', async () => {
  let attempts = 0;
  await assert.rejects(
    connectLoopbackWithReadiness(43123, {
      connector: async () => { attempts += 1; return {}; },
      bootstrapState: { exited: true, exitCode: 17, signal: '', spawnErrorCode: '' },
      diagnostic: { distribution: 'kali-linux', protocol: 2, corePid: 99 },
      getStderr: () => 'safe failure'
    }),
    (error) => error?.code === 'BOOTSTRAP_EXITED'
      && error?.diagnostic?.bootstrapExitCode === 17
      && error?.diagnostic?.stderr === 'safe failure'
      && error?.diagnostic?.portAvailable === false
  );
  assert.equal(attempts, 0);
});

test('stderr diagnóstico remove material com aparência de segredo e controles', () => {
  const candidate = 'AAAA'.repeat(12) + '==';
  const sanitized = sanitizeBootstrapStderr(`\u0000failure ${candidate}\nnext`);
  assert.equal(sanitized.includes(candidate), false);
  assert.equal(sanitized.includes('[redacted]'), true);
  assert.equal(sanitized.includes('\u0000'), false);
});
