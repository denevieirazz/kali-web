import { spawn } from 'node:child_process';
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import net from 'node:net';
import {
  WSL_CORE_PROTOCOL,
  WSL_CORE_PROTECTION,
  WslCoreAdapterError,
  SecureFrameCodec,
  deriveChannelMaterial,
  buildBootstrapArgs,
  parseBootstrapRecord,
  connectLoopbackWithReadiness,
  sanitizeBootstrapStderr,
} from '../terminal/wslCoreAdapter.js';

const WSL_EXE = 'C:\\Windows\\System32\\wsl.exe';
const MAX_FRAME = 1 << 20;
const SENSITIVE = /(?:SECRET|TOKEN|PASSWORD|CREDENTIAL|PRIVATE_KEY|API_KEY|JWT|NONCE)/i;

class Reader {
  constructor(stream) {
    this.buffer = Buffer.alloc(0); this.closed = false; this.waiters = [];
    stream.on('data', chunk => { this.buffer = Buffer.concat([this.buffer, Buffer.from(chunk)]); this.#wake(); });
    const close = () => { this.closed = true; this.#wake(); };
    stream.on('end', close); stream.on('close', close); stream.on('error', close);
  }
  #wake() { for (const wake of this.waiters.splice(0)) wake(); }
  async exact(size, timeoutMs = 10000) {
    const deadline = Date.now() + timeoutMs;
    while (this.buffer.length < size) {
      if (this.closed) throw new WslCoreAdapterError('CHANNEL_CLOSED', 'Protected channel closed.');
      const left = deadline - Date.now(); if (left <= 0) throw new WslCoreAdapterError('CHANNEL_TIMEOUT', 'Protected channel timed out.');
      await new Promise((resolve, reject) => { const timer = setTimeout(() => reject(new WslCoreAdapterError('CHANNEL_TIMEOUT', 'Protected channel timed out.')), left); this.waiters.push(() => { clearTimeout(timer); resolve(); }); });
    }
    const out = this.buffer.subarray(0, size); this.buffer = this.buffer.subarray(size); return out;
  }
}
function envWithoutSecrets() { const out = {}; for (const [key,value] of Object.entries(process.env)) if (typeof value === 'string' && !SENSITIVE.test(key)) out[key] = value; return out; }
function hmac(secret, role, clientNonce, serverNonce) { return createHmac('sha256', secret).update(Buffer.concat([Buffer.from(`cloudos-core/v2/${role}`, 'ascii'), Buffer.from([0]), clientNonce, serverNonce])).digest(); }
function encodePlain(value) { const body = Buffer.from(JSON.stringify({ v: WSL_CORE_PROTOCOL, ...value })); if (!body.length || body.length > MAX_FRAME) throw new WslCoreAdapterError('FRAME_LIMIT','Protocol frame size is invalid.'); const header=Buffer.alloc(4);header.writeUInt32BE(body.length);return Buffer.concat([header,body]); }
async function readPlain(reader) { const h=await reader.exact(4);const size=h.readUInt32BE();if(!size||size>MAX_FRAME)throw new WslCoreAdapterError('FRAME_LIMIT','Protocol frame size is invalid.');const value=JSON.parse((await reader.exact(size)).toString('utf8'));if(value?.v!==WSL_CORE_PROTOCOL||typeof value?.type!=='string')throw new WslCoreAdapterError('PROTOCOL_VERSION','Protocol frame version is invalid.');return value; }
async function writeSocket(socket, data) {
  if(socket.destroyed) throw new WslCoreAdapterError('CHANNEL_CLOSED','Protected channel closed.');
  if(socket.write(data)) return;
  await new Promise((resolve,reject)=>{
    const done=()=>{socket.off('error',fail);resolve();};
    const fail=()=>{socket.off('drain',done);reject(new WslCoreAdapterError('CHANNEL_CLOSED','Protected channel write failed.'));};
    socket.once('drain',done); socket.once('error',fail);
  });
}
async function readBootstrapLine(stream, childState, stderr) { return await new Promise((resolve,reject)=>{let buffer='';const timeout=setTimeout(()=>done(new WslCoreAdapterError('BOOTSTRAP_TIMEOUT','cloudos-core bootstrap timed out.')),20000);const onData=chunk=>{buffer+=Buffer.from(chunk).toString('utf8');if(buffer.length>8192)return done(new WslCoreAdapterError('BOOTSTRAP_INVALID','cloudos-core bootstrap response is too large.'));const index=buffer.indexOf('\n');if(index>=0)done(null,buffer.slice(0,index).trim());};const poll=setInterval(()=>{if(childState.exited)done(new WslCoreAdapterError('BOOTSTRAP_EXITED','cloudos-core exited before endpoint publication.'));},25);poll.unref?.();const done=(error,value)=>{clearTimeout(timeout);clearInterval(poll);stream.off('data',onData);error?reject(error):resolve(value);};stream.on('data',onData);}); }

class RpcClient {
  constructor(socket, reader, codec) { this.socket=socket;this.reader=reader;this.codec=codec;this.pending=new Map();this.closed=false;this.writeChain=Promise.resolve();this.pump=this.#pump();this.keepalive=setInterval(()=>{if(!this.closed)this.request('health',null,4000).catch(()=>{});},30000);this.keepalive.unref?.(); }
  async #readProtected(){const h=await this.reader.exact(4);const size=h.readUInt32BE();if(size<24||size>MAX_FRAME+24)throw new WslCoreAdapterError('FRAME_LIMIT','Protected frame size is invalid.');return this.codec.decodeBody(await this.reader.exact(size));}
  async #pump(){try{while(!this.closed){const env=await this.#readProtected();if(env.type==='event')continue;if(env.type!=='response'||!env.id||!this.pending.has(env.id))throw new WslCoreAdapterError('FRAME_SEQUENCE','Unexpected protected frame ordering.');const pending=this.pending.get(env.id);this.pending.delete(env.id);env.ok===true?pending.resolve(env.payload):pending.reject(Object.assign(new WslCoreAdapterError(env.error?.code||'REQUEST_FAILED',env.error?.message||'Guest request failed.'),{code:env.error?.code||'REQUEST_FAILED'}));}}catch(error){if(!this.closed){this.closed=true;clearInterval(this.keepalive);for(const p of this.pending.values())p.reject(error);this.pending.clear();this.socket.destroy();}}}
  async request(method, params=null, timeoutMs=5000){if(this.closed)throw new WslCoreAdapterError('CHANNEL_CLOSED','Protected channel is closed.');const id=randomBytes(16).toString('hex');const response=new Promise((resolve,reject)=>{const timer=setTimeout(()=>{this.pending.delete(id);reject(new WslCoreAdapterError('REQUEST_TIMEOUT','Guest request timed out.'));},timeoutMs);this.pending.set(id,{resolve:v=>{clearTimeout(timer);resolve(v);},reject:e=>{clearTimeout(timer);reject(e);}});});const frame=this.codec.encode({type:'request',id,payload:{method,params}});this.writeChain=this.writeChain.then(()=>writeSocket(this.socket,frame));try{await this.writeChain;}catch(error){this.pending.get(id)?.reject(error);this.pending.delete(id);}return await response;}
  async close(){if(this.closed)return;this.closed=true;clearInterval(this.keepalive);this.socket.destroy();for(const p of this.pending.values())p.reject(new WslCoreAdapterError('CHANNEL_CLOSED','Protected channel closed.'));this.pending.clear();try{await Promise.race([this.pump,new Promise(resolve=>setTimeout(resolve,200))]);}catch{}}
}

async function authenticateAndCreateClient(socket, secret) {
  const reader=new Reader(socket);const clientNonce=randomBytes(32);let serverNonce;
  try {
    await writeSocket(socket,encodePlain({type:'hello',payload:{clientNonce:clientNonce.toString('base64')}}));
    const challenge=await readPlain(reader);if(challenge.type!=='challenge')throw new WslCoreAdapterError('AUTH_FAILED','Guest challenge is invalid.');
    serverNonce=Buffer.from(challenge.payload?.serverNonce||'','base64');const received=Buffer.from(challenge.payload?.proof||'','base64');const expected=hmac(secret,'server',clientNonce,serverNonce);
    if(serverNonce.length!==32||received.length!==expected.length||!timingSafeEqual(received,expected))throw new WslCoreAdapterError('AUTH_FAILED','Guest proof is invalid.');
    await writeSocket(socket,encodePlain({type:'proof',payload:{proof:hmac(secret,'client',clientNonce,serverNonce).toString('base64')}}));
    const codec=new SecureFrameCodec(deriveChannelMaterial(secret,clientNonce,serverNonce),'client');
    const h=await reader.exact(4);const size=h.readUInt32BE();if(size<24||size>MAX_FRAME+24)throw new WslCoreAdapterError('FRAME_LIMIT','Protected ready frame size is invalid.');const ready=codec.decodeBody(await reader.exact(size));
    if(ready.type!=='ready'||ready.payload?.protocol!==WSL_CORE_PROTOCOL||ready.payload?.protection!==WSL_CORE_PROTECTION)throw new WslCoreAdapterError('AUTH_FAILED','Protected ready frame is invalid.');
    return new RpcClient(socket,reader,codec);
  } finally { clientNonce.fill(0);serverNonce?.fill(0); }
}

export async function createWslCoreRpcSession({ distribution, linuxCorePath, cgroupControl = false }) {
  if (process.env.CLOUDOS_WSL_CORE_FOUNDATION !== '1') throw new WslCoreAdapterError('FEATURE_DISABLED', 'WSL core foundation is disabled.');
  const args=buildBootstrapArgs(distribution,linuxCorePath);if(cgroupControl)args.push('--cgroup-control');
  const secret=randomBytes(32);const child=spawn(WSL_EXE,args,{windowsHide:true,shell:false,stdio:['pipe','pipe','pipe'],env:envWithoutSecrets()});
  const state={exited:false,exitCode:null,signal:''};child.once('exit',(code,signal)=>{state.exited=true;state.exitCode=Number.isInteger(code)?code:null;state.signal=typeof signal==='string'?signal:'';});let stderrText='';child.stderr.on('data',chunk=>{if(stderrText.length<4096)stderrText+=Buffer.from(chunk).toString('utf8');});const stderr=()=>sanitizeBootstrapStderr(stderrText);
  let socket=null;let client=null;let closed=false;const exitCleanup=()=>{if(!child.killed&&child.exitCode===null)child.kill();};process.once('exit',exitCleanup);
  try {
    await new Promise((resolve,reject)=>child.stdin.end(Buffer.from(`${secret.toString('base64')}\n`,'ascii'),error=>error?reject(error):resolve()));
    const record=parseBootstrapRecord(await readBootstrapLine(child.stdout,state,stderr));
    const readiness=await connectLoopbackWithReadiness(record.port,{timeoutMs:8000,bootstrapState:state,getStderr:stderr,diagnostic:{stage:'connect-readiness',distribution,protocol:WSL_CORE_PROTOCOL,corePid:record.pid,port:record.port}});socket=readiness.socket;
    client=await authenticateAndCreateClient(socket,secret);
    return { protocol:WSL_CORE_PROTOCOL,protection:WSL_CORE_PROTECTION,corePid:record.pid,distribution,request:(method,params=null,timeoutMs=5000)=>client.request(method,params,timeoutMs),close:async()=>{if(closed)return;closed=true;process.off('exit',exitCleanup);try{await client.request('shutdown',null,2000);}catch{}await client.close();if(!child.killed&&child.exitCode===null)child.kill();} };
  } catch (error) { process.off('exit',exitCleanup);socket?.destroy();if(!child.killed&&child.exitCode===null)child.kill();throw error; }
  finally { secret.fill(0); }
}
