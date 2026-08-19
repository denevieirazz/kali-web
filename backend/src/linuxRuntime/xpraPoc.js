import { execFile, spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { WebSocket } from 'ws';
import {
  WSL_EXE,
  getWslSnapshot,
  normalizeName,
  safeChildEnvironment,
  validateInstalledAsync,
} from '../wsl/distroService.js';
import {
  XPRA_DISPLAY_END,
  XPRA_DISPLAY_START,
  XPRA_PORT_END,
  XPRA_PORT_START,
  chooseXpraPair,
  displayForPort as displayForXpraPort,
  validateLedgerPair,
} from './xpraPairAllocator.js';

const execFileAsync = promisify(execFile);
const PORT_START = XPRA_PORT_START;
const PORT_END = XPRA_PORT_END;
const DISPLAY_START = XPRA_DISPLAY_START;
const DISPLAY_END = XPRA_DISPLAY_END;
const MAX_ACTIVE_SESSIONS = 4;
const START_TIMEOUT_MS = 25_000;
const HEALTH_TIMEOUT_MS = 4_000;
const STOP_TIMEOUT_MS = 6_000;
const LEDGER_FILE = path.join(os.tmpdir(), 'cloudos-linux-runtime-poc1-sessions.json');
const OWNER_ID = /^[a-zA-Z0-9._:-]{1,128}$/;
const ALLOWED_APPS = Object.freeze({
  xclock: { command: 'xclock', title: 'XClock' },
  xeyes: { command: 'xeyes', title: 'XEyes' },
  xterm: { command: 'xterm', title: 'XTerm' },
  gedit: { command: 'gedit', title: 'Gedit' },
});

const sessions = new Map();
const reservedPorts = new Set();
let lifecycleQueue = Promise.resolve();

function queueLifecycle(operation) {
  const next = lifecycleQueue.then(operation, operation);
  lifecycleQueue = next.catch(() => undefined);
  return next;
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'"'"'`)}'`;
}

function createPocError(code, message, details = null) {
  const error = new Error(message);
  error.code = code;
  if (details) error.details = details;
  return error;
}

function normalizeOwnerId(value) {
  const ownerId = String(value || 'cloudos-poc1').trim();
  if (!OWNER_ID.test(ownerId)) throw createPocError('LINUX_POC_OWNER_INVALID', 'Identificador da CloudOS Window inválido.');
  return ownerId;
}

function serializeLedgerSession(session) {
  return {
    id: session.id,
    ownerId: session.ownerId,
    app: session.app,
    title: session.title,
    distribution: session.distribution,
    port: session.port,
    display: session.display,
    startedAt: session.startedAt,
  };
}

function readLedger() {
  try {
    const parsed = JSON.parse(fs.readFileSync(LEDGER_FILE, 'utf8'));
    return Array.isArray(parsed?.sessions) ? parsed.sessions : [];
  } catch {
    return [];
  }
}

function writeLedger() {
  const live = [...sessions.values()]
    .filter(session => !['stopped', 'failed'].includes(session.state))
    .map(serializeLedgerSession);
  try {
    if (live.length === 0) {
      fs.rmSync(LEDGER_FILE, { force: true });
      return;
    }
    const temp = `${LEDGER_FILE}.tmp`;
    fs.writeFileSync(temp, JSON.stringify({ version: 1, sessions: live }, null, 2), 'utf8');
    fs.renameSync(temp, LEDGER_FILE);
  } catch {
    // O ledger é diagnóstico/recuperação. Falha de gravação não deve derrubar o CloudOS.
  }
}

function elapsedMs(start) {
  return Math.max(0, Date.now() - start);
}

function timedMetric(session, name, start) {
  const value = elapsedMs(start);
  session.metrics[name] = value;
  return value;
}

function withTimeout(promise, timeoutMs, code, message) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(createPocError(code, message)), timeoutMs);
      timer.unref?.();
    }),
  ]).finally(() => clearTimeout(timer));
}

export function getAllowedLinuxPocApps() {
  return Object.entries(ALLOWED_APPS).map(([id, value]) => ({ id, ...value }));
}

export function normalizePocApp(value) {
  const id = String(value || '').trim().toLowerCase();
  return ALLOWED_APPS[id] ? id : null;
}

export function buildXpraProbeCommand(appCommand) {
  return [
    'set -eu',
    'command -v xpra >/dev/null 2>&1 || { echo XPRA_MISSING; exit 41; }',
    `command -v ${shellQuote(appCommand)} >/dev/null 2>&1 || { echo APP_MISSING:${appCommand}; exit 42; }`,
    'xpra --version',
  ].join('; ');
}

export function displayForPort(port) {
  return displayForXpraPort(port);
}

export function buildXpraStartCommand({ appCommand, port, sessionId = 'cloudos-poc1' }) {
  if (!Number.isInteger(port) || port < PORT_START || port > PORT_END) throw new Error('Porta Xpra fora da faixa da POC.');
  const display = displayForPort(port);
  return [
    'set -eu',
    'unset DISPLAY WAYLAND_DISPLAY PULSE_SERVER',
    `exec xpra seamless :${display} --session-name=${shellQuote(`cloudos-poc1-${sessionId}`)} --start-child=${shellQuote(appCommand)} --exit-with-children=yes --daemon=no --mdns=no --notifications=no --printing=no --file-transfer=no --start-new-commands=no --bind=noabstract --bind-tcp=127.0.0.1:${port},auth=allow --html=on`,
  ].join('; ');
}

async function execWsl(distribution, command, timeout = HEALTH_TIMEOUT_MS) {
  return execFileAsync(WSL_EXE, ['-d', distribution, '--', 'sh', '-lc', command], {
    windowsHide: true,
    env: safeChildEnvironment(),
    timeout,
    maxBuffer: 512 * 1024,
  });
}

async function isPortFree(port) {
  if (reservedPorts.has(port)) return false;
  return new Promise((resolve) => {
    const server = net.createServer();
    server.unref();
    server.once('error', () => resolve(false));
    server.listen({ host: '127.0.0.1', port, exclusive: true }, () => server.close(() => resolve(true)));
  });
}

async function scanOccupiedDisplays(distribution) {
  const command = [
    `for n in $(seq ${DISPLAY_START} ${DISPLAY_END}); do`,
    'if [ -S "/tmp/.X11-unix/X$n" ] || [ -e "/tmp/.X$n-lock" ]; then echo "$n"; fi;',
    'done',
  ].join(' ');
  try {
    const { stdout } = await execWsl(distribution, command, 5000);
    return String(stdout || '')
      .split(/\r?\n/)
      .map(value => Number(value.trim()))
      .filter(display => Number.isInteger(display) && display >= DISPLAY_START && display <= DISPLAY_END);
  } catch (cause) {
    throw createPocError('XPRA_DISPLAY_SCAN_FAILED', `Não foi possível inspecionar DISPLAY ${DISPLAY_START}-${DISPLAY_END} em ${distribution}: ${cause.message}`);
  }
}

async function findFreePair(distribution) {
  const occupiedDisplays = await scanOccupiedDisplays(distribution);
  const freePorts = [];
  for (let port = PORT_START; port <= PORT_END; port += 1) {
    if (await isPortFree(port)) freePorts.push(port);
  }
  return chooseXpraPair({ occupiedDisplays, freePorts });
}

async function reservePair(distribution) {
  const pair = await findFreePair(distribution);
  if (!pair) {
    throw createPocError(
      'XPRA_PAIR_UNAVAILABLE',
      `Nenhum par DISPLAY/porta livre entre :${DISPLAY_START}-:${DISPLAY_END} e ${PORT_START}-${PORT_END}.`,
    );
  }
  reservedPorts.add(pair.port);
  return pair;
}

function releasePort(port) {
  reservedPorts.delete(port);
}

async function chooseDistribution(requested, snapshot = null) {
  if (requested) {
    const distribution = normalizeName(requested);
    if (!await validateInstalledAsync(distribution)) {
      throw createPocError('WSL_DISTRO_NOT_INSTALLED', `Distribuição WSL não instalada: ${distribution || '(vazia)'}`);
    }
    return distribution;
  }
  const current = snapshot || await getWslSnapshot();
  if (!current.installed) throw createPocError('WSL_NOT_FOUND', current.error || 'WSL não está instalado neste host Windows.');
  if (!current.operational) throw createPocError(current.errorCode || 'WSL_UNAVAILABLE', current.error || 'WSL não está operacional.');
  if (!current.distributions.length) throw createPocError('WSL_DISTRO_MISSING', 'WSL está disponível, mas nenhuma distribuição está instalada.');
  return current.preferred || current.default || current.distributions[0].name;
}

async function probe(distribution, appCommand) {
  const started = Date.now();
  try {
    const { stdout, stderr } = await execWsl(distribution, buildXpraProbeCommand(appCommand), 15_000);
    return {
      ok: true,
      durationMs: elapsedMs(started),
      version: String(stdout || stderr || '').trim().split(/\r?\n/).filter(Boolean).at(-1) || 'xpra',
    };
  } catch (cause) {
    const text = `${cause.stdout || ''}\n${cause.stderr || ''}`;
    if (text.includes('XPRA_MISSING')) throw createPocError('XPRA_MISSING', `Xpra não está instalado na distribuição ${distribution}.`);
    if (text.includes('APP_MISSING:')) throw createPocError('LINUX_POC_APP_MISSING', `${appCommand} não está instalado na distribuição ${distribution}.`);
    throw createPocError(cause.code === 'ETIMEDOUT' ? 'XPRA_PROBE_TIMEOUT' : 'XPRA_PROBE_FAILED', `Não foi possível validar Xpra/${appCommand} em ${distribution}: ${cause.message}`);
  }
}

async function probeWslServer(session) {
  const started = Date.now();
  try {
    await execWsl(session.distribution, `xpra info :${session.display} >/dev/null 2>&1`, HEALTH_TIMEOUT_MS);
    return { ok: true, durationMs: elapsedMs(started) };
  } catch (cause) {
    return { ok: false, durationMs: elapsedMs(started), error: cause.message };
  }
}

async function probeWindowsTcp(port, timeoutMs = 1500) {
  const started = Date.now();
  return new Promise((resolve) => {
    const socket = net.createConnection({ host: '127.0.0.1', port });
    let settled = false;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      resolve({ ...result, durationMs: elapsedMs(started) });
    };
    socket.setTimeout(timeoutMs, () => finish({ ok: false, error: 'timeout' }));
    socket.once('connect', () => finish({ ok: true }));
    socket.once('error', error => finish({ ok: false, error: error.message }));
  });
}

async function probeHttp(port, timeoutMs = 1500) {
  const started = Date.now();
  try {
    const response = await fetch(`http://127.0.0.1:${port}/`, { signal: AbortSignal.timeout(timeoutMs) });
    const body = await response.text();
    const contentType = response.headers.get('content-type') || '';
    const looksLikeHtmlClient = /html/i.test(contentType) && /xpra/i.test(body.slice(0, 32_000));
    return {
      ok: response.ok && looksLikeHtmlClient,
      durationMs: elapsedMs(started),
      status: response.status,
      contentType,
      embeddingHeaders: {
        xFrameOptions: response.headers.get('x-frame-options'),
        contentSecurityPolicy: response.headers.get('content-security-policy'),
      },
      error: response.ok && looksLikeHtmlClient ? null : `HTTP ${response.status}; cliente HTML5 Xpra não confirmado`,
    };
  } catch (cause) {
    return { ok: false, durationMs: elapsedMs(started), error: cause.message };
  }
}

async function probeWebSocket(port, timeoutMs = 2000) {
  const started = Date.now();
  return new Promise((resolve) => {
    let settled = false;
    const socket = new WebSocket(`ws://127.0.0.1:${port}/`, {
      handshakeTimeout: timeoutMs,
      origin: `http://127.0.0.1:${port}`,
    });
    const timer = setTimeout(() => finish({ ok: false, error: 'timeout' }), timeoutMs + 100);
    timer.unref?.();
    function finish(result) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { socket.terminate(); } catch {}
      resolve({ ...result, durationMs: elapsedMs(started) });
    }
    socket.once('open', () => finish({ ok: true }));
    socket.once('error', error => finish({ ok: false, error: error.message }));
    socket.once('unexpected-response', (_request, response) => finish({ ok: false, error: `HTTP ${response.statusCode}` }));
  });
}

async function waitForWslServer(session, child) {
  const deadline = Date.now() + START_TIMEOUT_MS;
  let last = null;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw createPocError('XPRA_EXITED_EARLY', `Xpra terminou antes de ficar pronto (exit=${child.exitCode}).`);
    last = await probeWslServer(session);
    if (last.ok) return last;
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  throw createPocError('XPRA_SERVER_TIMEOUT', `Xpra não ficou saudável no WSL em ${START_TIMEOUT_MS}ms.`, last);
}

async function waitForWindowsTransport(session, child) {
  const deadline = Date.now() + START_TIMEOUT_MS;
  let lastTcp = null;
  let lastHttp = null;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw createPocError('XPRA_EXITED_EARLY', `Xpra terminou durante a publicação do transporte (exit=${child.exitCode}).`);
    lastTcp = await probeWindowsTcp(session.port);
    if (lastTcp.ok) {
      lastHttp = await probeHttp(session.port);
      if (lastHttp.ok) return { tcp: lastTcp, http: lastHttp };
    }
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  const linux = await probeWslServer(session);
  if (linux.ok) {
    throw createPocError(
      'XPRA_WINDOWS_LOOPBACK_BLOCKED',
      `Xpra está saudável dentro do WSL, mas Windows não alcança 127.0.0.1:${session.port}. Verifique localhostForwarding/rede espelhada e firewall local.`,
      { tcp: lastTcp, http: lastHttp },
    );
  }
  throw createPocError('XPRA_HTTP_UNAVAILABLE', `Xpra não publicou o cliente HTML5 em 127.0.0.1:${session.port}.`, { tcp: lastTcp, http: lastHttp });
}

function publicMetrics(session) {
  return {
    preflightMs: session.metrics.preflightMs ?? null,
    wslServerReadyMs: session.metrics.wslServerReadyMs ?? null,
    windowsTransportReadyMs: session.metrics.windowsTransportReadyMs ?? null,
    bootMs: session.metrics.bootMs ?? null,
    websocketHandshakeMs: session.metrics.websocketHandshakeMs ?? null,
    lastHealthMs: session.metrics.lastHealthMs ?? null,
    iframeLoadMs: session.metrics.iframeLoadMs ?? null,
    firstRemoteWindowMs: session.metrics.firstRemoteWindowMs ?? null,
    reconnectCount: session.metrics.reconnectCount ?? 0,
    restartCount: session.metrics.restartCount ?? 0,
    healthFailures: session.metrics.healthFailures ?? 0,
    proxyHttpRequests: session.metrics.proxyHttpRequests ?? 0,
    proxyWebSocketConnections: session.metrics.proxyWebSocketConnections ?? 0,
  };
}

function proxyPath(session) {
  return `/__cloudos/linux-runtime/poc1/${session.id}/${session.proxyToken}/`;
}

function publicSession(session) {
  if (!session) return null;
  return {
    id: session.id,
    ownerId: session.ownerId,
    app: session.app,
    title: session.title,
    distribution: session.distribution,
    port: session.port,
    display: session.display,
    state: session.state,
    startedAt: session.startedAt,
    clientUrl: ['ready', 'degraded'].includes(session.state)
      ? `${proxyPath(session)}?clipboard=yes&keyboard=yes&floating_menu=no&reconnect=yes`
      : null,
    xpraVersion: session.xpraVersion,
    error: session.error || null,
    errorCode: session.errorCode || null,
    health: session.health || null,
    metrics: publicMetrics(session),
  };
}

export function getXpraPocSession(id = null) {
  if (id) return publicSession(sessions.get(id));
  return publicSession([...sessions.values()][0] || null);
}

export function getXpraPocSessions(ownerId = null) {
  const normalizedOwner = ownerId ? normalizeOwnerId(ownerId) : null;
  return [...sessions.values()]
    .filter(session => !normalizedOwner || session.ownerId === normalizedOwner)
    .map(publicSession);
}

export async function checkXpraPocReadiness({ app = 'xclock', distribution } = {}) {
  const started = Date.now();
  const appId = normalizePocApp(app);
  const checks = {
    wsl: { ok: false },
    distribution: { ok: false },
    xpra: { ok: false },
    app: { ok: false },
    port: { ok: false },
    windowsLoopback: { ok: null, state: 'pending-live-session' },
    websocket: { ok: null, state: 'pending-live-session' },
    orphans: { ok: true, count: 0 },
  };
  if (!appId) {
    return { ready: false, errorCode: 'LINUX_POC_APP_NOT_ALLOWED', error: 'Aplicativo não permitido na POC 1.', checks, durationMs: elapsedMs(started) };
  }

  const snapshot = await getWslSnapshot();
  checks.wsl = { ok: snapshot.installed, operational: snapshot.operational, errorCode: snapshot.errorCode, error: snapshot.error };
  if (!snapshot.installed) return { ready: false, errorCode: 'WSL_NOT_FOUND', error: snapshot.error || 'WSL ausente.', checks, durationMs: elapsedMs(started) };
  if (!snapshot.operational) return { ready: false, errorCode: snapshot.errorCode || 'WSL_UNAVAILABLE', error: snapshot.error || 'WSL indisponível.', checks, durationMs: elapsedMs(started) };
  if (!snapshot.distributions.length) return { ready: false, errorCode: 'WSL_DISTRO_MISSING', error: 'Nenhuma distribuição WSL instalada.', checks, durationMs: elapsedMs(started) };

  let selected;
  try {
    selected = await chooseDistribution(distribution, snapshot);
    checks.distribution = { ok: true, name: selected };
  } catch (cause) {
    checks.distribution = { ok: false, error: cause.message };
    return { ready: false, errorCode: cause.code, error: cause.message, checks, durationMs: elapsedMs(started) };
  }

  try {
    const result = await probe(selected, ALLOWED_APPS[appId].command);
    checks.xpra = { ok: true, version: result.version, durationMs: result.durationMs };
    checks.app = { ok: true, command: ALLOWED_APPS[appId].command };
  } catch (cause) {
    if (cause.code === 'XPRA_MISSING') checks.xpra = { ok: false, error: cause.message };
    else checks.xpra = { ok: true, state: 'probe-reached' };
    if (cause.code === 'LINUX_POC_APP_MISSING') checks.app = { ok: false, command: ALLOWED_APPS[appId].command, error: cause.message };
    return { ready: false, errorCode: cause.code, error: cause.message, distribution: selected, checks, durationMs: elapsedMs(started) };
  }

  let pair;
  try {
    pair = await findFreePair(selected);
  } catch (cause) {
    checks.port = { ok: false, error: cause.message };
    return { ready: false, errorCode: cause.code || 'XPRA_PAIR_SCAN_FAILED', error: cause.message, distribution: selected, checks, durationMs: elapsedMs(started) };
  }
  checks.port = pair
    ? { ok: true, candidate: pair.port, display: pair.display, range: `${PORT_START}-${PORT_END}` }
    : { ok: false, error: `Nenhum par DISPLAY/porta livre em :${DISPLAY_START}-:${DISPLAY_END} / ${PORT_START}-${PORT_END}.` };
  if (!pair) return { ready: false, errorCode: 'XPRA_PAIR_UNAVAILABLE', error: 'Nenhum par DISPLAY/porta da POC está livre.', distribution: selected, checks, durationMs: elapsedMs(started) };

  const orphans = await inspectOwnedOrphans({ distribution: selected });
  checks.orphans = { ok: orphans.length === 0, count: orphans.length, sessions: orphans };
  if (orphans.length) {
    return {
      ready: false,
      errorCode: 'LINUX_POC_ORPHANED_SESSION',
      error: 'Sessão Xpra da POC sobreviveu ao backend. Execute cleanup antes de iniciar outra sessão.',
      distribution: selected,
      checks,
      durationMs: elapsedMs(started),
    };
  }

  return { ready: true, app: appId, distribution: selected, checks, durationMs: elapsedMs(started) };
}

async function inspectOwnedOrphans({ distribution = null } = {}) {
  const ledger = readLedger();
  const orphans = [];
  const survivors = [];
  for (const entry of ledger) {
    if (sessions.has(entry.id)) {
      survivors.push(entry);
      continue;
    }
    const ledgerPair = validateLedgerPair(entry);
    if (!ledgerPair.ok) {
      orphans.push({ ...entry, classification: ledgerPair.code, pairEvidence: ledgerPair.evidence });
      survivors.push(entry);
      continue;
    }
    if (distribution && entry.distribution !== distribution) {
      survivors.push(entry);
      continue;
    }
    if (!await validateInstalledAsync(entry.distribution)) continue;
    const probeSession = { distribution: entry.distribution, display: entry.display };
    const linux = await probeWslServer(probeSession);
    const tcp = await probeWindowsTcp(entry.port, 500);
    if (linux.ok || tcp.ok) {
      orphans.push({ ...entry, linuxAlive: linux.ok, windowsPortAlive: tcp.ok });
      survivors.push(entry);
    }
  }
  if (survivors.length !== ledger.length) {
    try {
      if (survivors.length) fs.writeFileSync(LEDGER_FILE, JSON.stringify({ version: 1, sessions: survivors }, null, 2), 'utf8');
      else fs.rmSync(LEDGER_FILE, { force: true });
    } catch {}
  }
  return orphans;
}

async function stopLedgerEntry(entry) {
  if (!await validateInstalledAsync(entry.distribution)) return;
  await execWsl(entry.distribution, `xpra stop :${Number(entry.display)} >/dev/null 2>&1 || true`, STOP_TIMEOUT_MS).catch(() => undefined);
}

export async function cleanupXpraPoc({ ownerId = null, orphansOnly = false } = {}) {
  return queueLifecycle(async () => {
    const normalizedOwner = ownerId ? normalizeOwnerId(ownerId) : null;
    const stopped = [];
    if (!orphansOnly) {
      const targets = [...sessions.values()].filter(session => !normalizedOwner || session.ownerId === normalizedOwner);
      for (const session of targets) {
        await stopSessionInternal(session);
        stopped.push(session.id);
      }
    }

    const ledger = readLedger();
    const orphanEntries = ledger.filter(entry => !sessions.has(entry.id) && (!normalizedOwner || entry.ownerId === normalizedOwner));
    for (const entry of orphanEntries) {
      await stopLedgerEntry(entry);
      releasePort(entry.port);
      stopped.push(entry.id);
    }

    const retained = readLedger().filter(entry => !stopped.includes(entry.id));
    try {
      if (retained.length) fs.writeFileSync(LEDGER_FILE, JSON.stringify({ version: 1, sessions: retained }, null, 2), 'utf8');
      else fs.rmSync(LEDGER_FILE, { force: true });
    } catch {}

    return { cleaned: [...new Set(stopped)], remaining: getXpraPocSessions(normalizedOwner) };
  });
}

function diagnosticsFor(session) {
  return session.diagnostics.join('').slice(-6000);
}

function captureDiagnostics(session, chunk) {
  session.diagnostics.push(String(chunk));
  while (session.diagnostics.join('').length > 64 * 1024) session.diagnostics.shift();
}

export async function startXpraPoc({ app, distribution, ownerId } = {}) {
  return queueLifecycle(async () => {
    const appId = normalizePocApp(app || 'xclock');
    if (!appId) throw createPocError('LINUX_POC_APP_NOT_ALLOWED', 'Aplicativo não permitido na POC 1.');
    const normalizedOwner = normalizeOwnerId(ownerId);

    const existing = [...sessions.values()].find(session => session.ownerId === normalizedOwner && session.app === appId && ['starting', 'ready', 'degraded'].includes(session.state));
    if (existing) return publicSession(existing);
    const ownerSessions = [...sessions.values()].filter(session => session.ownerId === normalizedOwner && ['starting', 'ready', 'degraded'].includes(session.state));
    if (ownerSessions.length >= MAX_ACTIVE_SESSIONS) throw createPocError('LINUX_POC_SESSION_LIMIT', `Limite da POC: ${MAX_ACTIVE_SESSIONS} aplicações simultâneas por CloudOS Window.`);

    const readiness = await checkXpraPocReadiness({ app: appId, distribution });
    if (!readiness.ready) throw createPocError(readiness.errorCode, readiness.error, readiness.checks);

    const selected = readiness.distribution;
    const definition = ALLOWED_APPS[appId];
    const pair = await reservePair(selected);
    const { port, display } = pair;
    const id = `xpra-${Date.now().toString(36)}-${crypto.randomBytes(4).toString('hex')}`;
    const session = {
      id,
      ownerId: normalizedOwner,
      proxyToken: crypto.randomBytes(24).toString('hex'),
      app: appId,
      title: definition.title,
      distribution: selected,
      port,
      display,
      state: 'starting',
      startedAt: new Date().toISOString(),
      xpraVersion: readiness.checks.xpra.version,
      child: null,
      error: null,
      errorCode: null,
      health: null,
      diagnostics: [],
      metrics: {
        preflightMs: readiness.durationMs,
        restartCount: 0,
        reconnectCount: 0,
        healthFailures: 0,
        proxyHttpRequests: 0,
        proxyWebSocketConnections: 0,
      },
    };
    sessions.set(id, session);
    writeLedger();

    const startClock = Date.now();
    const command = buildXpraStartCommand({ appCommand: definition.command, port, sessionId: id });
    const child = spawn(WSL_EXE, ['-d', selected, '--', 'sh', '-lc', command], {
      windowsHide: true,
      env: safeChildEnvironment(),
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    session.child = child;
    child.stdout.on('data', chunk => captureDiagnostics(session, chunk));
    child.stderr.on('data', chunk => captureDiagnostics(session, chunk));
    child.once('error', cause => {
      if (session.state === 'starting') {
        session.state = 'failed';
        session.errorCode = 'XPRA_PROCESS_SPAWN_FAILED';
        session.error = cause.message;
      }
    });
    child.once('exit', (code) => {
      releasePort(session.port);
      if (!['stopping', 'stopped'].includes(session.state)) {
        session.state = 'failed';
        session.errorCode = 'XPRA_PROCESS_EXITED';
        session.error = `Xpra encerrou (exit=${code}). ${diagnosticsFor(session)}`.trim();
      }
      writeLedger();
    });

    try {
      await withTimeout(waitForWslServer(session, child), START_TIMEOUT_MS, 'XPRA_SERVER_TIMEOUT', 'Timeout esperando o servidor Xpra dentro do WSL.');
      session.metrics.wslServerReadyMs = elapsedMs(startClock);
      await withTimeout(waitForWindowsTransport(session, child), START_TIMEOUT_MS, 'XPRA_WINDOWS_TRANSPORT_TIMEOUT', 'Timeout esperando o transporte Xpra no Windows.');
      session.metrics.windowsTransportReadyMs = elapsedMs(startClock);
      const ws = await probeWebSocket(port);
      session.metrics.websocketHandshakeMs = ws.durationMs;
      if (!ws.ok) throw createPocError('XPRA_WEBSOCKET_UNAVAILABLE', `HTTP Xpra respondeu, mas o WebSocket não abriu: ${ws.error}`);
      session.metrics.bootMs = elapsedMs(startClock);
      session.state = 'ready';
      session.health = { healthy: true, checkedAt: new Date().toISOString() };
      writeLedger();
      return publicSession(session);
    } catch (cause) {
      session.state = 'failed';
      session.errorCode = cause.code || 'XPRA_START_FAILED';
      session.error = `${cause.message}\n${diagnosticsFor(session)}`.trim();
      await stopSessionInternal(session).catch(() => undefined);
      throw createPocError(session.errorCode, session.error, cause.details);
    }
  });
}

export async function healthXpraPocSession(id) {
  const session = sessions.get(id);
  if (!session) throw createPocError('LINUX_POC_SESSION_NOT_FOUND', 'Sessão POC 1 não encontrada.');
  const started = Date.now();
  const linux = await probeWslServer(session);
  const tcp = await probeWindowsTcp(session.port);
  const http = tcp.ok ? await probeHttp(session.port) : { ok: false, error: 'TCP indisponível', durationMs: 0 };
  const websocket = http.ok ? await probeWebSocket(session.port) : { ok: false, error: 'HTTP indisponível', durationMs: 0 };
  const healthy = linux.ok && tcp.ok && http.ok && websocket.ok && session.child?.exitCode === null;
  session.metrics.lastHealthMs = timedMetric(session, 'lastHealthMs', started);
  session.metrics.websocketHandshakeMs = websocket.durationMs || session.metrics.websocketHandshakeMs;
  if (!healthy) session.metrics.healthFailures += 1;
  if (healthy && session.state === 'degraded') session.metrics.reconnectCount += 1;
  session.state = healthy ? 'ready' : session.state === 'stopping' ? 'stopping' : 'degraded';
  session.health = {
    healthy,
    checkedAt: new Date().toISOString(),
    linux,
    windowsTcp: tcp,
    http,
    websocket,
    classification: !linux.ok
      ? 'XPRA_SERVER_UNHEALTHY'
      : !tcp.ok
        ? 'XPRA_WINDOWS_LOOPBACK_BLOCKED'
        : !http.ok
          ? 'XPRA_HTTP_UNAVAILABLE'
          : !websocket.ok
            ? 'XPRA_WEBSOCKET_UNAVAILABLE'
            : null,
  };
  return { session: publicSession(session), health: session.health };
}

async function stopSessionInternal(session) {
  if (!session || session.state === 'stopped') return publicSession(session);
  session.state = 'stopping';
  await execWsl(session.distribution, `xpra stop :${session.display} >/dev/null 2>&1 || true`, STOP_TIMEOUT_MS).catch(() => undefined);
  if (session.child && session.child.exitCode === null) {
    try { session.child.kill(); } catch {}
  }
  session.state = 'stopped';
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
      if (ownerId && session.ownerId !== normalizeOwnerId(ownerId)) throw createPocError('LINUX_POC_SESSION_OWNER_MISMATCH', 'A sessão pertence a outra CloudOS Window.');
      return stopSessionInternal(session);
    }
    const normalizedOwner = ownerId ? normalizeOwnerId(ownerId) : null;
    const targets = [...sessions.values()].filter(session => !normalizedOwner || session.ownerId === normalizedOwner);
    const stopped = [];
    for (const session of targets) stopped.push(await stopSessionInternal(session));
    return stopped;
  });
}

export async function restartXpraPoc(id, ownerId = null) {
  const current = sessions.get(id);
  if (!current) throw createPocError('LINUX_POC_SESSION_NOT_FOUND', 'Sessão POC 1 não encontrada.');
  if (ownerId && current.ownerId !== normalizeOwnerId(ownerId)) throw createPocError('LINUX_POC_SESSION_OWNER_MISMATCH', 'A sessão pertence a outra CloudOS Window.');
  const restartCount = (current.metrics.restartCount || 0) + 1;
  const config = { app: current.app, distribution: current.distribution, ownerId: current.ownerId };
  await stopXpraPoc(id, current.ownerId);
  const next = await startXpraPoc(config);
  const internal = sessions.get(next.id);
  if (internal) internal.metrics.restartCount = restartCount;
  return publicSession(internal);
}

export function recordXpraPocClientMetrics(id, ownerId, values = {}) {
  const session = sessions.get(id);
  if (!session) throw createPocError('LINUX_POC_SESSION_NOT_FOUND', 'Sessão POC 1 não encontrada.');
  if (session.ownerId !== normalizeOwnerId(ownerId)) throw createPocError('LINUX_POC_SESSION_OWNER_MISMATCH', 'A sessão pertence a outra CloudOS Window.');
  for (const key of ['iframeLoadMs', 'firstRemoteWindowMs']) {
    const value = Number(values[key]);
    if (Number.isFinite(value) && value >= 0 && value <= 300_000) session.metrics[key] = Math.round(value);
  }
  const reconnectCount = Number(values.reconnectCount);
  if (Number.isSafeInteger(reconnectCount) && reconnectCount >= 0 && reconnectCount <= 10_000) {
    session.metrics.reconnectCount = Math.max(session.metrics.reconnectCount || 0, reconnectCount);
  }
  return publicSession(session);
}

export function resolveXpraPocProxySession(id, token) {
  const session = sessions.get(String(id || ''));
  if (!session || !crypto.timingSafeEqual(Buffer.from(session.proxyToken), Buffer.from(String(token || '').padEnd(session.proxyToken.length).slice(0, session.proxyToken.length)))) return null;
  if (String(token || '').length !== session.proxyToken.length) return null;
  if (!['starting', 'ready', 'degraded'].includes(session.state)) return null;
  return session;
}

export function recordXpraPocProxyEvent(id, event) {
  const session = sessions.get(id);
  if (!session) return;
  if (event === 'http') session.metrics.proxyHttpRequests += 1;
  if (event === 'websocket') session.metrics.proxyWebSocketConnections += 1;
}

export async function shutdownXpraPocRuntime() {
  try {
    await cleanupXpraPoc();
  } catch {
    // O shutdown global possui timeout próprio; não bloquear o host por falha do WSL.
  }
}
