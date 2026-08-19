import { execFile, spawn } from 'node:child_process';
import net from 'node:net';
import { promisify } from 'node:util';
import { WSL_EXE, getWslSnapshot, normalizeName, validateInstalledAsync } from '../wsl/distroService.js';

const execFileAsync = promisify(execFile);
const PORT_START = 14500;
const PORT_END = 14549;
const ALLOWED_APPS = Object.freeze({
  xclock: { command: 'xclock', title: 'XClock' },
  xeyes: { command: 'xeyes', title: 'XEyes' },
  xterm: { command: 'xterm', title: 'XTerm' },
  gedit: { command: 'gedit', title: 'Gedit' },
});

let activeSession = null;

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'"'"'`)}'`;
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

export function buildXpraStartCommand({ appCommand, port }) {
  if (!Number.isInteger(port) || port < PORT_START || port > PORT_END) throw new Error('Porta Xpra fora da faixa da POC.');
  return [
    'set -eu',
    'unset DISPLAY WAYLAND_DISPLAY PULSE_SERVER',
    `exec xpra seamless --start-child=${shellQuote(appCommand)} --exit-with-children=yes --daemon=no --mdns=no --notifications=no --printing=no --file-transfer=no --bind=noabstract --bind-tcp=127.0.0.1:${port},auth=allow --html=on`,
  ].join('; ');
}

async function isPortFree(port) {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.unref();
    server.once('error', () => resolve(false));
    server.listen({ host: '127.0.0.1', port, exclusive: true }, () => server.close(() => resolve(true)));
  });
}

async function reservePort() {
  for (let port = PORT_START; port <= PORT_END; port += 1) {
    if (await isPortFree(port)) return port;
  }
  const error = new Error('Nenhuma porta localhost livre para a POC Xpra.');
  error.code = 'XPRA_PORT_UNAVAILABLE';
  throw error;
}

async function chooseDistribution(requested) {
  if (requested) {
    const distribution = normalizeName(requested);
    if (!await validateInstalledAsync(distribution)) {
      const error = new Error(`Distribuição WSL não instalada: ${distribution}`);
      error.code = 'WSL_DISTRO_NOT_INSTALLED';
      throw error;
    }
    return distribution;
  }
  const snapshot = await getWslSnapshot();
  if (!snapshot.operational || !snapshot.distributions.length) {
    const error = new Error(snapshot.error || 'Nenhuma distribuição WSL operacional encontrada.');
    error.code = snapshot.errorCode || 'WSL_UNAVAILABLE';
    throw error;
  }
  return snapshot.preferred || snapshot.default || snapshot.distributions[0].name;
}

async function probe(distribution, appCommand) {
  try {
    const { stdout, stderr } = await execFileAsync(WSL_EXE, ['-d', distribution, '--', 'sh', '-lc', buildXpraProbeCommand(appCommand)], {
      windowsHide: true,
      timeout: 15_000,
      maxBuffer: 256 * 1024,
    });
    return { version: String(stdout || stderr || '').trim().split(/\r?\n/).filter(Boolean).at(-1) || 'xpra' };
  } catch (error) {
    const text = `${error.stdout || ''}\n${error.stderr || ''}`;
    if (text.includes('XPRA_MISSING')) error.code = 'XPRA_MISSING';
    else if (text.includes('APP_MISSING:')) error.code = 'LINUX_POC_APP_MISSING';
    else error.code ||= 'XPRA_PROBE_FAILED';
    throw error;
  }
}

async function waitForHttp(port, child) {
  const deadline = Date.now() + 20_000;
  let lastError = null;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      const error = new Error(`Xpra terminou antes de ficar pronto (exit=${child.exitCode}).`);
      error.code = 'XPRA_EXITED_EARLY';
      throw error;
    }
    try {
      const response = await fetch(`http://127.0.0.1:${port}/`, { signal: AbortSignal.timeout(1000) });
      if (response.ok) return;
      lastError = new Error(`HTTP ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  const error = new Error(`Xpra não publicou o cliente HTML5 em localhost:${port}: ${lastError?.message || 'timeout'}`);
  error.code = 'XPRA_READINESS_TIMEOUT';
  throw error;
}

function publicSession(session) {
  if (!session) return null;
  return {
    id: session.id,
    app: session.app,
    title: session.title,
    distribution: session.distribution,
    port: session.port,
    state: session.state,
    startedAt: session.startedAt,
    clientUrl: session.state === 'ready' ? `http://127.0.0.1:${session.port}/?clipboard=yes&keyboard=yes&floating_menu=no&reconnect=yes` : null,
    xpraVersion: session.xpraVersion,
    error: session.error || null,
    errorCode: session.errorCode || null,
  };
}

export function getXpraPocSession() {
  return publicSession(activeSession);
}

export async function startXpraPoc({ app, distribution } = {}) {
  const appId = normalizePocApp(app || 'xclock');
  if (!appId) {
    const error = new Error('Aplicativo não permitido na POC 1.');
    error.code = 'LINUX_POC_APP_NOT_ALLOWED';
    throw error;
  }
  if (activeSession?.state === 'ready' || activeSession?.state === 'starting') {
    if (activeSession.app === appId) return publicSession(activeSession);
    const error = new Error('Já existe uma sessão Linux Runtime POC ativa.');
    error.code = 'LINUX_POC_SESSION_ACTIVE';
    throw error;
  }

  const selected = await chooseDistribution(distribution);
  const definition = ALLOWED_APPS[appId];
  const preflight = await probe(selected, definition.command);
  const port = await reservePort();
  const id = `xpra-${Date.now().toString(36)}`;
  const session = activeSession = {
    id,
    app: appId,
    title: definition.title,
    distribution: selected,
    port,
    state: 'starting',
    startedAt: new Date().toISOString(),
    xpraVersion: preflight.version,
    child: null,
    error: null,
    errorCode: null,
  };

  const command = buildXpraStartCommand({ appCommand: definition.command, port });
  const child = spawn(WSL_EXE, ['-d', selected, '--', 'sh', '-lc', command], {
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  session.child = child;
  const diagnostics = [];
  const capture = chunk => {
    diagnostics.push(String(chunk));
    if (diagnostics.join('').length > 64 * 1024) diagnostics.shift();
  };
  child.stdout.on('data', capture);
  child.stderr.on('data', capture);
  child.once('exit', (code) => {
    if (activeSession?.id !== id) return;
    if (session.state !== 'stopping' && session.state !== 'stopped') {
      session.state = 'failed';
      session.errorCode = 'XPRA_PROCESS_EXITED';
      session.error = `Xpra encerrou (exit=${code}). ${diagnostics.join('').slice(-3000)}`.trim();
    }
  });

  try {
    await waitForHttp(port, child);
    session.state = 'ready';
    return publicSession(session);
  } catch (error) {
    session.state = 'failed';
    session.errorCode = error.code || 'XPRA_START_FAILED';
    session.error = `${error.message}\n${diagnostics.join('').slice(-3000)}`.trim();
    try { child.kill(); } catch {}
    throw error;
  }
}

export async function stopXpraPoc() {
  if (!activeSession) return null;
  const session = activeSession;
  session.state = 'stopping';
  try {
    if (session.child && session.child.exitCode === null) session.child.kill();
    await execFileAsync(WSL_EXE, ['-d', session.distribution, '--', 'sh', '-lc', `xpra stop :${session.port} >/dev/null 2>&1 || true`], {
      windowsHide: true,
      timeout: 5000,
    }).catch(() => undefined);
  } finally {
    session.state = 'stopped';
    activeSession = null;
  }
  return publicSession(session);
}
