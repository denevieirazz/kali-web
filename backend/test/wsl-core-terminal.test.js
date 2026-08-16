import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SecureFrameCodec,
  WSL_CORE_PROTOCOL,
  WSL_CORE_PROTECTION,
  buildBootstrapArgs,
  deriveChannelMaterial,
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
