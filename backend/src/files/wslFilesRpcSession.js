import { spawn } from 'node:child_process';
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import net from 'node:net';
import {
  SecureFrameCodec,
  WSL_CORE_PROTOCOL,
  WSL_CORE_PROTECTION,
  buildBootstrapArgs,
  connectLoopbackWithReadiness,
  deriveChannelMaterial,
  parseBootstrapRecord,
  validateLinuxCorePath,
} from '../terminal/wslCoreAdapter.js';

const WSL_EXE = 'C:\\Windows\\System32\\wsl.exe';
const MAX_FRAME = 1 << 20;
const TAG_BYTES = 16;
const SENSITIVE_ENV = /(?:SECRET|TOKEN|PASSWORD|CREDENTIAL|PRIVATE_KEY|API_KEY|JWT|NONCE)/i;
const DISTRO = /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/;

export class WslFilesRpcError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'WslFilesRpcError';
    this.code = code;
  }
}

function safeEnv() {
  return Object.fromEntries(Object.entries(process.env).filter(([key, value]) => typeof value === 'string' && !SENSITIVE_ENV.test(key)));
}

function validateDistribution(value) {
  if (!DISTRO.test(value || '')) throw new WslFilesRpcError('DISTRO_INVALID', 'Linux distribution is invalid.');
  return value;
}

function encodePlain(value) {
  const body = Buffer.from(JSON.stringify({ v: WSL_CORE_PROTOCOL, ...value }), 'utf8');
  if (!body.length || body.length > MAX_FRAME) throw new WslFilesRpcError('FRAME_LIMIT', 'Frame size is invalid.');
  const header = Buffer.alloc(4);
  header.writeUInt32BE(body.length);
  return Buffer.concat([header, body]);
}

class Reader {
  constructor(socket) {
    this.buffer = Buffer.alloc(0);
    this.error = null;
    this.waiters = new Set();
    socket.on('data', chunk => {
      this.buffer = Buffer.concat([this.buffer, Buffer.from(chunk)]);
      this.#wake();
    });
    const closed = error => {
      this.error = error || new Error('closed');
      this.#wake();
    };
    socket.on('error', closed);
    socket.on('close', () => closed(new Error('closed')));
    socket.on('end', () => closed(new Error('ended')));
  }

  #wake() {
    for (const wake of this.waiters) wake();
    this.waiters.clear();
  }

  async exact(length, timeoutMs = 8000) {
    if (!Number.isInteger(length) || length <= 0 || length > MAX_FRAME + 64) throw new WslFilesRpcError('FRAME_LIMIT', 'Frame size is invalid.');
    const deadline = Date.now() + timeoutMs;
    while (this.buffer.length < length) {
      if (this.error) throw new WslFilesRpcError('CHANNEL_CLOSED', 'Protected channel closed.');
      const remaining = deadline - Date.now();
      if (remaining <= 0) throw new WslFilesRpcError('REQUEST_TIMEOUT', 'Protected channel timed out.');
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          this.waiters.delete(wake);
          reject(new WslFilesRpcError('REQUEST_TIMEOUT', 'Protected channel timed out.'));
        }, remaining);
        const wake = () => {
          clearTimeout(timer);
          resolve();
        };
        this.waiters.add(wake);
      });
    }
    const output = this.buffer.subarray(0, length);
    this.buffer = this.buffer.subarray(length);
    return output;
  }
}

async function writeAll(socket, data) {
  if (socket.destroyed) throw new WslFilesRpcError('CHANNEL_CLOSED', 'Protected channel closed.');
  if (socket.write(data)) return;
  await new Promise((resolve, reject) => {
    const onDrain = () => { socket.off('error', onError); resolve(); };
    const onError = () => { socket.off('drain', onDrain); reject(new WslFilesRpcError('CHANNEL_CLOSED', 'Protected channel write failed.')); };
    socket.once('drain', onDrain);
    socket.once('error', onError);
  });
}

async function readPlain(reader) {
  const header = await reader.exact(4);
  const length = header.readUInt32BE();
  if (!length || length > MAX_FRAME) throw new WslFilesRpcError('FRAME_LIMIT', 'Plain frame size is invalid.');
  const body = await reader.exact(length);
  let value;
  try { value = JSON.parse(body.toString('utf8')); } catch { throw new WslFilesRpcError('FRAME_INVALID', 'Plain frame is invalid.'); }
  if (value?.v !== WSL_CORE_PROTOCOL || typeof value.type !== 'string') throw new WslFilesRpcError('PROTOCOL_VERSION', 'Protocol frame is invalid.');
  return value;
}

async function writePlain(socket, value) {
  await writeAll(socket, encodePlain(value));
}

function proof(secret, role, clientNonce, serverNonce) {
  return createHmac('sha256', secret)
    .update(Buffer.concat([Buffer.from(`cloudos-core/v2/${role}`, 'ascii'), Buffer.from([0]), clientNonce, serverNonce]))
    .digest();
}

class SecureChannel {
  constructor(socket, reader, codec) {
    this.socket = socket;
    this.reader = reader;
    this.codec = codec;
  }
  async write(value) { await writeAll(this.socket, this.codec.encode(value)); }
  async read(timeoutMs = 8000) {
    const header = await this.reader.exact(4, timeoutMs);
    const length = header.readUInt32BE();
    if (length < 8 + TAG_BYTES || length > MAX_FRAME + 8 + TAG_BYTES) throw new WslFilesRpcError('FRAME_LIMIT', 'Protected frame size is invalid.');
    return this.codec.decodeBody(await this.reader.exact(length, timeoutMs));
  }
}

async function authenticate(socket, secret) {
  const reader = new Reader(socket);
  const clientNonce = randomBytes(32);
  let serverNonce = null;
  try {
    await writePlain(socket, { type: 'hello', payload: { clientNonce: clientNonce.toString('base64') } });
    const challenge = await readPlain(reader);
    if (challenge.type !== 'challenge') throw new WslFilesRpcError('AUTH_FAILED', 'Guest challenge is invalid.');
    serverNonce = Buffer.from(challenge.payload?.serverNonce || '', 'base64');
    const candidate = Buffer.from(challenge.payload?.proof || '', 'base64');
    const expected = proof(secret, 'server', clientNonce, serverNonce);
    if (serverNonce.length !== 32 || candidate.length !== expected.length || !timingSafeEqual(candidate, expected)) {
      throw new WslFilesRpcError('AUTH_FAILED', 'Guest proof is invalid.');
    }
    await writePlain(socket, { type: 'proof', payload: { proof: proof(secret, 'client', clientNonce, serverNonce).toString('base64') } });
    const codec = new SecureFrameCodec(deriveChannelMaterial(secret, clientNonce, serverNonce), 'client');
    const channel = new SecureChannel(socket, reader, codec);
    const ready = await channel.read(8000);
    if (ready.type !== 'ready' || ready.payload?.protocol !== WSL_CORE_PROTOCOL || ready.payload?.protection !== WSL_CORE_PROTECTION) {
      throw new WslFilesRpcError('AUTH_FAILED', 'Protected ready frame is invalid.');
    }
    return channel;
  } finally {
    clientNonce.fill(0);
    serverNonce?.fill(0);
  }
}

function readBootstrapLine(stream, child, timeoutMs = 20000) {
  return new Promise((resolve, reject) => {
    let buffer = Buffer.alloc(0);
    const timer = setTimeout(() => finish(new WslFilesRpcError('BOOTSTRAP_TIMEOUT', 'cloudos-core bootstrap timed out.')), timeoutMs);
    const finish = (error, value) => {
      clearTimeout(timer);
      stream.off('data', onData);
      stream.off('error', onError);
      child.off('exit', onExit);
      error ? reject(error) : resolve(value);
    };
    const onError = () => finish(new WslFilesRpcError('BOOTSTRAP_FAILED', 'cloudos-core bootstrap output failed.'));
    const onExit = () => finish(new WslFilesRpcError('BOOTSTRAP_EXITED', 'cloudos-core exited during bootstrap.'));
    const onData = chunk => {
      buffer = Buffer.concat([buffer, Buffer.from(chunk)]);
      if (buffer.length > 8192) return finish(new WslFilesRpcError('BOOTSTRAP_INVALID', 'cloudos-core bootstrap response is too large.'));
      const newline = buffer.indexOf(10);
      if (newline >= 0) finish(null, buffer.subarray(0, newline).toString('utf8').trim());
    };
    stream.on('data', onData);
    stream.once('error', onError);
    child.once('exit', onExit);
  });
}

export async function createWslFilesRpcSession({ distribution, linuxCorePath }) {
  validateDistribution(distribution);
  validateLinuxCorePath(linuxCorePath);
  if (process.env.CLOUDOS_WSL_CORE_FOUNDATION !== '1' || process.env.CLOUDOS_WSL_CORE_FILES !== '1') {
    throw new WslFilesRpcError('FEATURE_DISABLED', 'WSL Files is disabled.');
  }

  const secret = randomBytes(32);
  const child = spawn(WSL_EXE, buildBootstrapArgs(distribution, linuxCorePath), {
    windowsHide: true,
    shell: false,
    stdio: ['pipe', 'pipe', 'pipe'],
    env: safeEnv(),
  });
  let socket = null;
  let channel = null;
  let closed = false;
  let chain = Promise.resolve();

  try {
    await new Promise((resolve, reject) => {
      const encoded = Buffer.from(`${secret.toString('base64')}\n`, 'ascii');
      const fail = error => reject(Object.assign(new WslFilesRpcError('BOOTSTRAP_STDIN_FAILED', 'cloudos-core bootstrap secret delivery failed.'), { cause: error }));
      child.stdin.once('error', fail);
      child.stdin.end(encoded, () => { child.stdin.off('error', fail); encoded.fill(0); resolve(); });
    });
    const record = parseBootstrapRecord(await readBootstrapLine(child.stdout, child));
    const readiness = await connectLoopbackWithReadiness(record.port, { timeoutMs: 8000, attemptTimeoutMs: 600 });
    socket = readiness.socket;
    channel = await authenticate(socket, secret);

    const request = (method, params = null, timeoutMs = 8000) => {
      const execute = async () => {
        if (closed) throw new WslFilesRpcError('CHANNEL_CLOSED', 'WSL Files session is closed.');
        const id = randomBytes(16).toString('hex');
        await channel.write({ type: 'request', id, payload: { method, params } });
        const response = await channel.read(timeoutMs);
        if (response.type !== 'response' || response.id !== id) throw new WslFilesRpcError('FRAME_SEQUENCE', 'Unexpected Files RPC response.');
        if (response.ok !== true) throw new WslFilesRpcError(response.error?.code || 'REQUEST_FAILED', response.error?.message || 'WSL Files request failed.');
        return response.payload;
      };
      const next = chain.then(execute, execute);
      chain = next.catch(() => {});
      return next;
    };

    return {
      protocol: WSL_CORE_PROTOCOL,
      protection: WSL_CORE_PROTECTION,
      distribution,
      request,
      async close() {
        if (closed) return;
        closed = true;
        try {
          const id = randomBytes(16).toString('hex');
          await channel.write({ type: 'request', id, payload: { method: 'shutdown', params: null } });
        } catch {}
        socket?.destroy();
        if (!child.killed && child.exitCode === null) child.kill();
      },
    };
  } catch (error) {
    socket?.destroy();
    if (!child.killed && child.exitCode === null) child.kill();
    if (error instanceof WslFilesRpcError || typeof error?.code === 'string') throw error;
    throw new WslFilesRpcError('FILES_CHANNEL_FAILED', 'WSL Files protected channel failed.');
  } finally {
    secret.fill(0);
  }
}
