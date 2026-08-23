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
import { scanDiscoveredLinuxApps } from './desktopScanner.js';

const execFileAsync = promisify(execFile);
const PORT_START = XPRA_PORT_START;
const PORT_END = XPRA_PORT_END;
const DISPLAY_START = XPRA_DISPLAY_START;
const DISPLAY_END = XPRA_DISPLAY_END;
const MAX_ACTIVE_SESSIONS = 6;
const START_TIMEOUT_MS = 25_000;
const HEALTH_TIMEOUT_MS = 4_000;
const STOP_TIMEOUT_MS = 6_000;
const LEASE_TTL_MS = 120_000;
const LEDGER_FILE = path.join(os.tmpdir(), 'cloudos-linux-runtime-poc1-sessions.json');

export const ALLOWED_APPS = Object.freeze({
  xclock: { command: 'xclock', title: 'XClock' },
  xeyes: { command: 'xeyes', title: 'XEyes' },
  xterm: { command: "xterm -fa 'Monospace' -fs 11 -bg black -fg white", title: 'XTerm' },
  gedit: { command: 'gedit', title: 'Gedit' },
  firefox: { command: 'firefox-esr --no-remote --profile /tmp/cloudos-firefox-poc-{sessionId}', title: 'Firefox ESR' },
  chromium: { command: 'chromium --no-sandbox --disable-gpu', title: 'Chromium' },
  code: { command: 'code --no-sandbox', title: 'Visual Studio Code' },
  gimp: { command: 'gimp', title: 'GIMP' },
  vlc: { command: 'vlc', title: 'VLC Media Player' },
  libreoffice: { command: 'libreoffice', title: 'LibreOffice' },
  filezilla: { command: 'filezilla', title: 'FileZilla' },
  wireshark: { command: 'wireshark', title: 'Wireshark' },
  galculator: { command: 'galculator', title: 'Calculadora' },
  htop: { command: "xterm -fa 'Monospace' -fs 11 -e htop", title: 'Htop Monitor' },
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
    clientUrl: ['ready', 'degraded'].includes(session.state) ? `${proxyPath(session)}?username=root&clipboard=no&printing=no&file_transfer=no&floating_menu=no&reconnect=no` : null,
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

export async function resolvePocApp(appId, distro = 'kali-linux') {
  if (!appId) return null;
  const cleanId = String(appId).trim().toLowerCase();
  if (ALLOWED_APPS[cleanId]) {
    return { id: cleanId, ...ALLOWED_APPS[cleanId] };
  }
  const discovered = await scanDiscoveredLinuxApps(distro).catch(() => []);
  const found = discovered.find(d => d.id === cleanId || d.command.split(' ')[0].split('/').pop() === cleanId);
  if (found) {
    const cmd = found.terminal ? `xterm -fa 'Monospace' -fs 11 -bg black -fg white -e ${found.command}` : found.command;
    return {
      id: found.id,
      command: cmd,
      title: found.name,
      icon: found.iconUrl || found.icon,
      isDiscovered: true
    };
  }
  // Generic fallback if clean binary name
  const cleanBinary = cleanId.replace(/[^a-zA-Z0-9._+-]/g, '');
  if (cleanBinary) {
    return {
      id: cleanBinary,
      command: cleanBinary,
      title: cleanBinary.charAt(0).toUpperCase() + cleanBinary.slice(1),
      icon: '🐧',
      isDiscovered: true
    };
  }
  return null;
}

export async function getAllowedLinuxPocApps(distro = 'kali-linux') {
  const curated = Object.entries(ALLOWED_APPS).map(([id, value]) => ({ id, ...value }));
  try {
    const discovered = await scanDiscoveredLinuxApps(distro);
    const curatedIds = new Set(curated.map(c => c.id));
    const extra = discovered.filter(d => !curatedIds.has(d.id)).map(d => ({
      id: d.id,
      title: d.name,
      command: d.terminal ? `xterm -fa 'Monospace' -fs 11 -bg black -fg white -e ${d.command}` : d.command,
      category: d.category,
      icon: d.iconUrl || d.icon,
      isDiscovered: true
    }));
    return [...curated, ...extra];
  } catch {
    return curated;
  }
}

export function normalizePocApp(value) {
  const id = String(value || '').trim().toLowerCase();
  if (ALLOWED_APPS[id]) return id;
  if (/^[a-zA-Z0-9._+-]+$/.test(id)) return id;
  return null;
}

export function displayForPort(port) { return displayForXpraPort(port); }

export function buildXpraProbeCommand(appCommand) {
  const binary = String(appCommand || '').trim().split(/\s+/)[0];
  return ['set -eu', 'command -v xpra >/dev/null 2>&1 || { echo XPRA_MISSING; exit 41; }', `command -v ${shellQuote(binary)} >/dev/null 2>&1 || { echo APP_MISSING:${binary}; exit 42; }`, 'xpra --version'].join('; ');
}

export function buildXpraStartCommand({ appCommand, port, sessionId = 'cloudos-poc1', password = 'test-only-secret' }) {
  if (!Number.isInteger(port) || port < PORT_START || port > PORT_END) throw new Error('Porta Xpra fora da faixa da POC.');
  if (!password || String(password).length < 16) throw new Error('Capability Xpra inválida.');
  const display = displayForPort(port);
  const firefoxProfile = String(appCommand || '').match(/(?:^|\s)--profile\s+(\/tmp\/cloudos-firefox-poc-[a-zA-Z0-9._-]+)/)?.[1] || null;
  const wrappedChild = `dbus-run-session -- ${appCommand}`;
  return [
    'set -eu',
    'mkdir -p -m 1777 /tmp/.X11-unix /run/xpra 2>/dev/null || true',
    'mount -o remount,rw /tmp/.X11-unix 2>/dev/null || true',
    'chmod 1777 /tmp/.X11-unix /run/xpra 2>/dev/null || true',
    'rm -f /tmp/cloudos-*-poc/.parentlock /tmp/cloudos-*-poc/lock /tmp/cloudos-*-poc/SingletonLock 2>/dev/null || true',
    'unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET PULSE_SERVER',
    'export GDK_BACKEND=x11',
    'export QT_QPA_PLATFORM=xcb',
    'export SDL_VIDEODRIVER=x11',
    'export CLUTTER_BACKEND=x11',
    'export XDG_SESSION_TYPE=x11',
    'export MOZ_ENABLE_WAYLAND=0',
    'export ELECTRON_OZONE_PLATFORM_HINT=x11',
    'export LIBGL_ALWAYS_SOFTWARE=1',
    'export MOZ_X11_EGL=0',
    'export NO_AT_BRIDGE=1',
    ...(firefoxProfile ? [`install -d -m 700 ${shellQuote(firefoxProfile)}`] : []),
    `export XPRA_PASSWORD=${shellQuote(password)}`,
    `exec xpra seamless :${display} --socket-dirs=/run/xpra --session-name=${shellQuote(`cloudos-poc1-${sessionId}`)} --start-child=${shellQuote(wrappedChild)} --exit-with-children=yes --daemon=no --clipboard=no --printing=no --file-transfer=no --webcam=no --audio=no --speaker=no --microphone=no --notifications=no --mdns=no --dbus-launch=no --dbus-control=no --start-new-commands=no --bind=noabstract --bind-tcp=${XPRA_BIND_TCP_HOST}:${port},auth=env --video=no --html=on`,
  ].join('; ');
}

async function execWsl(distribution, command, timeout = HEALTH_TIMEOUT_MS) { return execFileAsync(WSL_EXE, ['-d', distribution, '--exec', 'sh', '-c', command], { windowsHide: true, env: safeChildEnvironment(), timeout, maxBuffer: 512 * 1024 }); }

export async function checkWslInteropDisabled(distribution) {
  const started = Date.now();
  try {
    const { stdout } = await execWsl(distribution, 'cat /proc/sys/fs/binfmt_misc/WSLInterop 2>/dev/null || true', 2000);
    const text = String(stdout || '').trim();
    if (text === 'disabled') return { ok: true, code: 'WSL_INTEROP_DISABLED', error: null, evidence: 'DISABLED', durationMs: elapsedMs(started) };
    if (!text) return { ok: true, code: 'WSL_INTEROP_NOT_REGISTERED', error: null, evidence: 'UNAVAILABLE', durationMs: elapsedMs(started) };
    return { ok: false, code: 'WSL_INTEROP_ENABLED', error: 'WSL interop está habilitado. A POC 1 exige interop desabilitado.', evidence: 'ENABLED', durationMs: elapsedMs(started) };
  } catch (error) {
    return { ok: false, code: 'WSL_INTEROP_CHECK_FAILED', error: error.message, evidence: 'ERROR', durationMs: elapsedMs(started) };
  }
}

async function getDistroInfo(distribution) { const { stdout } = await execWsl(distribution, 'uname -s; uname -r; cat /etc/os-release 2>/dev/null || true', 3000); const lines = String(stdout || '').split('\n'); return { kernel: lines[0] || 'Linux', release: lines[1] || 'unknown', prettyName: lines.find(l => l.startsWith('PRETTY_NAME='))?.split('=')[1]?.replace(/"/g, '') || distribution }; }
async function probe(distribution, appCommand) { try { const { stdout } = await execWsl(distribution, buildXpraProbeCommand(appCommand), 4000); const versionLine = String(stdout || '').split('\n').find(l => l.includes('xpra v') || l.includes('xpra')) || 'xpra v6'; return { ok: true, version: versionLine.trim() }; } catch (error) { const text = `${error.stdout || ''} ${error.stderr || ''}`; if (text.includes('XPRA_MISSING')) throw createPocError('XPRA_NOT_INSTALLED', 'Xpra não está instalado.'); if (text.includes('APP_MISSING:')) throw createPocError('XPRA_APP_MISSING', 'Aplicativo X11 não instalado.'); throw createPocError('XPRA_PROBE_FAILED', error.message); } }
async function probeWslServer({ distribution, display }) { try { const { stdout } = await execWsl(distribution, `xpra info :${Number(display)} >/dev/null 2>&1 && echo OK || true`, 2000); return { ok: String(stdout || '').includes('OK') }; } catch { return { ok: false }; } }
async function probeWindowsTcp(port, timeoutMs = 400) {
  const started = Date.now();
  return new Promise(resolve => {
    const socket = net.createConnection({ host: '127.0.0.1', port });
    let resolved = false;
    const finish = ok => {
      if (resolved) return;
      resolved = true;
      socket.destroy();
      resolve({ ok, port, durationMs: elapsedMs(started) });
    };
    socket.once('connect', () => finish(true));
    socket.once('error', () => finish(false));
    socket.setTimeout(timeoutMs, () => finish(false));
  });
}
async function probeHttp(port, password, timeoutMs = 800) {
  const started = Date.now();
  const headers = password ? { Authorization: `Basic ${Buffer.from(`:${password}`).toString('base64')}` } : {};
  try {
    const res = await fetch(`http://127.0.0.1:${port}/`, { method: 'GET', headers, signal: AbortSignal.timeout(timeoutMs) });
    return { ok: [200, 401, 403].includes(res.status), status: res.status, durationMs: elapsedMs(started) };
  } catch (cause) {
    return { ok: false, error: cause.message, durationMs: elapsedMs(started) };
  }
}
async function probeWebSocket(port, password, timeoutMs = 800) {
  const started = Date.now();
  const headers = password ? { Authorization: `Basic ${Buffer.from(`:${password}`).toString('base64')}` } : {};
  return new Promise(resolve => {
    let done = false;
    const socket = new WebSocket(`ws://127.0.0.1:${port}/`, ['binary'], { handshakeTimeout: timeoutMs, origin: `http://127.0.0.1:${port}`, headers });
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

async function waitForWindowsTransport(session, child) {
  const deadline = Date.now() + START_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw createPocError('XPRA_EXITED_EARLY', 'Xpra terminou durante transporte.');
    const tcp = await probeWindowsTcp(session.port, 300);
    if (tcp.ok) {
      const http = await probeHttp(session.port, session.xpraPassword, 300);
      if (http.ok) return { tcp, http };
    }
    await new Promise(r => setTimeout(r, 80));
  }
  throw createPocError('XPRA_WINDOWS_TRANSPORT_TIMEOUT', 'Transporte Xpra indisponível no Windows.');
}

const readinessCache = new Map();

export function getXpraPocSession(id = null) { return id ? publicSession(sessions.get(id)) : publicSession([...sessions.values()][0] || null); }
export function getXpraPocSessions(ownerId = null) { const owner = ownerId ? normalizeOwnerId(ownerId) : null; return [...sessions.values()].filter(s => !owner || s.ownerId === owner).map(publicSession); }

export async function checkXpraPocReadiness({ app = 'xclock', distribution, force = false } = {}) {
  const started = Date.now();
  const checks = { wsl: { ok: false }, distribution: { ok: false }, interop: { ok: false }, xpra: { ok: false }, app: { ok: false }, port: { ok: false }, windowsLoopback: { ok: null }, websocket: { ok: null }, orphans: { ok: true, count: 0 } };

  const snapshot = await getWslSnapshot();
  checks.wsl = { ok: snapshot.installed && snapshot.operational };
  if (!checks.wsl.ok) return { ready: false, errorCode: snapshot.errorCode || 'WSL_UNAVAILABLE', error: snapshot.error || 'WSL indisponível.', checks, durationMs: elapsedMs(started) };
  
  const selected = typeof distribution === 'string' && distribution.trim() ? distribution.trim() : snapshot.preferred || snapshot.default || 'kali-linux';
  checks.distribution = { ok: true, name: selected };

  const appDef = await resolvePocApp(app, selected);
  if (!appDef) return { ready: false, errorCode: 'LINUX_POC_APP_NOT_ALLOWED', error: 'Aplicativo não permitido.', checks, durationMs: elapsedMs(started) };

  const cacheKey = `${appDef.id}:${selected}`;
  const cached = readinessCache.get(cacheKey);
  if (!force && cached && (Date.now() - cached.time < 300_000)) {
    return { ...cached.data, durationMs: 0 };
  }

  const interop = await checkWslInteropDisabled(selected);
  checks.interop = interop;
  if (!interop.ok) return { ready: false, errorCode: interop.code || 'WSL_INTEROP_ENABLED', error: interop.error || 'POC1 exige WSL interoperability desabilitado e reinício da distro antes de iniciar.', distribution: selected, checks, durationMs: elapsedMs(started) };

  try {
    const result = await probe(selected, appDef.command);
    checks.xpra = { ok: true, version: result.version };
    checks.app = { ok: true, command: appDef.command };
  } catch (cause) {
    return { ready: false, errorCode: cause.code, error: cause.message, distribution: selected, checks, durationMs: elapsedMs(started) };
  }

  const orphans = await inspectOwnedOrphans({ distribution: selected });
  if (orphans.length) {
    for (const orphan of orphans) {
      await stopLedgerEntry(orphan).catch(() => undefined);
    }
  }
  checks.orphans = { ok: true, count: 0, sessions: [] };

  const candidatePort = PORT_START + (nextPortOffset % 40);
  const candidateDisplay = DISPLAY_START + (nextPortOffset % 40);
  checks.port = { ok: true, candidate: candidatePort, display: candidateDisplay };

  const result = { ready: true, app: appDef.id, distribution: selected, checks, durationMs: elapsedMs(started) };
  readinessCache.set(cacheKey, { time: Date.now(), data: result });
  return result;
}

async function inspectOwnedOrphans({ distribution = null } = {}) {
  const ledger = readLedger();
  const orphans = [];
  for (const entry of ledger) {
    if (sessions.has(entry.id)) continue;
    const pair = validateLedgerPair(entry);
    if (!pair.ok) { orphans.push({ ...entry, classification: pair.code }); continue; }
    if (distribution && entry.distribution !== distribution) continue;
    if (!await validateInstalledAsync(entry.distribution)) continue;
    const linux = await probeWslServer({ distribution: entry.distribution, display: entry.display });
    const tcp = await probeWindowsTcp(entry.port, 500);
    if (linux.ok || tcp.ok) orphans.push({ ...entry, linuxAlive: linux.ok, windowsPortAlive: tcp.ok });
  }
  return orphans;
}

async function stopLedgerEntry(entry) {
  if (await validateInstalledAsync(entry.distribution)) {
    await execWsl(entry.distribution, `xpra stop :${Number(entry.display)} >/dev/null 2>&1 || true`, STOP_TIMEOUT_MS).catch(() => undefined);
  }
}

export async function cleanupXpraPoc({ ownerId = null, orphansOnly = false } = {}) {
  return queueLifecycle(async () => {
    const owner = ownerId ? normalizeOwnerId(ownerId) : null;
    const stopped = [];
    if (!orphansOnly) {
      for (const session of [...sessions.values()].filter(s => !owner || s.ownerId === owner)) {
        await stopSessionInternal(session);
        stopped.push(session.id);
      }
    }
    for (const entry of readLedger().filter(e => !sessions.has(e.id) && (!owner || e.ownerId === owner))) {
      await stopLedgerEntry(entry);
      stopped.push(entry.id);
    }
    writeLedger();
    return { cleaned: [...new Set(stopped)], remaining: getXpraPocSessions(owner) };
  });
}

function diagnosticsFor(session) { return session.diagnostics.join('').slice(-6000); }

async function inspectSessionPids(distribution, display, appCommand) {
  try {
    const binary = path.posix.basename(String(appCommand || '').trim().split(/\s+/)[0]);
    if (!/^[a-zA-Z0-9._+-]+$/.test(binary)) return { xpra: null, app: null, xorg: null };
    const runtimeDirectory = `/run/xpra/${Number(display)}`;
    const cmd = `server_pid="$(cat ${runtimeDirectory}/server.pid 2>/dev/null || true)"; printf '%s\n' "$server_pid"; echo '---'; if [ -n "$server_pid" ]; then pgrep -P "$server_pid" -x ${shellQuote(binary)} | head -n 1; fi; echo '---'; cat ${runtimeDirectory}/xvfb.pid 2>/dev/null || true`;
    const { stdout } = await execWsl(distribution, cmd, 3000);
    const parts = String(stdout || '').split('---').map(s => Number(s.trim())).map(n => Number.isInteger(n) && n > 0 ? n : null);
    return { xpra: parts[0] || null, app: parts[1] || null, xorg: parts[2] || null };
  } catch {
    return { xpra: null, app: null, xorg: null };
  }
}

async function isPortFree(port) {
  return new Promise(resolve => {
    const server = net.createServer();
    server.unref();
    server.once('error', () => resolve(false));
    server.listen({ host: '127.0.0.1', port, exclusive: true }, () => {
      server.close(() => resolve(true));
    });
  });
}

let nextPortOffset = 0;
async function reservePair(distro) {
  for (let i = 0; i < 40; i++) {
    const offset = (nextPortOffset++) % 40;
    const port = PORT_START + offset;
    const display = DISPLAY_START + offset;
    if (!reservedPorts.has(port) && await isPortFree(port)) {
      reservedPorts.add(port);
      return { port, display, distribution: distro };
    }
  }
  throw createPocError('XPRA_PAIR_UNAVAILABLE', 'Nenhum par display/porta livre no momento.');
}

function releasePort(port) {
  reservedPorts.delete(port);
}

export async function startXpraPoc({ app, distribution, ownerId, generation = 1, filePath = null } = {}) {
  return queueLifecycle(async () => {
    const snapshot = await getWslSnapshot();
    const distro = typeof distribution === 'string' && distribution.trim() ? distribution.trim() : snapshot.preferred || snapshot.default || 'kali-linux';
    const appDef = await resolvePocApp(app || 'firefox', distro);
    if (!appDef) throw createPocError('LINUX_POC_APP_NOT_ALLOWED', 'Aplicativo não permitido.');
    const appId = appDef.id;
    const owner = normalizeOwnerId(ownerId);

    const existing = [...sessions.values()].find(s => s.ownerId === owner && s.app === appId && ['starting', 'ready', 'degraded'].includes(s.state));
    if (existing) return publicSession(existing);

    if ([...sessions.values()].filter(s => s.ownerId === owner && ['starting', 'ready', 'degraded'].includes(s.state)).length >= MAX_ACTIVE_SESSIONS) {
      throw createPocError('LINUX_POC_SESSION_LIMIT', 'Limite de sessões atingido.');
    }

    const readiness = await checkXpraPocReadiness({ app: appId, distribution: distro });
    if (!readiness.ready) throw createPocError(readiness.errorCode, readiness.error, readiness.checks);

    const pair = await reservePair(readiness.distribution);
    const id = `xpra-${Date.now().toString(36)}-${crypto.randomBytes(4).toString('hex')}`;
    const startedAt = new Date().toISOString();
    const leaseExpiresAt = Date.now() + LEASE_TTL_MS;

    const session = {
      id,
      generation,
      ownerId: owner,
      proxyToken: crypto.randomBytes(24).toString('hex'),
      xpraPassword: crypto.randomBytes(32).toString('base64url'),
      app: appId,
      title: appDef.title || appDef.name || appId,
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

    let appCommand = appDef.command.replaceAll('{sessionId}', id);
    if (filePath && typeof filePath === 'string' && filePath.trim()) {
      let linuxPath = filePath.trim();
      if (/^[a-zA-Z]:[\\/]/.test(linuxPath)) {
        const drive = linuxPath.charAt(0).toLowerCase();
        linuxPath = `/mnt/${drive}/${linuxPath.slice(3).replace(/\\/g, '/')}`;
      }
      if (/%[fFuU]/.test(appCommand)) {
        appCommand = appCommand.replace(/%[fFuU]/g, shellQuote(linuxPath));
      } else {
        appCommand = `${appCommand} ${shellQuote(linuxPath)}`;
      }
    }

    sessions.set(id, session);
    writeLedger();
    const startClock = Date.now();
    const command = buildXpraStartCommand({ appCommand, port: pair.port, sessionId: id, password: session.xpraPassword });

    const child = spawn(WSL_EXE, ['-d', session.distribution, '--exec', 'sh', '-c', command], {
      windowsHide: true,
      env: safeChildEnvironment(),
      stdio: ['ignore', 'pipe', 'pipe']
    });
    session.child = child;

    for (const stream of [child.stdout, child.stderr]) {
      stream.on('data', chunk => {
        session.diagnostics.push(String(chunk));
        while (session.diagnostics.join('').length > 65536) session.diagnostics.shift();
      });
    }

    child.once('exit', code => {
      releasePort(session.port);
      if (!['stopping', 'stopped'].includes(session.state)) {
        session.state = 'failed';
        session.errorCode = 'XPRA_PROCESS_EXITED';
        session.error = `Xpra encerrou (exit=${code}). ${diagnosticsFor(session)}`;
      }
      writeLedger();
    });

    try {
      await withTimeout(waitForWindowsTransport(session, child), START_TIMEOUT_MS, 'XPRA_WINDOWS_TRANSPORT_TIMEOUT', 'Timeout transporte.');
      session.metrics.windowsTransportReadyMs = elapsedMs(startClock);
      inspectSessionPids(session.distribution, session.display, appCommand).then(pids => {
        session.xpraPid = pids.xpra;
        session.appPid = pids.app;
        session.xorgPid = pids.xorg;
        writeLedger();
      }).catch(() => undefined);
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
