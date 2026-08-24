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
import {
  buildContainedLegacyShellArgs,
  buildWslHostEnvironment,
  WSL_TERMINAL_CONTAINMENT,
  WSL_TERMINAL_SAFE_PATH
} from '../src/terminal/wslTerminalContainment.js';

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
  const args = buildBootstrapArgs('kali-linux', '/tmp/cloudos-core-abc123');
  assert.deepEqual(args.slice(0, 6), ['--distribution', 'kali-linux', '--user', 'root', '--exec', '/usr/bin/env']);
  assert.equal(args.includes('/tmp/cloudos-core-abc123'), true);
  assert.equal(args.includes('core'), true);
  assert.equal(validateLinuxCorePath('/tmp/cloudos-core-abc123'), '/tmp/cloudos-core-abc123');
  assert.throws(() => buildBootstrapArgs('kali-linux;whoami', '/tmp/core'));
  assert.throws(() => validateLinuxCorePath('relative/core'));
  assert.throws(() => validateLinuxCorePath('/tmp/core;whoami'));
});

test('core e fallback WSL compartilham namespace mount+PID fail-closed', () => {
  const core = buildBootstrapArgs('Ubuntu', '/tmp/cloudos-core-safe');
  const shell = buildContainedLegacyShellArgs('Ubuntu');
  for (const args of [core, shell]) {
    const command = args.join('\n');
    assert.match(command, /--mount/);
    assert.match(command, /--pid/);
    assert.match(command, /--fork/);
    assert.match(command, /--kill-child/);
    assert.match(command, /--mount-proc=\/proc/);
    assert.match(command, /--propagation private/);
    assert.match(command, /mount -t tmpfs[^\n]* \/tmp/);
    assert.match(command, /mount -t tmpfs[^\n]* \/run\/user/);
    for (const target of ['/mnt/wslg', '/run/WSL', '/init', '/run/systemd', '/run/dbus']) {
      assert.equal(command.includes(target), true, `missing containment mask ${target}`);
    }
    assert.match(command, /--reuid="\$target_uid"/);
    assert.match(command, /--no-new-privs/);
    assert.match(command, /--bounding-set=-all/);
    assert.match(command, /--seccomp-filter/);
    assert.match(command, /env -i/);
    assert.match(command, /CLOUDOS_TERMINAL_CONTAINMENT_CANARY_FAILED/);
    assert.match(command, /seccomp-not-active/);
    assert.match(command, /interop-handler-enabled/);
    assert.match(command, /\/mnt\/c\/Windows\/System32\/cmd\.exe \/c exit/);
    assert.match(command, /\[ "\$\$" -eq 1 \]/);
  }
  assert.equal(WSL_TERMINAL_CONTAINMENT, 'mount-pid-nointerop-v1');
  assert.equal(WSL_TERMINAL_SAFE_PATH, '/usr/local/bin:/usr/bin:/bin');
});

test('ambiente host do wsl.exe não propaga PATH, WSLENV, display ou segredos', () => {
  const environment = buildWslHostEnvironment({
    SystemRoot: 'C:\\Windows',
    TEMP: 'C:\\Temp',
    USERPROFILE: 'C:\\Users\\test',
    Path: 'C:\\unsafe',
    WSLENV: 'DISPLAY/u:SECRET/u',
    DISPLAY: ':0',
    WAYLAND_DISPLAY: 'wayland-0',
    WSL_INTEROP: '/run/WSL/1_interop',
    CLOUD_TOKEN: 'secret'
  });
  assert.equal(environment.Path, 'C:\\Windows\\System32;C:\\Windows');
  for (const key of ['WSLENV', 'DISPLAY', 'WAYLAND_DISPLAY', 'WSL_INTEROP', 'CLOUD_TOKEN']) {
    assert.equal(Object.hasOwn(environment, key), false, `unsafe host environment key ${key}`);
  }
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
