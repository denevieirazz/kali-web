import { spawn } from 'node:child_process';
import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import net from 'node:net';

export const WSL_CORE_PROTOCOL = 2;
export const WSL_CORE_PROTECTION = 'aes-256-gcm-seq';
const MAX = 1 << 20;
const TAG = 16;
const WSL_EXE = 'C:\\Windows\\System32\\wsl.exe';
const DISTRO = /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/;
const LINUX_PATH = /^\/(?:[A-Za-z0-9._+@%=-]+\/)*[A-Za-z0-9._+@%=-]+$/;
const SENSITIVE = /(?:SECRET|TOKEN|PASSWORD|CREDENTIAL|PRIVATE_KEY|API_KEY|JWT|NONCE)/i;

export class WslCoreAdapterError extends Error {
  constructor(code, message) { super(message); this.name = 'WslCoreAdapterError'; this.code = code; }
}

class Reader {
  constructor(stream) {
    this.buffer = Buffer.alloc(0); this.error = null; this.wake = null;
    stream.on('data', chunk => { this.buffer = Buffer.concat([this.buffer, Buffer.from(chunk)]); this.#notify(); });
    const closed = () => { if (!this.error) this.error = new Error('closed'); this.#notify(); };
    stream.on('error', error => { this.error = error; this.#notify(); });
    stream.on('end', closed); stream.on('close', closed);
  }
  #notify() { const wake = this.wake; this.wake = null; wake?.(); }
  async exact(length, timeoutMs = 10000) {
    if (!Number.isInteger(length) || length <= 0 || length > MAX + 64) throw new WslCoreAdapterError('FRAME_LIMIT', 'Invalid frame length.');
    const until = Date.now() + timeoutMs;
    while (this.buffer.length < length) {
      if (this.error) throw new WslCoreAdapterError('CHANNEL_CLOSED', 'Protected channel closed.');
      const left = until - Date.now();
      if (left <= 0) throw new WslCoreAdapterError('CHANNEL_TIMEOUT', 'Protected channel timed out.');
      await new Promise((resolve, reject) => {
        const wake = () => { clearTimeout(timer); resolve(); };
        const timer = setTimeout(() => { if (this.wake === wake) this.wake = null; reject(new WslCoreAdapterError('CHANNEL_TIMEOUT', 'Protected channel timed out.')); }, left);
        this.wake = wake;
      });
    }
    const out = this.buffer.subarray(0, length); this.buffer = this.buffer.subarray(length); return out;
  }
}

const u64 = value => { const b = Buffer.alloc(8); b.writeBigUInt64BE(value); return b; };
const mac = (key, data) => createHmac('sha256', key).update(data).digest();
const nonce = (prefix, seq) => Buffer.concat([prefix, u64(seq)]);
const aad = (dir, seq) => Buffer.concat([Buffer.from(`cloudos-core/v2/secure/${dir}`, 'ascii'), Buffer.from([0]), u64(seq)]);

function expand(prk, info, length) {
  const infoBytes = Buffer.from(info, 'ascii'); const blocks = []; let prev = Buffer.alloc(0); let n = 0;
  for (let counter = 1; n < length; counter++) {
    if (counter > 255) throw new WslCoreAdapterError('CRYPTO_CONFIG', 'HKDF output is invalid.');
    prev = mac(prk, Buffer.concat([prev, infoBytes, Buffer.from([counter])])); blocks.push(prev); n += prev.length;
  }
  return Buffer.concat(blocks).subarray(0, length);
}

export function deriveChannelMaterial(secret, clientNonce, serverNonce) {
  if (secret.length !== 32 || clientNonce.length !== 32 || serverNonce.length !== 32) throw new WslCoreAdapterError('AUTH_FAILED', 'Invalid channel material.');
  const salt = createHash('sha256').update(Buffer.concat([Buffer.from('cloudos-core/v2/hkdf-salt', 'ascii'), Buffer.from([0]), clientNonce, serverNonce])).digest();
  const prk = mac(salt, secret);
  return {
    c2sKey: expand(prk, 'cloudos-core/v2/c2s/key', 32), s2cKey: expand(prk, 'cloudos-core/v2/s2c/key', 32),
    c2sPrefix: expand(prk, 'cloudos-core/v2/c2s/nonce', 4), s2cPrefix: expand(prk, 'cloudos-core/v2/s2c/nonce', 4)
  };
}

const proof = (secret, role, clientNonce, serverNonce) => mac(secret, Buffer.concat([Buffer.from(`cloudos-core/v2/${role}`, 'ascii'), Buffer.from([0]), clientNonce, serverNonce]));
const envelope = value => ({ v: WSL_CORE_PROTOCOL, ...value });
function parse(data) {
  let value; try { value = JSON.parse(data.toString('utf8')); } catch { throw new WslCoreAdapterError('FRAME_INVALID', 'Protocol frame is invalid.'); }
  if (value?.v !== WSL_CORE_PROTOCOL || typeof value?.type !== 'string' || !value.type) throw new WslCoreAdapterError('PROTOCOL_VERSION', 'Protocol frame version/type is invalid.');
  return value;
}

export class SecureFrameCodec {
  constructor(material, side = 'client') {
    if (!['client','server'].includes(side)) throw new TypeError('Invalid secure channel side.');
    this.readKey = side === 'client' ? material.s2cKey : material.c2sKey; this.writeKey = side === 'client' ? material.c2sKey : material.s2cKey;
    this.readPrefix = side === 'client' ? material.s2cPrefix : material.c2sPrefix; this.writePrefix = side === 'client' ? material.c2sPrefix : material.s2cPrefix;
    this.readLabel = side === 'client' ? 's2c' : 'c2s'; this.writeLabel = side === 'client' ? 'c2s' : 's2c'; this.readSequence = 0n; this.writeSequence = 0n;
  }
  encode(value) {
    const seq = this.writeSequence + 1n; const plain = Buffer.from(JSON.stringify(envelope(value)));
    if (!plain.length || plain.length > MAX) throw new WslCoreAdapterError('FRAME_LIMIT', 'Protocol frame size is invalid.');
    const cipher = createCipheriv('aes-256-gcm', this.writeKey, nonce(this.writePrefix, seq), { authTagLength: TAG }); cipher.setAAD(aad(this.writeLabel, seq));
    const body = Buffer.concat([u64(seq), cipher.update(plain), cipher.final(), cipher.getAuthTag()]); const header = Buffer.alloc(4); header.writeUInt32BE(body.length); this.writeSequence = seq;
    return Buffer.concat([header, body]);
  }
  decodeBody(body) {
    if (body.length < 8 + TAG || body.length > MAX + 8 + TAG) throw new WslCoreAdapterError('FRAME_LIMIT', 'Protected frame size is invalid.');
    const seq = body.readBigUInt64BE(0); if (seq !== this.readSequence + 1n) throw new WslCoreAdapterError('FRAME_SEQUENCE', 'Protected frame sequence is invalid.');
    const decipher = createDecipheriv('aes-256-gcm', this.readKey, nonce(this.readPrefix, seq), { authTagLength: TAG }); decipher.setAAD(aad(this.readLabel, seq)); decipher.setAuthTag(body.subarray(-TAG));
    let plain; try { plain = Buffer.concat([decipher.update(body.subarray(8, -TAG)), decipher.final()]); } catch { throw new WslCoreAdapterError('FRAME_INTEGRITY', 'Protected frame authentication failed.'); }
    const value = parse(plain); this.readSequence = seq; return value;
  }
}

async function write(socket, data) {
  if (socket.destroyed) throw new WslCoreAdapterError('CHANNEL_CLOSED', 'Protected channel is closed.');
  if (socket.write(data)) return;
  await new Promise((resolve, reject) => { const done = () => { socket.off('error', fail); resolve(); }; const fail = () => { socket.off('drain', done); reject(new WslCoreAdapterError('CHANNEL_CLOSED', 'Protected channel write failed.')); }; socket.once('drain', done); socket.once('error', fail); });
}
async function writePlain(socket, value) { const body = Buffer.from(JSON.stringify(envelope(value))); const h = Buffer.alloc(4); h.writeUInt32BE(body.length); await write(socket, Buffer.concat([h, body])); }
async function readPlain(reader) { const h = await reader.exact(4); const n = h.readUInt32BE(); if (!n || n > MAX) throw new WslCoreAdapterError('FRAME_LIMIT', 'Protocol frame size is invalid.'); return parse(await reader.exact(n)); }

class Channel {
  constructor(socket, reader, codec) { this.socket = socket; this.reader = reader; this.codec = codec; this.chain = Promise.resolve(); }
  write(value) { const frame = this.codec.encode(value); const next = this.chain.then(() => write(this.socket, frame)); this.chain = next.catch(() => {}); return next; }
  async read() { const h = await this.reader.exact(4); const n = h.readUInt32BE(); if (n < 8 + TAG || n > MAX + 8 + TAG) throw new WslCoreAdapterError('FRAME_LIMIT', 'Protected frame size is invalid.'); return this.codec.decodeBody(await this.reader.exact(n)); }
}

export function validateLinuxCorePath(path) { if (typeof path !== 'string' || path.length > 4096 || !LINUX_PATH.test(path)) throw new WslCoreAdapterError('CORE_PATH_INVALID', 'cloudos-core Linux path is invalid.'); return path; }
function validateDistribution(name) { if (!DISTRO.test(name || '')) throw new WslCoreAdapterError('DISTRO_INVALID', 'WSL distribution identifier is invalid.'); }
export const buildBootstrapArgs = (distribution, linuxCorePath) => { validateDistribution(distribution); validateLinuxCorePath(linuxCorePath); return ['--distribution', distribution, '--exec', linuxCorePath, 'serve']; };
export const wslCoreTerminalEnabled = env => env.CLOUDOS_WSL_CORE_TERMINAL === '1';
export const wslCoreTerminalFallbackEnabled = env => env.CLOUDOS_WSL_CORE_TERMINAL_FALLBACK === '1';
function safeEnv() { const out = {}; for (const [k,v] of Object.entries(process.env)) if (typeof v === 'string' && !SENSITIVE.test(k)) out[k] = v; return out; }

async function bootstrapLine(stream) {
  return await new Promise((resolve, reject) => { let buf = Buffer.alloc(0); const timer = setTimeout(() => end(new WslCoreAdapterError('BOOTSTRAP_TIMEOUT', 'cloudos-core bootstrap timed out.')), 20000);
    const end = (error, value) => { clearTimeout(timer); stream.off('data', data); stream.off('error', failed); error ? reject(error) : resolve(value); };
    const failed = () => end(new WslCoreAdapterError('BOOTSTRAP_FAILED', 'cloudos-core bootstrap failed.'));
    const data = chunk => { buf = Buffer.concat([buf, Buffer.from(chunk)]); if (buf.length > 8192) return end(new WslCoreAdapterError('BOOTSTRAP_INVALID', 'cloudos-core bootstrap response is too large.')); const i = buf.indexOf(10); if (i >= 0) end(null, buf.subarray(0,i).toString('utf8').trim()); };
    stream.on('data', data); stream.once('error', failed);
  });
}
async function socketTo(port) { return await new Promise((resolve, reject) => { const socket = net.createConnection({ host:'127.0.0.1', port, family:4 }); const timer=setTimeout(()=>{socket.destroy();reject(new WslCoreAdapterError('CHANNEL_TIMEOUT','cloudos-core connection timed out.'));},8000); socket.once('connect',()=>{clearTimeout(timer);socket.setNoDelay(true);resolve(socket);}); socket.once('error',()=>{clearTimeout(timer);reject(new WslCoreAdapterError('CHANNEL_CONNECT_FAILED','cloudos-core connection failed.'));}); }); }

async function authenticate(socket, secret) {
  const reader = new Reader(socket); const cn = randomBytes(32); let sn;
  try {
    await writePlain(socket,{type:'hello',payload:{clientNonce:cn.toString('base64')}}); const challenge=await readPlain(reader); if(challenge.type!=='challenge') throw new WslCoreAdapterError('AUTH_FAILED','Guest challenge is invalid.');
    sn=Buffer.from(challenge.payload?.serverNonce||'','base64'); const candidate=Buffer.from(challenge.payload?.proof||'','base64'); const expected=proof(secret,'server',cn,sn);
    if(sn.length!==32||candidate.length!==expected.length||!timingSafeEqual(candidate,expected)) throw new WslCoreAdapterError('AUTH_FAILED','Guest proof is invalid.');
    await writePlain(socket,{type:'proof',payload:{proof:proof(secret,'client',cn,sn).toString('base64')}}); const channel=new Channel(socket,reader,new SecureFrameCodec(deriveChannelMaterial(secret,cn,sn),'client')); const ready=await channel.read();
    if(ready.type!=='ready'||ready.payload?.protocol!==2||ready.payload?.protection!==WSL_CORE_PROTECTION) throw new WslCoreAdapterError('AUTH_FAILED','Protected ready frame is invalid.'); return channel;
  } finally { cn.fill(0); sn?.fill(0); }
}

class Client {
  constructor(channel,socket,bootstrap){this.channel=channel;this.socket=socket;this.bootstrap=bootstrap;this.pending=new Map();this.listeners=new Map();this.queue=new Map();this.closed=false;this.keepalive=setInterval(()=>{if(!this.closed)this.request('health',null,5000).catch(()=>{});},30000);this.keepalive.unref?.();this.pump=this.#pump();}
  subscribe(id,listener){this.listeners.set(id,listener);for(const event of this.queue.get(id)||[])listener(event);this.queue.delete(id);}
  async #pump(){try{while(!this.closed){const e=await this.channel.read();if(e.type==='event'){const id=e.payload?.sessionId;const listener=id?this.listeners.get(id):null;if(listener)listener(e.payload);else if(id){const q=this.queue.get(id)||[];if(q.length<32)q.push(e.payload);this.queue.set(id,q);}continue;}if(e.type==='response'&&e.id&&this.pending.has(e.id)){const p=this.pending.get(e.id);this.pending.delete(e.id);e.ok===true?p.resolve(e.payload):p.reject(new WslCoreAdapterError(e.error?.code||'REQUEST_FAILED',e.error?.message||'Guest request failed.'));continue;}throw new WslCoreAdapterError('FRAME_SEQUENCE','Unexpected protected frame ordering.');}}catch(error){if(!this.closed){this.closed=true;clearInterval(this.keepalive);for(const p of this.pending.values())p.reject(error);this.pending.clear();this.socket.destroy();}}}
  async request(method,params=null,timeoutMs=8000){if(this.closed)throw new WslCoreAdapterError('CHANNEL_CLOSED','Protected channel is closed.');const id=randomBytes(16).toString('hex');const response=new Promise((resolve,reject)=>{const timer=setTimeout(()=>{this.pending.delete(id);reject(new WslCoreAdapterError('REQUEST_TIMEOUT','Guest request timed out.'));},timeoutMs);this.pending.set(id,{resolve:v=>{clearTimeout(timer);resolve(v);},reject:e=>{clearTimeout(timer);reject(e);}});});try{await this.channel.write({type:'request',id,payload:{method,params}});}catch(error){const p=this.pending.get(id);this.pending.delete(id);p?.reject(error);}return await response;}
  async dispose(){if(this.closed)return;this.closed=true;clearInterval(this.keepalive);this.socket.destroy();try{await Promise.race([this.pump,new Promise(r=>setTimeout(r,250))]);}catch{}}
}

async function connectCore(distribution,linuxCorePath){validateDistribution(distribution);validateLinuxCorePath(linuxCorePath);if(process.env.CLOUDOS_WSL_CORE_FOUNDATION!=='1')throw new WslCoreAdapterError('FEATURE_DISABLED','WSL core foundation is disabled.');const secret=randomBytes(32);const bootstrap=spawn(WSL_EXE,buildBootstrapArgs(distribution,linuxCorePath),{windowsHide:true,shell:false,stdio:['pipe','pipe','pipe'],env:safeEnv()});bootstrap.stderr.resume();try{bootstrap.stdin.end(`${secret.toString('base64')}\n`);const record=JSON.parse(await bootstrapLine(bootstrap.stdout));if(record?.protocol!==2||!Number.isInteger(record?.port)||record.port<1||record.port>65535||!Number.isInteger(record?.pid)||record.pid<=0)throw new WslCoreAdapterError('BOOTSTRAP_INVALID','cloudos-core bootstrap response failed validation.');const socket=await socketTo(record.port);return{client:new Client(await authenticate(socket,secret),socket,bootstrap),corePid:record.pid,bootstrap};}catch(error){if(!bootstrap.killed)bootstrap.kill();throw error;}finally{secret.fill(0);}}

export async function createWslCoreTerminalSession({distribution,linuxCorePath,rows=32,cols=120,onOutput=()=>{},onExit=()=>{}}){const core=await connectCore(distribution,linuxCorePath);let sessionId;let terminalPid=0;let exited=false;let resolveExit;const exitPromise=new Promise(resolve=>{resolveExit=resolve;});try{const status=await core.client.request('terminal.create',{rows,cols});if(!status?.sessionId||!Number.isInteger(status?.pid)||status.pid<=0||status.pty!==true)throw new WslCoreAdapterError('TERMINAL_CREATE_FAILED','Guest terminal session is invalid.');sessionId=status.sessionId;terminalPid=status.pid;core.client.subscribe(sessionId,event=>{if(event.type==='session.output'&&typeof event.data==='string'){try{onOutput(Buffer.from(event.data,'base64').toString('utf8'));}catch{}}else if(event.type==='session.exit'){exited=true;const detail={exitCode:event.exitCode??null,signal:event.signal||''};onExit(detail);resolveExit(detail);}});return{protocol:2,protection:WSL_CORE_PROTECTION,corePid:core.corePid,terminalPid,sessionId,input:async data=>{const b=Buffer.from(String(data));if(b.length>65536)throw new WslCoreAdapterError('IO_LIMIT','Terminal input exceeds limit.');await core.client.request('session.input',{sessionId,data:b.toString('base64')},5000);},resize:async(c,r)=>core.client.request('session.resize',{sessionId,rows:r,cols:c},5000),signal:async signal=>core.client.request('session.signal',{sessionId,signal},5000),waitForExit:async(timeoutMs=8000)=>exited?exitPromise:Promise.race([exitPromise,new Promise((_,reject)=>setTimeout(()=>reject(new WslCoreAdapterError('WAIT_TIMEOUT','Terminal exit timed out.')),timeoutMs))]),close:async()=>{if(!exited){try{await core.client.request('session.signal',{sessionId,signal:'hangup'},2000);}catch{}try{await core.client.request('session.wait',{sessionId,timeoutMs:2000},3500);}catch{}}try{await core.client.request('shutdown',null,3000);}catch{}await core.client.dispose();if(!core.bootstrap.killed&&core.bootstrap.exitCode===null)core.bootstrap.kill();}};}catch(error){try{await core.client.request('shutdown',null,1500);}catch{}await core.client.dispose();if(!core.bootstrap.killed&&core.bootstrap.exitCode===null)core.bootstrap.kill();throw error;}}
