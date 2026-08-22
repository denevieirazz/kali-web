import { execFile, spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { WebSocket } from 'ws';
import { WSL_EXE, getWslSnapshot, normalizeName, safeChildEnvironment, validateInstalledAsync } from '../wsl/distroService.js';
import { XPRA_BIND_TCP_HOST, XPRA_DISPLAY_END, XPRA_DISPLAY_START, XPRA_PORT_END, XPRA_PORT_START, chooseXpraPair, displayForPort as displayForXpraPort, validateLedgerPair } from './xpraPairAllocator.js';

const execFileAsync = promisify(execFile);
const PORT_START = XPRA_PORT_START;
const PORT_END = XPRA_PORT_END;
const DISPLAY_START = XPRA_DISPLAY_START;
const DISPLAY_END = XPRA_DISPLAY_END;
const MAX_ACTIVE_SESSIONS = 4;
const START_TIMEOUT_MS = 25_000;
const HEALTH_TIMEOUT_MS = 4_000;
const STOP_TIMEOUT_MS = 6_000;
const LEASE_TTL_MS = 120_000;
const LEDGER_FILE = path.join(os.tmpdir(), 'cloudos-linux-runtime-poc1-sessions.json');
const ALLOWED_APPS = Object.freeze({
  xclock: { command: 'xclock', title: 'XClock' },
  xeyes: { command: 'xeyes', title: 'XEyes' },
  xterm: { command: 'xterm', title: 'XTerm' },
  gedit: { command: 'gedit', title: 'Gedit' },
  firefox: { command: 'firefox-esr', title: 'Firefox ESR' },
  chromium: { command: 'chromium', title: 'Chromium' },
  code: { command: 'code', title: 'Visual Studio Code' },
  gimp: { command: 'gimp', title: 'GIMP' },
  vlc: { command: 'vlc', title: 'VLC Media Player' },
  libreoffice: { command: 'libreoffice', title: 'LibreOffice' },
  filezilla: { command: 'filezilla', title: 'FileZilla' },
  wireshark: { command: 'wireshark', title: 'Wireshark' },
  galculator: { command: 'galculator', title: 'Calculadora' },
  htop: { command: 'xterm -e htop', title: 'Htop Monitor' },
  mousepad: { command: 'mousepad', title: 'Mousepad' },
});
const OWNER_ID = /^[a-zA-Z0-9._:-]{1,128}$/;
const sessions = new Map();
const reservedPorts = new Set();
let lifecycleQueue = Promise.resolve();

function queueLifecycle(operation) {
  const next = lifecycleQueue.then(operation, operation);
  lifecycleQueue = next.catch(() => undefined);
  return next;
}
function shellQuote(value) { return `'${String(value).replace(/'/g, `'"'"'`)}'`; }
function createPocError(code, message, details = null) { const error = new Error(message); error.code = code; if (details) error.details = details; return error; }
function normalizeOwnerId(value) { const ownerId = String(value || 'cloudos-poc1').trim(); if (!OWNER_ID.test(ownerId)) throw createPocError('LINUX_POC_OWNER_INVALID', 'Identificador de owner inválido.'); return ownerId; }
function elapsedMs(start) { return Math.max(0, Date.now() - start); }
function withTimeout(promise, timeoutMs, code, message) { let timer; return Promise.race([promise, new Promise((_, reject) => { timer = setTimeout(() => reject(createPocError(code, message)), timeoutMs); timer.unref?.(); })]).finally(() => clearTimeout(timer)); }
function publicMetrics(session) { return { preflightMs: session.metrics.preflightMs ?? null, wslServerReadyMs: session.metrics.wslServerReadyMs ?? null, windowsTransportReadyMs: session.metrics.windowsTransportReadyMs ?? null, bootMs: session.metrics.bootMs ?? null, websocketHandshakeMs: session.metrics.websocketHandshakeMs ?? null, lastHealthMs: session.metrics.lastHealthMs ?? null, iframeLoadMs: session.metrics.iframeLoadMs ?? null, firstRemoteWindowMs: session.metrics.firstRemoteWindowMs ?? null, firstFramePaintedMs: session.metrics.firstFramePaintedMs ?? null, canvasWidth: session.metrics.canvasWidth ?? null, canvasHeight: session.metrics.canvasHeight ?? null, reconnectCount: session.metrics.reconnectCount ?? 0, restartCount: session.metrics.restartCount ?? 0, healthFailures: session.metrics.healthFailures ?? 0, proxyHttpRequests: session.metrics.proxyHttpRequests ?? 0, proxyWebSocketConnections: session.metrics.proxyWebSocketConnections ?? 0 }; }
function proxyPath(session) { return `/__cloudos/linux-runtime/poc1/${session.id}/${session.proxyToken}/`; }
function publicSession(session) {
  if (!session) return null;
  return {
    id: session.id,
    generation: session.generation || 1,
    ownerId: session.ownerId,
    app: session.app,
    title: session.title,
    distribution: session.distribution,
    port: session.port,
    display: session.display,
    state: session.state,
    startedAt: session.startedAt,
    leaseExpiresAt: new Date(session.leaseExpiresAt).toISOString(),
    pids: { xpra: session.xpraPid || null, app: session.appPid || null, xorg: session.xorgPid || null },
    clientUrl: ['ready', 'degraded'].includes(session.state) ? `${proxyPath(session)}?username=root&clipboard=no&keyboard=no&printing=no&file_transfer=no&floating_menu=no&reconnect=no` : null,
    xpraVersion: session.xpraVersion,
    error: session.error || null,
    errorCode: session.errorCode || null,
    health: session.health || null,
    metrics: publicMetrics(session)
  };
}
function serializeLedgerSession(session) {
  return {
    id: session.id,
    generation: session.generation || 1,
    ownerId: session.ownerId,
    app: session.app,
    title: session.title,
    distribution: session.distribution,
    port: session.port,
    display: session.display,
    startedAt: session.startedAt,
    leaseExpiresAt: new Date(session.leaseExpiresAt).toISOString(),
    pids: { xpra: session.xpraPid || null, app: session.appPid || null, xorg: session.xorgPid || null }
  };
}
function readLedger() { try { const parsed = JSON.parse(fs.readFileSync(LEDGER_FILE, 'utf8')); return Array.isArray(parsed?.sessions) ? parsed.sessions : []; } catch { return []; } }
function writeLedger() { const live = [...sessions.values()].filter(s => !['stopped', 'failed'].includes(s.state)).map(serializeLedgerSession); try { if (!live.length) return fs.rmSync(LEDGER_FILE, { force: true }); const temp = `${LEDGER_FILE}.tmp`; fs.writeFileSync(temp, JSON.stringify({ version: 1, sessions: live }, null, 2), 'utf8'); fs.renameSync(temp, LEDGER_FILE); } catch {} }

export function getAllowedLinuxPocApps() { return Object.entries(ALLOWED_APPS).map(([id, value]) => ({ id, ...value })); }
export function normalizePocApp(value) { const id = String(value || '').trim().toLowerCase(); return ALLOWED_APPS[id] ? id : null; }
export function displayForPort(port) { return displayForXpraPort(port); }
export function buildXpraProbeCommand(appCommand) { return ['set -eu', 'command -v xpra >/dev/null 2>&1 || { echo XPRA_MISSING; exit 41; }', `command -v ${shellQuote(appCommand)} >/dev/null 2>&1 || { echo APP_MISSING:${appCommand}; exit 42; }`, 'xpra --version'].join('; '); }
export function buildXpraStartCommand({ appCommand, port, sessionId = 'cloudos-poc1', password = 'test-only-secret' }) {
  if (!Number.isInteger(port) || port < PORT_START || port > PORT_END) throw new Error('Porta Xpra fora da faixa da POC.');
  if (!password || String(password).length < 16) throw new Error('Capability Xpra inválida.');
  const display = displayForPort(port);
  return [
    'set -eu',
    'mkdir -p -m 1777 /tmp/.X11-unix 2>/dev/null || true',
    'mount -o remount,rw /tmp/.X11-unix 2>/dev/null || true',
    'chmod 1777 /tmp/.X11-unix 2>/dev/null || true',
    'unset DISPLAY WAYLAND_DISPLAY PULSE_SERVER',
    `export XPRA_PASSWORD=${shellQuote(password)}`,
    `exec xpra seamless :${display} --session-name=${shellQuote(`cloudos-poc1-${sessionId}`)} --start-child=${shellQuote(appCommand)} --exit-with-children=yes --daemon=no --clipboard=no --printing=no --file-transfer=no --webcam=no --audio=no --speaker=no --microphone=no --notifications=no --mdns=no --dbus-launch=no --dbus-control=no --start-new-commands=no --bind=noabstract --bind-tcp=${XPRA_BIND_TCP_HOST}:${port},auth=env --video=no --html=on`,
  ].join('; ');
}
async function execWsl(distribution, command, timeout = HEALTH_TIMEOUT_MS) { return execFileAsync(WSL_EXE, ['-d', distribution, '--exec', 'sh', '-c', command], { windowsHide: true, env: safeChildEnvironment(), timeout, maxBuffer: 512 * 1024 }); }
export async function checkWslInteropDisabled(distribution) {
  const started = Date.now();
  try {
    const { stdout } = await execWsl(distribution, "if [ -e /proc/sys/fs/binfmt_misc/WSLInterop ]; then cat /proc/sys/fs/binfmt_misc/WSLInterop; else echo DISABLED; fi", 15000);
    const evidence = String(stdout || '').trim();
    const disabled = evidence === 'DISABLED' || /disabled/i.test(evidence);
    return {
      ok: disabled,
      code: disabled ? 'WSL_INTEROP_DISABLED' : 'WSL_INTEROP_ENABLED',
      error: disabled ? null : 'POC1 exige WSL interoperability desabilitado e reinício da distro antes de iniciar.',
      evidence,
      durationMs: elapsedMs(started),
    };
  } catch (cause) {
    const isTimeout = cause.killed || cause.signal === 'SIGTERM' || cause.code === 'ETIMEDOUT' || /timeout/i.test(cause.message);
    return {
      ok: false,
      code: isTimeout ? 'WSL_INTEROP_PROBE_TIMEOUT' : 'WSL_INTEROP_PROBE_FAILED',
      error: isTimeout ? 'A verificação de interoperabilidade do WSL excedeu o tempo limite (cold boot).' : `Falha ao verificar status de interoperabilidade: ${cause.message}`,
      evidence: cause.message,
      durationMs: elapsedMs(started),
    };
  }
}
async function chooseDistribution(requested, snapshot = null) { if (requested) { const distribution = normalizeName(requested); if (!await validateInstalledAsync(distribution)) throw createPocError('WSL_DISTRO_NOT_INSTALLED', `Distribuição WSL não instalada: ${distribution || '(vazia)'}`); return distribution; } const current = snapshot || await getWslSnapshot(); if (!current.installed) throw createPocError('WSL_NOT_FOUND', current.error || 'WSL ausente.'); if (!current.operational) throw createPocError(current.errorCode || 'WSL_UNAVAILABLE', current.error || 'WSL indisponível.'); if (!current.distributions.length) throw createPocError('WSL_DISTRO_MISSING', 'Nenhuma distribuição WSL instalada.'); return current.preferred || current.default || current.distributions[0].name; }
async function probe(distribution, appCommand) { const started = Date.now(); try { const { stdout, stderr } = await execWsl(distribution, buildXpraProbeCommand(appCommand), 15000); return { ok: true, durationMs: elapsedMs(started), version: String(stdout || stderr || '').trim().split(/\r?\n/).filter(Boolean).at(-1) || 'xpra' }; } catch (cause) { const text = `${cause.stdout || ''}\n${cause.stderr || ''}`; if (text.includes('XPRA_MISSING')) throw createPocError('XPRA_MISSING', `Xpra não está instalado em ${distribution}.`); if (text.includes('APP_MISSING:')) throw createPocError('LINUX_POC_APP_MISSING', `${appCommand} não está instalado em ${distribution}.`); throw createPocError('XPRA_PROBE_FAILED', cause.message); } }
async function isPortFree(port) { if (reservedPorts.has(port)) return false; return new Promise(resolve => { const server = net.createServer(); server.unref(); server.once('error', () => resolve(false)); server.listen({ host: '127.0.0.1', port, exclusive: true }, () => server.close(() => resolve(true))); }); }
async function scanOccupiedDisplays(distribution) { const { stdout } = await execWsl(distribution, `for n in $(seq ${DISPLAY_START} ${DISPLAY_END}); do if [ -S \"/tmp/.X11-unix/X$n\" ] || [ -e \"/tmp/.X$n-lock\" ]; then echo \"$n\"; fi; done`, 5000); return String(stdout || '').split(/\r?\n/).map(v => Number(v.trim())).filter(Number.isInteger); }
async function findFreePair(distribution) { const occupiedDisplays = await scanOccupiedDisplays(distribution); const freePorts = []; for (let port = PORT_START; port <= PORT_END; port += 1) if (await isPortFree(port)) freePorts.push(port); return chooseXpraPair({ occupiedDisplays, freePorts }); }
async function reservePair(distribution) { const pair = await findFreePair(distribution); if (!pair) throw createPocError('XPRA_PAIR_UNAVAILABLE', 'Nenhum par DISPLAY/porta livre.'); reservedPorts.add(pair.port); return pair; }
function releasePort(port) { reservedPorts.delete(port); }
async function probeWslServer(session) { const started = Date.now(); try { await execWsl(session.distribution, `xpra info :${session.display} >/dev/null 2>&1`, HEALTH_TIMEOUT_MS); return { ok: true, durationMs: elapsedMs(started) }; } catch (cause) { return { ok: false, durationMs: elapsedMs(started), error: cause.message }; } }
async function probeWindowsTcp(port, timeoutMs = 1500) { const started = Date.now(); return new Promise(resolve => { const socket = net.createConnection({ host: '127.0.0.1', port }); let done = false; const finish = result => { if (done) return; done = true; socket.destroy(); resolve({ ...result, durationMs: elapsedMs(started) }); }; socket.setTimeout(timeoutMs, () => finish({ ok: false, error: 'timeout' })); socket.once('connect', () => finish({ ok: true })); socket.once('error', e => finish({ ok: false, error: e.message })); }); }
async function probeHttp(port, password = null, timeoutMs = 1500) {
  const started = Date.now();
  try {
    const headers = {};
    if (password) {
      headers.authorization = `Basic ${Buffer.from(`xpra:${password}`).toString('base64')}`;
    }
    const response = await fetch(`http://127.0.0.1:${port}/`, {
      headers,
      signal: AbortSignal.timeout(timeoutMs),
    });
    const body = await response.text();
    const ok = response.ok && /xpra/i.test(body.slice(0, 32000));
    return { ok, status: response.status, durationMs: elapsedMs(started), error: ok ? null : `HTTP ${response.status}` };
  } catch (cause) {
    return { ok: false, durationMs: elapsedMs(started), error: cause.message };
  }
}
async function probeWebSocket(port, password = null, timeoutMs = 2000) {
  const started = Date.now();
  return new Promise(resolve => {
    let done = false;
    const headers = {};
    if (password) {
      headers.authorization = `Basic ${Buffer.from(`xpra:${password}`).toString('base64')}`;
    }
    const socket = new WebSocket(`ws://127.0.0.1:${port}/`, ['binary'], {
      handshakeTimeout: timeoutMs,
      origin: `http://127.0.0.1:${port}`,
      headers,
    });
    const timer = setTimeout(() => finish({ ok: false, error: 'timeout' }), timeoutMs + 100);
    function finish(result) {
      if (done) return;
      done = true;
      clearTimeout(timer);
      try { socket.terminate(); } catch {}
      resolve({ ...result, durationMs: elapsedMs(started) });
    }
    socket.once('open', () => finish({ ok: true }));
    socket.once('error', e => finish({ ok: false, error: e.message }));
    socket.once('unexpected-response', (_req, res) => finish({ ok: false, error: `HTTP ${res.statusCode}` }));
  });
}
async function waitForWslServer(session, child) { const deadline = Date.now() + START_TIMEOUT_MS; while (Date.now() < deadline) { if (child.exitCode !== null) throw createPocError('XPRA_EXITED_EARLY', `Xpra terminou (exit=${child.exitCode}).`); const result = await probeWslServer(session); if (result.ok) return result; await new Promise(r => setTimeout(r, 250)); } throw createPocError('XPRA_SERVER_TIMEOUT', 'Timeout esperando Xpra.'); }
async function waitForWindowsTransport(session, child) {
  const deadline = Date.now() + START_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw createPocError('XPRA_EXITED_EARLY', 'Xpra terminou durante transporte.');
    const tcp = await probeWindowsTcp(session.port);
    if (tcp.ok) {
      const http = await probeHttp(session.port, session.xpraPassword);
      if (http.ok) return { tcp, http };
    }
    await new Promise(r => setTimeout(r, 250));
  }
  throw createPocError('XPRA_WINDOWS_TRANSPORT_TIMEOUT', 'Transporte Xpra indisponível no Windows.');
}

export function getXpraPocSession(id = null) { return id ? publicSession(sessions.get(id)) : publicSession([...sessions.values()][0] || null); }
export function getXpraPocSessions(ownerId = null) { const owner = ownerId ? normalizeOwnerId(ownerId) : null; return [...sessions.values()].filter(s => !owner || s.ownerId === owner).map(publicSession); }
export async function checkXpraPocReadiness({ app = 'xclock', distribution } = {}) {
  const started = Date.now(); const appId = normalizePocApp(app); const checks = { wsl: { ok: false }, distribution: { ok: false }, interop: { ok: false }, xpra: { ok: false }, app: { ok: false }, port: { ok: false }, windowsLoopback: { ok: null }, websocket: { ok: null }, orphans: { ok: true, count: 0 } };
  if (!appId) return { ready: false, errorCode: 'LINUX_POC_APP_NOT_ALLOWED', error: 'Aplicativo não permitido.', checks, durationMs: elapsedMs(started) };
  const snapshot = await getWslSnapshot(); checks.wsl = { ok: snapshot.installed && snapshot.operational }; if (!checks.wsl.ok) return { ready: false, errorCode: snapshot.errorCode || 'WSL_UNAVAILABLE', error: snapshot.error || 'WSL indisponível.', checks, durationMs: elapsedMs(started) };
  const selected = await chooseDistribution(distribution, snapshot); checks.distribution = { ok: true, name: selected };
  const interop = await checkWslInteropDisabled(selected); checks.interop = interop; if (!interop.ok) return { ready: false, errorCode: interop.code || 'WSL_INTEROP_ENABLED', error: interop.error || 'POC1 exige WSL interoperability desabilitado e reinício da distro antes de iniciar.', distribution: selected, checks, durationMs: elapsedMs(started) };
  try { const result = await probe(selected, ALLOWED_APPS[appId].command); checks.xpra = { ok: true, version: result.version }; checks.app = { ok: true, command: ALLOWED_APPS[appId].command }; } catch (cause) { return { ready: false, errorCode: cause.code, error: cause.message, distribution: selected, checks, durationMs: elapsedMs(started) }; }
  const pair = await findFreePair(selected); checks.port = { ok: Boolean(pair), candidate: pair?.port, display: pair?.display }; if (!pair) return { ready: false, errorCode: 'XPRA_PAIR_UNAVAILABLE', error: 'Nenhum par livre.', distribution: selected, checks, durationMs: elapsedMs(started) };
  const orphans = await inspectOwnedOrphans({ distribution: selected }); checks.orphans = { ok: !orphans.length, count: orphans.length, sessions: orphans }; if (orphans.length) return { ready: false, errorCode: 'LINUX_POC_ORPHANED_SESSION', error: 'Sessão órfã detectada.', distribution: selected, checks, durationMs: elapsedMs(started) };
  return { ready: true, app: appId, distribution: selected, checks, durationMs: elapsedMs(started) };
}
async function inspectOwnedOrphans({ distribution = null } = {}) { const ledger = readLedger(); const orphans = []; for (const entry of ledger) { if (sessions.has(entry.id)) continue; const pair = validateLedgerPair(entry); if (!pair.ok) { orphans.push({ ...entry, classification: pair.code }); continue; } if (distribution && entry.distribution !== distribution) continue; if (!await validateInstalledAsync(entry.distribution)) continue; const linux = await probeWslServer({ distribution: entry.distribution, display: entry.display }); const tcp = await probeWindowsTcp(entry.port, 500); if (linux.ok || tcp.ok) orphans.push({ ...entry, linuxAlive: linux.ok, windowsPortAlive: tcp.ok }); } return orphans; }
async function stopLedgerEntry(entry) { if (await validateInstalledAsync(entry.distribution)) await execWsl(entry.distribution, `xpra stop :${Number(entry.display)} >/dev/null 2>&1 || true`, STOP_TIMEOUT_MS).catch(() => undefined); }
export async function cleanupXpraPoc({ ownerId = null, orphansOnly = false } = {}) { return queueLifecycle(async () => { const owner = ownerId ? normalizeOwnerId(ownerId) : null; const stopped = []; if (!orphansOnly) for (const session of [...sessions.values()].filter(s => !owner || s.ownerId === owner)) { await stopSessionInternal(session); stopped.push(session.id); } for (const entry of readLedger().filter(e => !sessions.has(e.id) && (!owner || e.ownerId === owner))) { await stopLedgerEntry(entry); stopped.push(entry.id); } writeLedger(); return { cleaned: [...new Set(stopped)], remaining: getXpraPocSessions(owner) }; }); }
function diagnosticsFor(session) { return session.diagnostics.join('').slice(-6000); }
async function inspectSessionPids(distribution, display, appCommand) {
  try {
    const cmd = `cat /tmp/${display}/server.pid 2>/dev/null || true; echo '---'; cat /tmp/${display}/${appCommand}.pid 2>/dev/null || true; echo '---'; cat /tmp/${display}/xvfb.pid 2>/dev/null || true`;
    const { stdout } = await execWsl(distribution, cmd, 3000);
    const parts = String(stdout || '').split('---').map(s => Number(s.trim())).map(n => Number.isInteger(n) && n > 0 ? n : null);
    return { xpra: parts[0] || null, app: parts[1] || null, xorg: parts[2] || null };
  } catch {
    return { xpra: null, app: null, xorg: null };
  }
}

export async function startXpraPoc({ app, distribution, ownerId, generation = 1 } = {}) {
  return queueLifecycle(async () => {
    const appId = normalizePocApp(app || 'xclock'); if (!appId) throw createPocError('LINUX_POC_APP_NOT_ALLOWED', 'Aplicativo não permitido.'); const owner = normalizeOwnerId(ownerId);
    const existing = [...sessions.values()].find(s => s.ownerId === owner && s.app === appId && ['starting', 'ready', 'degraded'].includes(s.state)); if (existing) return publicSession(existing);
    if ([...sessions.values()].filter(s => s.ownerId === owner && ['starting', 'ready', 'degraded'].includes(s.state)).length >= MAX_ACTIVE_SESSIONS) throw createPocError('LINUX_POC_SESSION_LIMIT', 'Limite de sessões atingido.');
    const readiness = await checkXpraPocReadiness({ app: appId, distribution }); if (!readiness.ready) throw createPocError(readiness.errorCode, readiness.error, readiness.checks);
    const definition = ALLOWED_APPS[appId]; const pair = await reservePair(readiness.distribution); const id = `xpra-${Date.now().toString(36)}-${crypto.randomBytes(4).toString('hex')}`;
    const startedAt = new Date().toISOString();
    const leaseExpiresAt = Date.now() + LEASE_TTL_MS;
    const session = {
      id,
      generation,
      ownerId: owner,
      proxyToken: crypto.randomBytes(24).toString('hex'),
      xpraPassword: crypto.randomBytes(32).toString('base64url'),
      app: appId,
      title: definition.title,
      distribution: readiness.distribution,
      port: pair.port,
      display: pair.display,
      state: 'starting',
      startedAt,
      leaseExpiresAt,
      xpraPid: null,
      appPid: null,
      xorgPid: null,
      xpraVersion: readiness.checks.xpra.version,
      child: null,
      diagnostics: [],
      metrics: { preflightMs: readiness.durationMs, restartCount: 0, reconnectCount: 0, healthFailures: 0, proxyHttpRequests: 0, proxyWebSocketConnections: 0 }
    };
    sessions.set(id, session); writeLedger(); const startClock = Date.now(); const command = buildXpraStartCommand({ appCommand: definition.command, port: pair.port, sessionId: id, password: session.xpraPassword });
    const child = spawn(WSL_EXE, ['-d', session.distribution, '--exec', 'sh', '-c', command], { windowsHide: true, env: safeChildEnvironment(), stdio: ['ignore', 'pipe', 'pipe'] }); session.child = child;
    for (const stream of [child.stdout, child.stderr]) stream.on('data', chunk => { session.diagnostics.push(String(chunk)); while (session.diagnostics.join('').length > 65536) session.diagnostics.shift(); });
    child.once('exit', code => { releasePort(session.port); if (!['stopping', 'stopped'].includes(session.state)) { session.state = 'failed'; session.errorCode = 'XPRA_PROCESS_EXITED'; session.error = `Xpra encerrou (exit=${code}). ${diagnosticsFor(session)}`; } writeLedger(); });
    try {
      await withTimeout(waitForWslServer(session, child), START_TIMEOUT_MS, 'XPRA_SERVER_TIMEOUT', 'Timeout Xpra.');
      session.metrics.wslServerReadyMs = elapsedMs(startClock);
      await withTimeout(waitForWindowsTransport(session, child), START_TIMEOUT_MS, 'XPRA_WINDOWS_TRANSPORT_TIMEOUT', 'Timeout transporte.');
      session.metrics.windowsTransportReadyMs = elapsedMs(startClock);
      const ws = await probeWebSocket(session.port, session.xpraPassword);
      session.metrics.websocketHandshakeMs = ws.durationMs;
      if (!ws.ok) throw createPocError('XPRA_WEBSOCKET_UNAVAILABLE', ws.error);
      const pids = await inspectSessionPids(session.distribution, session.display, definition.command);
      session.xpraPid = pids.xpra;
      session.appPid = pids.app;
      session.xorgPid = pids.xorg;
      session.metrics.bootMs = elapsedMs(startClock);
      session.state = 'ready';
      session.health = { healthy: true, checkedAt: new Date().toISOString() };
      writeLedger();
      return publicSession(session);
    } catch (cause) {
      session.errorCode = cause.code || 'XPRA_START_FAILED';
      session.error = `${cause.message}\n${diagnosticsFor(session)}`.trim();
      await stopSessionInternal(session).catch(() => undefined);
      throw createPocError(session.errorCode, session.error);
    }
  });
}
export async function healthXpraPocSession(id) {
  const session = sessions.get(id);
  if (!session) throw createPocError('LINUX_POC_SESSION_NOT_FOUND', 'Sessão não encontrada.');
  const started = Date.now();
  session.leaseExpiresAt = Date.now() + LEASE_TTL_MS;
  const linux = await probeWslServer(session);
  const tcp = await probeWindowsTcp(session.port);
  const http = tcp.ok ? await probeHttp(session.port, session.xpraPassword) : { ok: false };
  const websocket = http.ok ? await probeWebSocket(session.port, session.xpraPassword) : { ok: false };
  const healthy = linux.ok && tcp.ok && http.ok && websocket.ok && session.child?.exitCode === null;
  session.metrics.lastHealthMs = elapsedMs(started);
  if (!healthy) session.metrics.healthFailures += 1;
  session.state = healthy ? 'ready' : 'degraded';
  session.health = { healthy, checkedAt: new Date().toISOString(), linux, windowsTcp: tcp, http, websocket };
  return { session: publicSession(session), health: session.health };
}
async function stopSessionInternal(session) {
  if (!session || session.state === 'stopped') return publicSession(session);
  session.state = 'stopping';
  await execWsl(session.distribution, `xpra stop :${session.display} >/dev/null 2>&1 || true`, STOP_TIMEOUT_MS).catch(() => undefined);
  if (session.child && session.child.exitCode === null) {
    try { session.child.kill('SIGTERM'); } catch {}
    await new Promise(r => setTimeout(r, 400));
    if (session.child.exitCode === null) {
      try { session.child.kill('SIGKILL'); } catch {}
    }
  }
  await execWsl(session.distribution, `rm -f /tmp/.X11-unix/X${session.display} /tmp/.X${session.display}-lock /tmp/${session.display}/*.pid >/dev/null 2>&1 || true`, 2000).catch(() => undefined);
  session.state = 'stopped';
  if (session.xpraPassword) session.xpraPassword = null;
  releasePort(session.port);
  sessions.delete(session.id);
  writeLedger();
  return publicSession(session);
}
export async function stopXpraPoc(id = null, ownerId = null) {
  return queueLifecycle(async () => {
    if (id) {
      const session = sessions.get(id);
      if (!session) return null;
      if (ownerId && session.ownerId !== normalizeOwnerId(ownerId)) throw createPocError('LINUX_POC_SESSION_OWNER_MISMATCH', 'Sessão pertence a outro owner.');
      return stopSessionInternal(session);
    }
    const owner = ownerId ? normalizeOwnerId(ownerId) : null;
    const result = [];
    for (const session of [...sessions.values()].filter(s => !owner || s.ownerId === owner)) result.push(await stopSessionInternal(session));
    return result;
  });
}
export async function restartXpraPoc(id, ownerId = null) {
  const current = sessions.get(id);
  if (!current) throw createPocError('LINUX_POC_SESSION_NOT_FOUND', 'Sessão não encontrada.');
  if (ownerId && current.ownerId !== normalizeOwnerId(ownerId)) throw createPocError('LINUX_POC_SESSION_OWNER_MISMATCH', 'Sessão pertence a outro owner.');
  const nextGeneration = (current.generation || 1) + 1;
  const config = { app: current.app, distribution: current.distribution, ownerId: current.ownerId, generation: nextGeneration };
  await stopXpraPoc(id, current.ownerId);
  return startXpraPoc(config);
}
export function recordXpraPocClientMetrics(id, ownerId, values = {}) {
  const session = sessions.get(id);
  if (!session) throw createPocError('LINUX_POC_SESSION_NOT_FOUND', 'Sessão não encontrada.');
  if (session.ownerId !== normalizeOwnerId(ownerId)) throw createPocError('LINUX_POC_SESSION_OWNER_MISMATCH', 'Sessão pertence a outro owner.');
  session.leaseExpiresAt = Date.now() + LEASE_TTL_MS;
  for (const key of ['iframeLoadMs', 'firstRemoteWindowMs', 'firstFramePaintedMs', 'canvasWidth', 'canvasHeight']) {
    const value = Number(values[key]);
    if (Number.isFinite(value) && value >= 0 && value <= 300000) session.metrics[key] = Math.round(value);
  }
  return publicSession(session);
}
export function resolveXpraPocProxySession(id, token) {
  const session = sessions.get(String(id || ''));
  if (!session || !['starting', 'ready', 'degraded'].includes(session.state)) return null;
  if (!session.xpraPassword) return null;
  if (Date.now() > (session.leaseExpiresAt || 0) + 15_000) return null;
  const supplied = Buffer.from(String(token || ''));
  const expected = Buffer.from(session.proxyToken);
  if (supplied.length !== expected.length || !crypto.timingSafeEqual(supplied, expected)) return null;
  return session;
}
export function recordXpraPocProxyEvent(id, event) {
  const session = sessions.get(id);
  if (!session) return;
  session.leaseExpiresAt = Date.now() + LEASE_TTL_MS;
  if (event === 'http') session.metrics.proxyHttpRequests += 1;
  if (event === 'websocket') session.metrics.proxyWebSocketConnections += 1;
}
export async function shutdownXpraPocRuntime() { try { await cleanupXpraPoc(); } catch {} }
