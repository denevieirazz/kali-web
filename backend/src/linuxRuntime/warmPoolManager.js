import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import crypto from 'node:crypto';
import net from 'node:net';
import { WSL_EXE, safeChildEnvironment, getWslSnapshot } from '../wsl/distroService.js';
import { CURATED_LINUX_APPS } from './packageManager.js';

const PORT_BASE = 14820;
const DISPLAY_BASE = 160;

const activeAppSessions = new Map();
const reservedPorts = new Set();
const standbyPool = [];

let isRefillingPool = false;
let cachedDistro = 'kali-linux';
let lastDistroCheck = 0;

async function getFastDistribution() {
  if (Date.now() - lastDistroCheck < 300_000 && cachedDistro) {
    return cachedDistro;
  }
  try {
    const snap = await getWslSnapshot();
    cachedDistro = snap.preferred || snap.default || 'kali-linux';
    lastDistroCheck = Date.now();
    return cachedDistro;
  } catch {
    return 'kali-linux';
  }
}

async function isPortFree(port) {
  if (reservedPorts.has(port)) return false;
  return new Promise(resolve => {
    const server = net.createServer();
    server.unref();
    server.once('error', () => resolve(false));
    server.listen({ host: '127.0.0.1', port, exclusive: true }, () => {
      server.close(() => resolve(true));
    });
  });
}

let nextSlotIndex = 0;
async function allocateSlot(distro) {
  for (let tries = 0; tries < 40; tries++) {
    const offset = (nextSlotIndex++) % 40;
    const port = PORT_BASE + offset;
    const display = DISPLAY_BASE + offset;
    if (!reservedPorts.has(port) && await isPortFree(port)) {
      reservedPorts.add(port);
      return { port, display, distro };
    }
  }
  const fallback = PORT_BASE + 50 + (nextSlotIndex++ % 20);
  reservedPorts.add(fallback);
  return { port: fallback, display: fallback - PORT_BASE + DISPLAY_BASE, distro };
}

async function createSingleStandbySession() {
  const distro = await getFastDistribution();
  const slot = await allocateSlot(distro);
  const sessionId = `warm-${Date.now().toString(36)}-${crypto.randomBytes(3).toString('hex')}`;
  const proxyToken = crypto.randomBytes(24).toString('hex');
  const xpraPassword = crypto.randomBytes(24).toString('base64url');

  const startCmd = [
    'set -eu',
    `fuser -k -9 ${slot.port}/tcp 2>/dev/null || true`,
    `rm -rf /run/user/0/xpra/* /run/xpra/${slot.display} /tmp/.X11-unix/X${slot.display} /root/.xpra/*:${slot.display}* 2>/dev/null || true`,
    'mkdir -p -m 1777 /tmp/.X11-unix /run/xpra /tmp/cloudos-ff-poc 2>/dev/null || true',
    'mount -o remount,rw /tmp/.X11-unix 2>/dev/null || true',
    'chmod 1777 /tmp/.X11-unix /run/xpra 2>/dev/null || true',
    'rm -f /tmp/cloudos-*-poc/.parentlock /tmp/cloudos-*-poc/lock /tmp/cloudos-*-poc/SingletonLock /tmp/cloudos-ff-poc/.parentlock /tmp/cloudos-ff-poc/lock 2>/dev/null || true',
    'unset DISPLAY WAYLAND_DISPLAY PULSE_SERVER',
    `export XPRA_PASSWORD=${JSON.stringify(xpraPassword)}`,
    `exec xpra seamless :${slot.display} --socket-dirs=/run/xpra --session-name=${JSON.stringify(sessionId)} --exit-with-children=no --daemon=no --clipboard=no --printing=no --file-transfer=no --webcam=no --audio=no --speaker=no --microphone=no --notifications=no --mdns=no --dbus-launch=no --dbus-control=no --bind=noabstract --bind-tcp=0.0.0.0:${slot.port},auth=env --video=no --html=on`,
  ].join('; ');

  const child = spawn(WSL_EXE, ['-d', distro, '--exec', 'sh', '-c', startCmd], {
    windowsHide: true,
    env: safeChildEnvironment(),
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  child.once('exit', () => {
    reservedPorts.delete(slot.port);
    activeAppSessions.delete(sessionId);
    const idx = standbyPool.findIndex(s => s.id === sessionId);
    if (idx !== -1) standbyPool.splice(idx, 1);
  });

  // Fast-wait for TCP port to open
  const pollStart = Date.now();
  let isUp = false;
  while (Date.now() - pollStart < 6000) {
    if (child.exitCode !== null) break;
    const socket = net.createConnection({ host: '127.0.0.1', port: slot.port });
    isUp = await new Promise(res => {
      socket.once('connect', () => { socket.destroy(); res(true); });
      socket.once('error', () => { socket.destroy(); res(false); });
    });
    if (isUp) break;
    await new Promise(r => setTimeout(r, 40));
  }

  if (!isUp) {
    child.kill();
    reservedPorts.delete(slot.port);
    throw new Error('Falha ao inicializar slot Xpra pré-aquecido.');
  }

  const clientUrl = `/__cloudos/linux-runtime/poc1/${sessionId}/${proxyToken}/?username=root&password=${encodeURIComponent(xpraPassword)}&clipboard=no&keyboard=no&printing=no&file_transfer=no&floating_menu=no&reconnect=no&action=connect`;

  const session = {
    id: sessionId,
    proxyToken,
    xpraPassword,
    port: slot.port,
    display: slot.display,
    distribution: distro,
    clientUrl,
    state: 'standby',
    child,
    created: Date.now(),
  };

  activeAppSessions.set(sessionId, session);
  return session;
}

export async function refillStandbyPool() {
  if (isRefillingPool) return;
  isRefillingPool = true;
  try {
    while (standbyPool.length < 2) {
      const sess = await createSingleStandbySession();
      standbyPool.push(sess);
      console.log(`⚡ [WarmPool] Slot aquecido em standby: :${sess.display} (port ${sess.port}) [pool: ${standbyPool.length}]`);
    }
  } catch (err) {
    console.warn('⚠️ [WarmPool] Falha ao pré-aquecer pool:', err.message);
  } finally {
    isRefillingPool = false;
  }
}

export async function launchFastLinuxApp({ appId, ownerId }) {
  const started = Date.now();
  const distro = await getFastDistribution();
  const envFlags = 'MOZ_DISABLE_RDD_SANDBOX=1 MOZ_X11_EGL=0 LIBGL_ALWAYS_SOFTWARE=1 NO_AT_BRIDGE=1';
  const appCmd = appId === 'firefox' ? `${envFlags} firefox-esr --no-remote -profile /tmp/cloudos-ff-poc` :
                 appId === 'chromium' ? 'chromium --no-sandbox --disable-gpu' :
                 appId === 'code' ? 'code --no-sandbox' :
                 appId === 'xterm' ? "xterm -fa 'Monospace' -fs 11 -bg black -fg white" : appId;
  const appName = appId === 'firefox' ? 'Firefox ESR' :
                  appId === 'chromium' ? 'Chromium' :
                  appId === 'code' ? 'Visual Studio Code' :
                  appId === 'xterm' ? 'XTerm' : appId;

  let session = null;

  // 1. Check standby pool
  while (standbyPool.length > 0) {
    const candidate = standbyPool.shift();
    if (candidate.child?.exitCode === null) {
      session = candidate;
      break;
    }
  }

  // 2. If pool was empty, wait up to 1500ms if a refill is in progress
  if (!session && isRefillingPool) {
    const waitStart = Date.now();
    while (Date.now() - waitStart < 2000) {
      await new Promise(r => setTimeout(r, 40));
      if (standbyPool.length > 0) {
        session = standbyPool.shift();
        break;
      }
    }
  }

  // 3. If session found from warm pool: instant launch
  if (session) {
    session.ownerId = ownerId || 'desktop-user';
    session.appId = appId;
    session.title = appName;
    session.state = 'ready';

    // Trigger background pool refill
    setTimeout(() => { refillStandbyPool().catch(() => {}); }, 50);

    // Spawn app process on warm display persistently
    const appProcess = spawn(WSL_EXE, ['-d', distro, '--exec', 'sh', '-c', `rm -f /tmp/cloudos-ff-poc/.parentlock /tmp/cloudos-ff-poc/lock 2>/dev/null || true; exec env DISPLAY=:${session.display} ${appCmd}`], {
      windowsHide: true,
      env: safeChildEnvironment(),
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    session.appProcess = appProcess;

    session.metrics = {
      warmHit: true,
      launchDurationMs: Date.now() - started,
    };

    console.log(`🚀 [WarmPool] WARM HIT para ${appId}! Latência backend: ${session.metrics.launchDurationMs} ms`);
    return session;
  }

  // 4. Cold Fallback
  console.log(`⚡ [WarmPool] Cold fallback para ${appId}...`);
  session = await createSingleStandbySession();
  session.ownerId = ownerId || 'desktop-user';
  session.appId = appId;
  session.title = appName;
  session.state = 'ready';

  const appProcess = spawn(WSL_EXE, ['-d', distro, '--exec', 'sh', '-c', `rm -f /tmp/cloudos-ff-poc/.parentlock /tmp/cloudos-ff-poc/lock 2>/dev/null || true; exec env DISPLAY=:${session.display} ${appCmd}`], {
    windowsHide: true,
    env: safeChildEnvironment(),
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  session.appProcess = appProcess;

  session.metrics = {
    warmHit: false,
    launchDurationMs: Date.now() - started,
  };

  setTimeout(() => { refillStandbyPool().catch(() => {}); }, 100);
  return session;
}

export function resolveWarmSession(id, token) {
  const session = activeAppSessions.get(id);
  if (!session || session.proxyToken !== token) return null;
  return session;
}

// Pre-fill pool on startup
refillStandbyPool().catch(() => {});
