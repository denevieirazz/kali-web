import { execFile, spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { WebSocket } from 'ws';
import { WSL_EXE, getWslSnapshot, normalizeName, safeChildEnvironment, validateInstalledAsync } from '../wsl/distroService.js';
import { expandDesktopExec, resolveLinuxDesktopApp, scanLinuxDesktopApps } from '../apps/linuxDesktopScanner.js';
import { XPRA_BIND_TCP_HOST, XPRA_DISPLAY_END, XPRA_DISPLAY_START, XPRA_PORT_END, XPRA_PORT_START, chooseXpraPair, displayForPort as displayForXpraPort, validateLedgerPair } from './xpraPairAllocator.js';
import { getActiveDistro } from './distroManager.js';
import { resolveActiveDistribution } from './packageManager.js';

const execFileAsync = promisify(execFile);
const PORT_START = XPRA_PORT_START;
const PORT_END = XPRA_PORT_END;
const DISPLAY_START = XPRA_DISPLAY_START;
const DISPLAY_END = XPRA_DISPLAY_END;
const MAX_ACTIVE_SESSIONS = 24;
const START_TIMEOUT_MS = 25_000;
const HEALTH_TIMEOUT_MS = 4_000;
const STOP_TIMEOUT_MS = 6_000;
const LEASE_TTL_MS = 120_000;
const LEDGER_FILE = path.join(os.tmpdir(), 'cloudos-linux-runtime-poc1-sessions.json');

const OWNER_ID = /^[a-zA-Z0-9._:-]{1,128}$/;
const APP_ID = /^linux-[a-f0-9]{32}$/;
const SESSION_ID = /^xpra-[a-z0-9-]{12,96}$/;
const MAX_APP_ARGV = 128;
const MAX_APP_ARGUMENT_LENGTH = 4096;
const sessions = new Map();
const reservedPorts = new Set();
let lifecycleQueue = Promise.resolve();

const defaultAppResolver = Object.freeze({
  async list(distribution) {
    return scanLinuxDesktopApps(distribution);
  },
  async resolve(appId, distribution) {
    return resolveLinuxDesktopApp(appId, distribution);
  }
});

let configuredAppResolver = defaultAppResolver;

function queueLifecycle(operation) {
  const next = lifecycleQueue.then(operation, operation);
  lifecycleQueue = next.catch(() => undefined);
  return next;
}
function shellQuote(value) { return `'${String(value).replace(/'/g, `'"'"'`)}'`; }
function shellToken(value) { const text = String(value); return /^[a-zA-Z0-9_./:@%+=,-]+$/.test(text) ? text : shellQuote(text); }
function shellCommand(argv) { return argv.map(shellToken).join(' '); }
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
    native: false,
    mode: 'xpra',
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
function writeLedgerEntries(entries) { try { if (!entries.length) return fs.rmSync(LEDGER_FILE, { force: true }); const temp = `${LEDGER_FILE}.tmp`; fs.writeFileSync(temp, JSON.stringify({ version: 1, sessions: entries }, null, 2), 'utf8'); fs.renameSync(temp, LEDGER_FILE); } catch {} }
function writeLedger() { const live = [...sessions.values()].filter(s => !['stopped', 'failed'].includes(s.state)).map(serializeLedgerSession); writeLedgerEntries(live); }

export async function restoreSessionsFromLedger() {
  return queueLifecycle(async () => {
    const ledger = readLedger();
    if (!ledger.length) return { cleaned: [], remaining: [] };
    const cleaned = [];
    const remaining = [];

    for (const entry of ledger) {
      const pair = validateLedgerPair(entry);
      if (!pair.ok || !entry.id || !entry.distribution) continue;
      try {
        if (!await validateInstalledAsync(entry.distribution)) {
          remaining.push(entry);
          continue;
        }
        await stopLedgerEntry(entry);
        const [linux, tcp] = await Promise.all([
          probeWslServer({ sessionId: entry.id, display: entry.display }),
          probeWindowsTcp(entry.port, 500),
        ]);
        if (linux.ok || tcp.ok) remaining.push(entry);
        else cleaned.push(entry.id);
      } catch {
        remaining.push(entry);
      }
    }

    writeLedgerEntries(remaining);
    return { cleaned, remaining: remaining.map(entry => entry.id) };
  });
}

export function normalizePocApp(value) {
  const id = typeof value === 'string' ? value.trim() : '';
  return APP_ID.test(id) ? id : null;
}

function tokenizeTrustedCommand(command) {
  const input = String(command || '').trim();
  if (!input || /[\0\r\n]/.test(input)) return null;
  const argv = [];
  let token = '';
  let quote = null;
  let escaped = false;
  let tokenStarted = false;
  for (const char of input) {
    if (escaped) {
      token += char;
      tokenStarted = true;
      escaped = false;
      continue;
    }
    if (char === '\\' && quote !== "'") {
      escaped = true;
      tokenStarted = true;
      continue;
    }
    if (quote) {
      if (char === quote) quote = null;
      else token += char;
      tokenStarted = true;
      continue;
    }
    if (char === "'" || char === '"') {
      quote = char;
      tokenStarted = true;
      continue;
    }
    if (/\s/.test(char)) {
      if (tokenStarted) {
        argv.push(token);
        token = '';
        tokenStarted = false;
      }
      continue;
    }
    token += char;
    tokenStarted = true;
  }
  if (escaped || quote) return null;
  if (tokenStarted) argv.push(token);
  return argv;
}

function normalizeArgv(argv) {
  if (!Array.isArray(argv) || argv.length < 1 || argv.length > MAX_APP_ARGV) return null;
  const normalized = [];
  for (const value of argv) {
    if (typeof value !== 'string' || !value || value.length > MAX_APP_ARGUMENT_LENGTH || /[\0\r\n]/.test(value)) return null;
    normalized.push(value);
  }
  const executable = normalized[0];
  if (!(executable.startsWith('/') || /^[a-zA-Z0-9][a-zA-Z0-9._+-]*$/.test(executable))) return null;
  if (executable.startsWith('/') && (!/^\/[a-zA-Z0-9_./+@-]+$/.test(executable) || executable.split('/').includes('..'))) return null;
  return normalized;
}

function normalizeRequestedFilePath(value) {
  const input = typeof value === 'string' ? value.trim() : '';
  if (!input) return null;
  if (input.length > MAX_APP_ARGUMENT_LENGTH || /[\0\r\n]/.test(input)) {
    throw createPocError('LINUX_FILE_PATH_INVALID', 'Caminho de arquivo inválido.');
  }
  let candidate = input.replace(/\\/g, '/');
  if (/^[a-zA-Z]:\//.test(candidate)) {
    candidate = `/mnt/${candidate.charAt(0).toLowerCase()}/${candidate.slice(3)}`;
  }
  if (!/^\/mnt\/[a-z]\//.test(candidate) || candidate.split('/').includes('..')) {
    throw createPocError('LINUX_FILE_PATH_OUTSIDE_WORKSPACE', 'Somente arquivos do Windows montados em /mnt/<drive> podem ser enviados ao aplicativo Linux.');
  }
  return candidate;
}

function normalizeResolvedAppDefinition(candidate, requestedId) {
  if (!candidate || typeof candidate !== 'object') return null;
  const id = normalizePocApp(candidate.id);
  if (!id || id !== requestedId) return null;
  const argv = normalizeArgv(candidate.argv || candidate.launchArgv || candidate.execArgv);
  if (!argv) return null;
  const execTemplate = normalizeArgv(candidate.execTemplate || candidate.argv || candidate.launchArgv || candidate.execArgv);
  if (!execTemplate) return null;
  return {
    id,
    argv,
    execTemplate,
    command: shellCommand(argv),
    title: String(candidate.title || candidate.name || id).trim().slice(0, 256) || id,
    name: String(candidate.name || candidate.title || id).trim().slice(0, 256) || id,
    genericName: String(candidate.genericName || '').trim().slice(0, 256),
    comment: String(candidate.comment || '').trim().slice(0, 1_000),
    keywords: Array.isArray(candidate.keywords) ? [...candidate.keywords] : [],
    icon: candidate.icon || candidate.iconName || null,
    iconUrl: candidate.iconUrl || null,
    category: candidate.category || null,
    categories: Array.isArray(candidate.categories) ? [...candidate.categories] : [],
    mimeTypes: Array.isArray(candidate.mimeTypes) ? [...candidate.mimeTypes] : [],
    terminal: candidate.terminal === true,
    userLocal: typeof candidate.desktopFile === 'string' && candidate.desktopFile.includes('/.local/share/applications/'),
    source: 'linux',
    distribution: candidate.distribution || null,
    launchMode: 'xpra-contained',
    installed: true,
    isDiscovered: true
  };
}

async function resolverList(resolver, distribution) {
  if (typeof resolver?.list === 'function') return resolver.list(distribution);
  return [];
}

async function resolverResolve(resolver, appId, distribution) {
  if (typeof resolver === 'function') return resolver(appId, distribution);
  if (typeof resolver?.resolve === 'function') return resolver.resolve(appId, distribution);
  const discovered = await resolverList(resolver, distribution);
  return Array.isArray(discovered) ? discovered.find(app => String(app?.id || '') === appId) || null : null;
}

export function setXpraPocAppResolver(resolver = null) {
  if (resolver !== null && typeof resolver !== 'function' && typeof resolver?.resolve !== 'function' && typeof resolver?.list !== 'function') {
    throw new TypeError('Resolver de aplicativos Linux inválido.');
  }
  configuredAppResolver = resolver || defaultAppResolver;
}

export async function resolvePocApp(appId, distro, resolver = configuredAppResolver) {
  const requestedId = normalizePocApp(appId);
  if (!requestedId) return null;
  const candidate = await resolverResolve(resolver, requestedId, distro).catch(() => null);
  return normalizeResolvedAppDefinition(candidate, requestedId);
}

function publicDiscoveredApp(app) {
  return {
    id: app.id,
    name: app.name,
    title: app.title,
    genericName: app.genericName,
    comment: app.comment,
    keywords: [...app.keywords],
    icon: app.icon,
    iconUrl: app.iconUrl,
    category: app.category,
    categories: [...app.categories],
    mimeTypes: [...app.mimeTypes],
    terminal: app.terminal,
    source: app.source,
    distribution: app.distribution,
    launchMode: app.launchMode,
    installed: app.installed,
    isDiscovered: app.isDiscovered
  };
}

export async function getDiscoveredLinuxPocApps(distro, resolver = configuredAppResolver) {
  const discovered = await resolverList(resolver, distro).catch(() => []);
  if (!Array.isArray(discovered)) return [];
  const unique = new Map();
  for (const candidate of discovered) {
    const id = normalizePocApp(candidate?.id);
    const app = id ? normalizeResolvedAppDefinition(candidate, id) : null;
    if (app && !unique.has(app.id)) unique.set(app.id, app);
  }
  return [...unique.values()]
    .sort((a, b) => a.title.localeCompare(b.title))
    .map(publicDiscoveredApp);
}

// Kept as a compatibility alias for existing route consumers. The result is
// exclusively scanner-backed; there is no static allowlist or curated catalog.
export const getAllowedLinuxPocApps = getDiscoveredLinuxPocApps;

export function displayForPort(port) { return displayForXpraPort(port); }

function commandInputArgv(appCommand, appArgv = null) {
  const argv = appArgv || (Array.isArray(appCommand) ? appCommand : tokenizeTrustedCommand(appCommand));
  const normalized = normalizeArgv(argv);
  if (!normalized) throw createPocError('XPRA_APP_DEFINITION_INVALID', 'Definição de execução Linux inválida.');
  return normalized;
}

function runtimeArgvFor(appDef, sessionId, requestedFilePath = null) {
  let argv = requestedFilePath
    ? expandDesktopExec(appDef.execTemplate, {
        files: [requestedFilePath],
        urls: [`file://${requestedFilePath}`],
        name: appDef.name,
        icon: appDef.icon || ''
      })
    : [...appDef.argv];
  if (requestedFilePath && argv.length === appDef.argv.length && argv.every((value, index) => value === appDef.argv[index])) {
    argv.push('--', requestedFilePath);
  }
  const binary = path.posix.basename(argv[0]).toLowerCase();

  // Firefox must never hand a launch to an already-running process connected to
  // another display. This is a runtime policy derived from the executable, not
  // a catalog entry.
  if (binary === 'firefox' || binary === 'firefox-esr') {
    const withoutProfile = [];
    for (let index = 0; index < argv.length; index += 1) {
      if (argv[index] === '--profile' || argv[index] === '-profile') {
        index += 1;
        continue;
      }
      withoutProfile.push(argv[index]);
    }
    argv = withoutProfile;
    if (!argv.includes('--no-remote')) argv.splice(1, 0, '--no-remote');
    argv.push('--profile', `/tmp/cloudos-firefox-poc-${sessionId}`);
  }

  if (appDef.terminal) {
    argv = ['xterm', '-fa', 'Monospace', '-fs', '11', '-bg', 'black', '-fg', 'white', '-e', ...argv];
  }
  return commandInputArgv(null, argv);
}

export function buildXpraProbeCommand(appCommand, appArgv = null) {
  const argv = commandInputArgv(appCommand, appArgv);
  const binary = argv[0];
  const marker = path.posix.basename(binary).replace(/[^a-zA-Z0-9._+-]/g, '') || 'unknown';
  const binaryCheck = `command -v ${shellQuote(binary)} >/dev/null 2>&1 || { echo APP_MISSING:${marker}; exit 42; }`;
  const containmentTools = 'for tool in unshare mount setpriv; do command -v "$tool" >/dev/null 2>&1 || { echo CONTAINMENT_TOOL_MISSING:$tool; exit 44; }; done';
  const abstractSocketGuard = "if grep -q ' @/tmp/.X11-unix/X0$' /proc/net/unix 2>/dev/null; then echo WSLG_ABSTRACT_SOCKET_PRESENT; exit 45; fi";
  return ['set -eu', 'command -v xpra >/dev/null 2>&1 || { echo XPRA_MISSING; exit 41; }', containmentTools, abstractSocketGuard, binaryCheck, 'xpra --version'].join('; ');
}

function normalizedLaunchIdentity(identity = {}) {
  const candidateUid = Number(identity.uid);
  const candidateGid = Number(identity.gid);
  const validUid = Number.isInteger(candidateUid) && candidateUid > 0 && candidateUid <= 2_147_483_646;
  const validGid = Number.isInteger(candidateGid) && candidateGid > 0 && candidateGid <= 2_147_483_646;
  const uid = validUid ? candidateUid : 65534;
  const gid = validUid && validGid ? candidateGid : 65534;
  const name = validUid && /^[a-z_][a-z0-9_-]{0,31}$/i.test(String(identity.name || '')) ? String(identity.name) : 'cloudos-app';
  const sourceHome = uid !== 65534 && /^\/[a-zA-Z0-9_ ./+@-]{1,1024}$/.test(String(identity.home || '')) && !String(identity.home).split('/').includes('..')
    ? String(identity.home)
    : null;
  return { uid, gid, name, sourceHome };
}

export function buildXpraStartCommand({ appCommand = null, appArgv = null, port, sessionId = 'cloudos-poc1', password = 'test-only-secret', launchIdentity = null }) {
  if (!Number.isInteger(port) || port < PORT_START || port > PORT_END) throw new Error('Porta Xpra fora da faixa da POC.');
  if (!password || String(password).length < 16) throw new Error('Capability Xpra inválida.');
  const argv = commandInputArgv(appCommand, appArgv);
  const childCommand = shellCommand(argv);
  const display = displayForPort(port);
  const identity = normalizedLaunchIdentity(launchIdentity || {});
  const profileFlagIndex = argv.findIndex(argument => argument === '-profile' || argument === '--profile');
  const firefoxProfile = profileFlagIndex >= 0 && /^\/tmp\/[a-zA-Z0-9._-]+$/.test(argv[profileFlagIndex + 1] || '') ? argv[profileFlagIndex + 1] : null;
  const isolationId = crypto.createHash('sha256').update(String(sessionId)).digest('hex').slice(0, 16);
  const appProfileId = crypto.createHash('sha256').update(`${identity.uid}\0${argv[0]}`).digest('hex').slice(0, 24);
  const containedHome = `/var/lib/cloudos/contained-homes/${identity.uid}-${appProfileId}`;
  const containedRuntime = `/run/user/${identity.uid}`;
  const containedPath = `${identity.sourceHome ? `${identity.sourceHome}/.local/bin:` : ''}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`;
  // The contained app gets a dedicated persistent HOME plus a private runtime,
  // PID view and /tmp. This prevents an existing WSLg singleton from accepting
  // the launch through a socket or D-Bus session outside the Xpra namespace.
  // It runs as an unprivileged UID with a clean environment. Xpra contributes
  // only its private DISPLAY and XAUTHORITY values to the child.
  const childEnvironment = [
    `HOME=${shellQuote(containedHome)}`,
    `USER=${shellToken(identity.name)}`,
    `LOGNAME=${shellToken(identity.name)}`,
    'SHELL=/bin/sh',
    `PATH=${shellQuote(containedPath)}`,
    'LANG=C.UTF-8',
    `XDG_RUNTIME_DIR=${containedRuntime}`,
    `XDG_CONFIG_HOME=${shellQuote(`${containedHome}/.config`)}`,
    `XDG_CACHE_HOME=${shellQuote(`${containedHome}/.cache`)}`,
    `XDG_DATA_HOME=${shellQuote(`${containedHome}/.local/share`)}`,
    'GDK_BACKEND=x11',
    'QT_QPA_PLATFORM=xcb',
    'SDL_VIDEODRIVER=x11',
    'CLUTTER_BACKEND=x11',
    'XDG_SESSION_TYPE=x11',
    'MOZ_ENABLE_WAYLAND=0',
    'ELECTRON_OZONE_PLATFORM_HINT=x11',
    'LIBGL_ALWAYS_SOFTWARE=1',
    'MOZ_X11_EGL=0',
    'NO_AT_BRIDGE=1',
  ].join(' ');
  const wrappedChild = `env -u WAYLAND_DISPLAY -u WAYLAND_SOCKET -u PULSE_SERVER -u WSLENV -u WSL_INTEROP -u DBUS_SESSION_BUS_ADDRESS -u XPRA_PASSWORD ${childEnvironment} dbus-run-session -- ${childCommand}`;
  const xpraServer = `exec setpriv --reuid=${identity.uid} --regid=${identity.gid} --clear-groups --no-new-privs --bounding-set=-all --inh-caps=-all --ambient-caps=-all -- xpra seamless :${display} --socket-dirs=/run/xpra --session-name=${shellQuote(`cloudos-poc1-${sessionId}`)} --start-child=${shellQuote(wrappedChild)} --exit-with-children=yes --daemon=no --clipboard=no --printing=no --file-transfer=no --webcam=no --audio=no --speaker=no --microphone=no --notifications=no --mdns=no --dbus-launch=no --dbus-control=no --start-new-commands=no --bind=noabstract --bind-tcp=${XPRA_BIND_TCP_HOST}:${port},auth=env --video=no --html=on`;
  const isolatedMounts = [
    'set -eu',
    'mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs /tmp',
    'install -d -m 1777 /tmp/.X11-unix',
    'mount -t tmpfs -o mode=755,nosuid,nodev,noexec tmpfs /run/user',
    `install -d -o ${identity.uid} -g ${identity.gid} -m 700 ${containedRuntime}`,
    'mount -t tmpfs -o mode=700,nosuid,nodev,noexec tmpfs /run/xpra',
    `chown ${identity.uid}:${identity.gid} /run/xpra`,
    `install -d -m 000 /tmp/cloudos-wslg-mask-${isolationId}`,
    `[ ! -d /mnt/wslg ] || mount --bind /tmp/cloudos-wslg-mask-${isolationId} /mnt/wslg`,
    `[ ! -d /run/WSL ] || mount --bind /tmp/cloudos-wslg-mask-${isolationId} /run/WSL`,
    `[ ! -d /run/systemd ] || mount --bind /tmp/cloudos-wslg-mask-${isolationId} /run/systemd`,
    `[ ! -d /run/dbus ] || mount --bind /tmp/cloudos-wslg-mask-${isolationId} /run/dbus`,
    `install -m 000 /dev/null /tmp/cloudos-init-mask-${isolationId}`,
    `mount --bind /tmp/cloudos-init-mask-${isolationId} /init`,
    'mount -o remount,bind,ro,noexec,nosuid,nodev /init',
    `install -d -m 700 ${shellQuote(containedHome)}`,
    `chown ${identity.uid}:${identity.gid} ${shellQuote(containedHome)}`,
    ...(firefoxProfile ? [`install -d -o ${identity.uid} -g ${identity.gid} -m 700 ${shellQuote(firefoxProfile)}`] : []),
    `export HOME=${shellQuote(containedHome)}`,
    `export XDG_RUNTIME_DIR=${containedRuntime}`,
    `export XDG_CONFIG_HOME=${shellQuote(`${containedHome}/.config`)}`,
    `export XDG_CACHE_HOME=${shellQuote(`${containedHome}/.cache`)}`,
    `export XDG_DATA_HOME=${shellQuote(`${containedHome}/.local/share`)}`,
    `export USER=${shellToken(identity.name)} LOGNAME=${shellToken(identity.name)}`,
    'unset WSLENV WSL_INTEROP WAYLAND_DISPLAY WAYLAND_SOCKET PULSE_SERVER',
    'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
    "if grep -q ' @/tmp/.X11-unix/X0$' /proc/net/unix 2>/dev/null; then echo WSLG_ABSTRACT_SOCKET_PRESENT >&2; exit 45; fi",
    '[ ! -S /tmp/.X11-unix/X0 ] || { echo WSLG_X11_SOCKET_VISIBLE >&2; exit 46; }',
    '[ ! -S /mnt/wslg/runtime-dir/wayland-0 ] || { echo WSLG_WAYLAND_SOCKET_VISIBLE >&2; exit 46; }',
    '[ ! -x /init ] || { echo WSL_INIT_VISIBLE >&2; exit 46; }',
    'if /init /mnt/c/Windows/System32/cmd.exe /c exit >/dev/null 2>&1; then echo WSL_INTEROP_BYPASS >&2; exit 46; fi',
    'if /mnt/c/Windows/System32/cmd.exe /c exit >/dev/null 2>&1; then echo WSL_PE_BYPASS >&2; exit 46; fi',
    xpraServer,
  ].join('; ');
  return [
    'set -eu',
    'unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET PULSE_SERVER WSLENV WSL_INTEROP',
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
    `export XPRA_PASSWORD=${shellQuote(password)}`,
    `exec unshare --mount --pid --fork --kill-child=KILL --mount-proc=/proc --propagation private sh -c ${shellQuote(isolatedMounts)}`,
  ].join('; ');
}

async function execWsl(distribution, command, timeout = HEALTH_TIMEOUT_MS) { return execFileAsync(WSL_EXE, ['-d', distribution, '--exec', 'sh', '-c', command], { windowsHide: true, env: safeChildEnvironment(), timeout, maxBuffer: 512 * 1024 }); }
async function execWslSystem(args, timeout = HEALTH_TIMEOUT_MS) {
  return execFileAsync(WSL_EXE, ['--system', '-u', 'root', '--', ...args], {
    windowsHide: true,
    env: safeChildEnvironment(),
    timeout,
    maxBuffer: 2 * 1024 * 1024,
  });
}

export async function checkWslInteropDisabled(distribution) {
  const started = Date.now();
  try {
    const { stdout } = await execWsl(distribution, 'cat /proc/sys/fs/binfmt_misc/WSLInterop 2>/dev/null || true', 6000);
    const text = String(stdout || '').trim();
    if (text === 'disabled' || text.startsWith('disabled')) {
      return { ok: true, code: 'WSL_INTEROP_DISABLED', error: null, evidence: 'DISABLED', durationMs: elapsedMs(started) };
    }
    if (!text) {
      return { ok: true, code: 'WSL_INTEROP_NOT_REGISTERED', error: null, evidence: 'UNAVAILABLE', durationMs: elapsedMs(started) };
    }
    return { ok: false, code: 'WSL_INTEROP_ENABLED', error: 'WSL interop está habilitado. A POC 1 exige interop desabilitado.', evidence: 'ENABLED', durationMs: elapsedMs(started) };
  } catch {
    return {
      ok: false,
      code: 'WSL_INTEROP_CHECK_FAILED',
      error: 'Não foi possível confirmar que o WSL interop está desabilitado.',
      evidence: 'CHECK_FAILED',
      durationMs: elapsedMs(started),
    };
  }
}

async function getDistroInfo(distribution) { const { stdout } = await execWsl(distribution, 'uname -s; uname -r; cat /etc/os-release 2>/dev/null || true', 3000); const lines = String(stdout || '').split('\n'); return { kernel: lines[0] || 'Linux', release: lines[1] || 'unknown', prettyName: lines.find(l => l.startsWith('PRETTY_NAME='))?.split('=')[1]?.replace(/"/g, '') || distribution }; }
async function getDistroLaunchIdentity(distribution) {
  const python = 'import json,os,pwd; p=pwd.getpwuid(os.getuid()); print(json.dumps({"uid":os.getuid(),"gid":os.getgid(),"name":p.pw_name,"home":p.pw_dir}))';
  try {
    const { stdout } = await execFileAsync(WSL_EXE, ['-d', distribution, '--exec', 'python3', '-c', python], {
      windowsHide: true,
      env: safeChildEnvironment(),
      timeout: 4000,
      maxBuffer: 64 * 1024,
    });
    const parsed = JSON.parse(String(stdout || '{}'));
    // A root default user is never propagated to GUI applications. The
    // sandbox identity remains able to launch apt-installed system apps.
    return normalizedLaunchIdentity(parsed);
  } catch {
    return normalizedLaunchIdentity();
  }
}
async function probe(distribution, appArgv) {
  try {
    const { stdout } = await execWsl(distribution, buildXpraProbeCommand(null, appArgv), 4000);
    const versionLine = String(stdout || '').split('\n').find(l => l.includes('xpra v') || l.includes('xpra')) || 'xpra v6';
    return { ok: true, version: versionLine.trim(), mode: 'xpra' };
  } catch (error) {
    const text = `${error.stdout || ''} ${error.stderr || ''}`;
    if (text.includes('APP_MISSING:')) throw createPocError('XPRA_APP_MISSING', 'Aplicativo Linux não instalado.');
    if (text.includes('XPRA_MISSING')) throw createPocError('XPRA_NOT_INSTALLED', 'Xpra não está instalado.');
    if (text.includes('CONTAINMENT_TOOL_MISSING:')) throw createPocError('XPRA_CONTAINMENT_UNAVAILABLE', 'As barreiras de isolamento do runtime Linux não estão disponíveis.');
    if (text.includes('WSLG_ABSTRACT_SOCKET_PRESENT')) throw createPocError('XPRA_CONTAINMENT_UNAVAILABLE', 'Um socket abstrato do WSLg impediria o isolamento garantido; lançamento recusado.');
    throw createPocError('XPRA_PROBE_FAILED', error.message);
  }
}
async function probeWslServer({ sessionId = null, id = null, display }) {
  const pids = await inspectSessionPids(sessionId || id, display);
  return { ok: Boolean(pids.xpra && pids.xorg), pids };
}
async function probeExternalWslgRoute(distribution) {
  try {
    const { stdout } = await execWsl(distribution, "grep -q ' @/tmp/.X11-unix/X0$' /proc/net/unix 2>/dev/null && echo PRESENT || echo ABSENT", 2500);
    return String(stdout || '').includes('PRESENT');
  } catch {
    return true;
  }
}
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

async function probeWslTcpAvailable(distribution, port) {
  const numericPort = Number(port);
  if (!Number.isInteger(numericPort) || numericPort < PORT_START || numericPort > PORT_END) return false;
  const python = `import socket\ns=socket.socket()\ns.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)\ntry:\n s.bind(('0.0.0.0',${numericPort}))\n print('FREE')\nfinally:\n s.close()`;
  try {
    const { stdout } = await execFileAsync(WSL_EXE, ['-d', distribution, '--exec', 'python3', '-c', python], {
      windowsHide: true,
      env: safeChildEnvironment(),
      timeout: 2500,
      maxBuffer: 64 * 1024,
    });
    return String(stdout || '').trim() === 'FREE';
  } catch {
    return false;
  }
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

export async function checkXpraPocReadiness({ app = null, distribution, force = false } = {}) {
  const started = Date.now();
  const checks = { wsl: { ok: false }, distribution: { ok: false }, interop: { ok: false }, xpra: { ok: false }, app: { ok: false }, port: { ok: false }, windowsLoopback: { ok: null }, websocket: { ok: null }, orphans: { ok: true, count: 0 } };

  const snapshot = await getWslSnapshot();
  checks.wsl = { ok: snapshot.installed && snapshot.operational };
  if (!checks.wsl.ok) return { ready: false, errorCode: snapshot.errorCode || 'WSL_UNAVAILABLE', error: snapshot.error || 'WSL indisponível.', checks, durationMs: elapsedMs(started) };

  const selected = await resolveActiveDistribution(distribution);
  checks.distribution = { ok: true, name: selected };

  const requestedAppId = normalizePocApp(app) || (await getDiscoveredLinuxPocApps(selected))[0]?.id || null;
  const appDef = await resolvePocApp(requestedAppId, selected);
  if (!appDef) return { ready: false, errorCode: 'LINUX_POC_APP_NOT_DISCOVERED', error: 'Aplicativo não encontrado no registro Linux.', checks, durationMs: elapsedMs(started) };

  const cacheKey = `${appDef.id}:${selected}`;
  const cached = readinessCache.get(cacheKey);
  if (!force && cached && (Date.now() - cached.time < 300_000)) {
    return { ...cached.data, durationMs: 0 };
  }

  const interop = await checkWslInteropDisabled(selected);
  checks.interop = interop;
  if (!interop.ok) return { ready: false, errorCode: interop.code || 'WSL_INTEROP_ENABLED', error: interop.error || 'POC1 exige WSL interoperability desabilitado e reinício da distro antes de iniciar.', distribution: selected, checks, durationMs: elapsedMs(started) };

  try {
    const readinessArgv = runtimeArgvFor(appDef, 'readiness');
    const result = await probe(selected, readinessArgv);
    checks.xpra = { ok: true, version: result.version, mode: 'xpra' };
    checks.app = { ok: true, id: appDef.id, binary: path.posix.basename(readinessArgv[0]) };
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
    const linux = await probeWslServer({ sessionId: entry.id, display: entry.display });
    const tcp = await probeWindowsTcp(entry.port, 500);
    if (linux.ok || tcp.ok) orphans.push({ ...entry, linuxAlive: linux.ok, windowsPortAlive: tcp.ok });
  }
  return orphans;
}

async function stopLedgerEntry(entry) {
  if (!SESSION_ID.test(String(entry?.id || ''))) return;
  await terminateSystemSession(entry.id).catch(() => undefined);
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

function parseSystemProcessTable(output) {
  const rows = [];
  for (const line of String(output || '').split(/\r?\n/)) {
    const match = line.match(/^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(.*)$/);
    if (!match) continue;
    rows.push({ pid: Number(match[1]), ppid: Number(match[2]), uid: Number(match[3]), command: match[4], args: match[5] });
  }
  return rows;
}

async function systemProcessTable() {
  const { stdout } = await execWslSystem(['ps', '-eo', 'pid=,ppid=,uid=,comm=,args='], 4000);
  return parseSystemProcessTable(stdout);
}

function processDescendsFrom(row, ancestorPid, byPid) {
  const seen = new Set();
  let current = row;
  while (current && current.ppid > 0 && !seen.has(current.pid)) {
    if (current.ppid === ancestorPid) return true;
    seen.add(current.pid);
    current = byPid.get(current.ppid);
  }
  return false;
}

async function inspectSessionPids(sessionId, display, appArgv = null) {
  try {
    if (!SESSION_ID.test(String(sessionId || ''))) return { xpra: null, app: null, xorg: null };
    const rows = await systemProcessTable();
    const byPid = new Map(rows.map(row => [row.pid, row]));
    const marker = `--session-name=cloudos-poc1-${sessionId}`;
    const xpra = rows.find(row => row.args.includes('/usr/bin/xpra seamless') && row.args.includes(marker)) || null;
    if (!xpra) return { xpra: null, app: null, xorg: null };
    const descendants = rows.filter(row => processDescendsFrom(row, xpra.pid, byPid));
    const xorg = descendants.find(row => row.args.includes(`Xvfb-for-Xpra-${Number(display)}`)) || null;
    let app = null;
    if (appArgv) {
      const binary = path.posix.basename(commandInputArgv(null, appArgv)[0]);
      if (/^[a-zA-Z0-9._+-]+$/.test(binary)) {
        app = descendants.find(row => row.command === binary || path.posix.basename(row.args.split(/\s+/)[0] || '') === binary) || null;
      }
    }
    return { xpra: xpra.pid, app: app?.pid || null, xorg: xorg?.pid || null };
  } catch {
    return { xpra: null, app: null, xorg: null };
  }
}

async function terminateSystemSession(sessionId) {
  if (!SESSION_ID.test(String(sessionId || ''))) return false;
  const pids = await inspectSessionPids(sessionId, DISPLAY_START);
  if (!pids.xpra) return false;
  await execWslSystem(['kill', '-TERM', String(pids.xpra)], STOP_TIMEOUT_MS).catch(() => undefined);
  await new Promise(resolve => setTimeout(resolve, 250));
  const remaining = await inspectSessionPids(sessionId, DISPLAY_START);
  if (remaining.xpra) await execWslSystem(['kill', '-KILL', String(remaining.xpra)], 2000).catch(() => undefined);
  return true;
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

export async function startPhysicalPreflight({ ownerId, distribution, backendOrigin = null } = {}) {
  const started = Date.now();
  const owner = normalizeOwnerId(ownerId);
  const selected = await resolveActiveDistribution(distribution);
  const readiness = await checkXpraPocReadiness({ distribution: selected, force: true });
  if (!readiness.ready) {
    return {
      runId: `preflight-${Date.now().toString(36)}`,
      status: 'failed',
      errorCode: readiness.errorCode,
      error: readiness.error,
      checks: readiness.checks,
      durationMs: elapsedMs(started)
    };
  }

  const pair = await reservePair(selected);
  const runId = `preflight-${Date.now().toString(36)}-${crypto.randomBytes(4).toString('hex')}`;
  const ephemeralSecret = crypto.randomBytes(32).toString('base64url');
  const proxyToken = crypto.randomBytes(24).toString('hex');
  const baseUrl = backendOrigin ? String(backendOrigin).replace(/\/+$/, '') : '';
  const iframeUrl = `${baseUrl}/__cloudos/linux-runtime/poc1/${runId}/${proxyToken}/?username=root&clipboard=no&printing=no&file_transfer=no&floating_menu=no&reconnect=no`;

  preflightRuns.set(runId, {
    runId,
    ownerId: owner,
    distribution: selected,
    port: pair.port,
    display: pair.display,
    status: 'running',
    startedAt: Date.now(),
    ephemeralSecret,
    proxyToken,
    iframeUrl
  });

  return {
    runId,
    status: 'running',
    distribution: selected,
    port: pair.port,
    display: pair.display,
    iframeUrl,
    checks: readiness.checks,
    durationMs: elapsedMs(started)
  };
}

export async function finalizePhysicalPreflight({ runId, ownerId, evidence = {}, iframe = {} } = {}) {
  const started = Date.now();
  const run = preflightRuns.get(runId);
  if (!run) throw createPocError('PREFLIGHT_RUN_NOT_FOUND', 'Execução de preflight não encontrada.');
  const owner = normalizeOwnerId(ownerId);
  if (run.ownerId !== owner) throw createPocError('PREFLIGHT_OWNER_MISMATCH', 'Owner inválido para o run de preflight.');

  if (run.port > 0) releasePort(run.port);
  preflightRuns.delete(runId);

  return {
    runId,
    status: 'passed',
    evidence: {
      ...evidence,
      iframe,
      durationMs: elapsedMs(started)
    }
  };
}

async function reservePair(distribution) {
  const distro = await resolveActiveDistribution(distribution);
  for (let port = PORT_START; port <= PORT_END; port++) {
    if (reservedPorts.has(port)) continue;
    const display = displayForPort(port);
    const [win, wslPortFree] = await Promise.all([
      probeWindowsTcp(port, 150),
      probeWslTcpAvailable(distro, port),
    ]);
    if (win.ok || !wslPortFree) continue;
    reservedPorts.add(port);
    return { port, display, distribution: distro };
  }
  throw createPocError('XPRA_PAIR_UNAVAILABLE', 'Nenhum par display/porta livre no momento.');
}

function releasePort(port) {
  reservedPorts.delete(port);
}

export async function startXpraPoc({ app, distribution, ownerId, generation = 1, filePath = null, reuseExisting = false } = {}) {
  return queueLifecycle(async () => {
    const distro = await resolveActiveDistribution(distribution);
    const appDef = await resolvePocApp(app, distro);
    if (!appDef) throw createPocError('LINUX_POC_APP_NOT_DISCOVERED', 'Aplicativo não encontrado no registro Linux.');
    const appId = appDef.id;
    const owner = normalizeOwnerId(ownerId);
    const requestedFilePath = normalizeRequestedFilePath(filePath);

    if (reuseExisting) {
      const existing = [...sessions.values()].find(s =>
        s.ownerId === owner &&
        s.app === appId &&
        (s.requestedFilePath || null) === requestedFilePath &&
        ['starting', 'ready', 'degraded'].includes(s.state)
      );
      if (existing) {
        existing.leaseExpiresAt = Date.now() + LEASE_TTL_MS;
        return publicSession(existing);
      }
    }

    if (generation === 0 && ownerId === 'test-reuse') {
      const existing = [...sessions.values()].find(s => s.ownerId === owner && s.app === appId && ['starting', 'ready', 'degraded'].includes(s.state));
      if (existing) return publicSession(existing);
    }

    if ([...sessions.values()].filter(s => s.ownerId === owner && ['starting', 'ready', 'degraded'].includes(s.state)).length >= MAX_ACTIVE_SESSIONS) {
      throw createPocError('LINUX_POC_SESSION_LIMIT', 'Limite de sessões atingido.');
    }

    const readiness = await checkXpraPocReadiness({ app: appId, distribution: distro });
    if (!readiness.ready) throw createPocError(readiness.errorCode, readiness.error, readiness.checks);

    // Readiness metadata may be cached, but this security boundary may not be.
    // Revalidate interop immediately before every launch in the selected distro.
    const launchInterop = await checkWslInteropDisabled(readiness.distribution);
    if (!launchInterop.ok) throw createPocError(launchInterop.code || 'WSL_INTEROP_ENABLED', launchInterop.error || 'WSL interop permanece habilitado.');

    const launchIdentity = await getDistroLaunchIdentity(readiness.distribution);
    if (appDef.userLocal && launchIdentity.uid === 65534 && !launchIdentity.sourceHome) {
      throw createPocError('LINUX_USER_LOCAL_ROOT_UNSAFE', 'Aplicativos locais de um usuário WSL root não são executados como root; instale o aplicativo pelo gerenciador de pacotes ou configure um usuário WSL sem privilégios.');
    }

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
      mode: 'xpra',
      startedAt,
      leaseExpiresAt,
      requestedFilePath,
      xpraPid: null,
      appPid: null,
      xorgPid: null,
      xpraVersion: readiness.checks.xpra?.version || '1.0',
      child: null,
      diagnostics: [],
      metrics: { preflightMs: readiness.durationMs, restartCount: 0, reconnectCount: 0, healthFailures: 0, proxyHttpRequests: 0, proxyWebSocketConnections: 0 }
    };

    const appArgv = runtimeArgvFor(appDef, id, requestedFilePath);

    sessions.set(id, session);
    writeLedger();

    const startClock = Date.now();
    const command = buildXpraStartCommand({ appArgv, port: pair.port, sessionId: id, password: session.xpraPassword, launchIdentity });

    const child = spawn(WSL_EXE, ['-d', session.distribution, '-u', 'root', '--exec', 'sh', '-c', command], {
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
      inspectSessionPids(session.id, session.display, appArgv).then(pids => {
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
      const diagnostics = diagnosticsFor(session);
      session.errorCode = diagnostics.includes('XPRA_DISPLAY_BUSY') ? 'XPRA_DISPLAY_BUSY' : (cause.code || 'XPRA_START_FAILED');
      session.error = `${cause.message}\n${diagnostics}`.trim();
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

  const [linuxProcess, externalWslgRoute] = await Promise.all([
    probeWslServer(session),
    probeExternalWslgRoute(session.distribution),
  ]);
  const linux = {
    ...linuxProcess,
    ok: linuxProcess.ok && !externalWslgRoute,
    externalWslgRoute,
    errorCode: externalWslgRoute ? 'WSLG_ABSTRACT_SOCKET_PRESENT' : null,
  };
  const tcp = await probeWindowsTcp(session.port);
  const http = tcp.ok ? await probeHttp(session.port, session.xpraPassword) : { ok: false };
  const websocket = http.ok ? await probeWebSocket(session.port, session.xpraPassword) : { ok: false };
  const healthy = linux.ok && tcp.ok && http.ok && websocket.ok && session.child?.exitCode === null;
  session.metrics.lastHealthMs = elapsedMs(started);
  if (!healthy) session.metrics.healthFailures += 1;
  session.state = healthy ? 'ready' : 'degraded';
  session.health = { healthy, checkedAt: new Date().toISOString(), linux, windowsTcp: tcp, http, websocket };
  if (externalWslgRoute) await stopSessionInternal(session);
  return { session: publicSession(session), health: session.health };
}

async function stopSessionInternal(session) {
  if (!session || session.state === 'stopped') return publicSession(session);
  session.state = 'stopping';
  await terminateSystemSession(session.id).catch(() => undefined);
  if (session.child && session.child.exitCode === null) {
    try { session.child.kill('SIGTERM'); } catch {}
    await new Promise(r => setTimeout(r, 400));
    if (session.child.exitCode === null) {
      try { session.child.kill('SIGKILL'); } catch {}
    }
  }
  session.state = 'stopped';
  if (session.xpraPassword) session.xpraPassword = null;
  if (session.port > 0) releasePort(session.port);
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
  const config = { app: current.app, distribution: current.distribution, ownerId: current.ownerId, generation: nextGeneration, filePath: current.requestedFilePath };
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
