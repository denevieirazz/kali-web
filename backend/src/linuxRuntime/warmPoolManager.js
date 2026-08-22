import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import crypto from 'node:crypto';
import net from 'node:net';
import { WSL_EXE, safeChildEnvironment, getWslSnapshot } from '../wsl/distroService.js';
import { CURATED_LINUX_APPS } from './packageManager.js';

const execFileAsync = promisify(execFile);
const PORT_BASE = 14520;
const DISPLAY_BASE = 120;

const activeAppSessions = new Map();
const reservedPorts = new Set();

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

async function allocateSlot(distro) {
  for (let offset = 0; offset < 20; offset++) {
    const port = PORT_BASE + offset;
    const display = DISPLAY_BASE + offset;
    if (await isPortFree(port)) {
      reservedPorts.add(port);
      return { port, display, distro };
    }
  }
  return { port: 14540, display: 140, distro };
}

export async function launchFastLinuxApp({ appId, ownerId }) {
  const started = Date.now();
  const distro = await getFastDistribution();
  const appDef = CURATED_LINUX_APPS.find(a => a.id === appId) || {
    id: appId,
    name: appId,
    command: appId,
  };

  const slot = await allocateSlot(distro);
  const sessionId = `fast-${Date.now().toString(36)}-${crypto.randomBytes(3).toString('hex')}`;
  const proxyToken = crypto.randomBytes(24).toString('hex');
  const xpraPassword = crypto.randomBytes(24).toString('base64url');

  const startCmd = [
    'set -eu',
    'mkdir -p -m 1777 /tmp/.X11-unix 2>/dev/null || true',
    'mount -o remount,rw /tmp/.X11-unix 2>/dev/null || true',
    'chmod 1777 /tmp/.X11-unix 2>/dev/null || true',
    'unset DISPLAY WAYLAND_DISPLAY PULSE_SERVER',
    `export XPRA_PASSWORD=${JSON.stringify(xpraPassword)}`,
    `exec xpra seamless :${slot.display} --session-name=${JSON.stringify(sessionId)} --start-child=${JSON.stringify(appDef.command)} --exit-with-children=yes --daemon=no --clipboard=no --printing=no --file-transfer=no --webcam=no --audio=no --notifications=no --mdns=no --dbus-launch=no --dbus-control=no --bind=noabstract --bind-tcp=0.0.0.0:${slot.port},auth=env --video=no --html=on`,
  ].join('; ');

  const child = spawn(WSL_EXE, ['-d', distro, '--exec', 'sh', '-c', startCmd], {
    windowsHide: true,
    env: safeChildEnvironment(),
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  child.once('exit', () => {
    reservedPorts.delete(slot.port);
    activeAppSessions.delete(sessionId);
  });

  // Fast-wait for TCP port to open
  const pollStart = Date.now();
  while (Date.now() - pollStart < 8000) {
    if (child.exitCode !== null) break;
    const socket = net.createConnection({ host: '127.0.0.1', port: slot.port });
    const isUp = await new Promise(res => {
      socket.once('connect', () => { socket.destroy(); res(true); });
      socket.once('error', () => { socket.destroy(); res(false); });
    });
    if (isUp) break;
    await new Promise(r => setTimeout(r, 120));
  }

  const clientUrl = `/__cloudos/linux-runtime/poc1/${sessionId}/${proxyToken}/?username=root&password=${encodeURIComponent(xpraPassword)}&clipboard=no&keyboard=no&printing=no&file_transfer=no&floating_menu=no&reconnect=no&action=connect`;

  const session = {
    id: sessionId,
    ownerId: ownerId || 'desktop-user',
    proxyToken,
    xpraPassword,
    port: slot.port,
    display: slot.display,
    distribution: distro,
    appId,
    title: appDef.name,
    clientUrl,
    state: 'ready',
    child,
    metrics: {
      launchDurationMs: Date.now() - started,
    }
  };

  activeAppSessions.set(sessionId, session);
  return session;
}

export function resolveWarmSession(id, token) {
  const session = activeAppSessions.get(id);
  if (!session || session.proxyToken !== token) return null;
  return session;
}
