#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const WSL_EXE = process.env.WSL_EXE || 'wsl.exe';
const MAX_BUFFER = 8 * 1024 * 1024;
const DEFAULT_OUTPUT_DIR = path.resolve('poc1-physical-evidence', 'automatic-app-integration');

function usage() {
  return `Usage:
  node scripts/collect-linux-containment-evidence.mjs \\
    --distribution Ubuntu --display 101 \\
    --session-name cloudos-poc1-xpra-SESSION_ID \\
    --app l3afpad [--output-dir PATH] [--prefix NAME]

Compatibility positional form:
  node scripts/collect-linux-containment-evidence.mjs [distribution] [display] [app] [session-name]

The session name may be omitted only when exactly one Xpra process on the requested
display exposes a --session-name value. Evidence is always written. PASS exits 0;
a containment violation exits 1; an incomplete/failed collection exits 2.`;
}

function parseArgs(argv) {
  const options = {
    distribution: 'Ubuntu',
    display: 101,
    app: 'l3afpad',
    sessionName: null,
    outputDir: DEFAULT_OUTPUT_DIR,
    prefix: null,
  };
  const positional = [];
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--help' || token === '-h') {
      process.stdout.write(`${usage()}\n`);
      process.exit(0);
    }
    if (!token.startsWith('--')) {
      positional.push(token);
      continue;
    }
    const value = argv[index + 1];
    if (!value || value.startsWith('--')) throw new Error(`Argumento sem valor: ${token}`);
    index += 1;
    if (token === '--distribution') options.distribution = value;
    else if (token === '--display') options.display = Number.parseInt(value, 10);
    else if (token === '--app') options.app = value;
    else if (token === '--session-name') options.sessionName = value;
    else if (token === '--output-dir') options.outputDir = path.resolve(value);
    else if (token === '--prefix') options.prefix = value;
    else throw new Error(`Argumento desconhecido: ${token}`);
  }

  if (positional[0]) options.distribution = positional[0];
  if (positional[1]) options.display = Number.parseInt(positional[1], 10);
  if (positional[2]) options.app = positional[2];
  if (positional[3]) options.sessionName = positional[3];

  if (!Number.isInteger(options.display) || options.display < 1 || options.display > 65535) throw new Error('Display inválido.');
  if (!/^[a-zA-Z0-9._+-]+$/.test(options.app)) throw new Error('Nome de processo inválido.');
  if (!/^[a-zA-Z0-9._+ -]{1,128}$/.test(options.distribution)) throw new Error('Distribuição inválida.');
  if (options.sessionName && !/^[a-zA-Z0-9._:-]{1,192}$/.test(options.sessionName)) throw new Error('Session name inválido.');
  if (options.prefix && !/^[a-zA-Z0-9._-]{1,96}$/.test(options.prefix)) throw new Error('Prefixo inválido.');
  options.prefix ||= `linux-containment-display-${options.display}`;
  return options;
}

function decodeOutput(value) {
  const buffer = Buffer.isBuffer(value) ? value : Buffer.from(value || '');
  if (buffer.length === 0) return '';
  const sampleLength = Math.min(buffer.length, 512);
  let nulCount = 0;
  for (let index = 0; index < sampleLength; index += 1) if (buffer[index] === 0) nulCount += 1;
  return buffer.toString(nulCount > sampleLength / 5 ? 'utf16le' : 'utf8').replace(/^\uFEFF/, '');
}

function runSystem(command, args = [], { allowFailure = false, raw = false } = {}) {
  const invocation = ['--system', '-u', 'root', '--', command, ...args.map(String)];
  const result = spawnSync(WSL_EXE, invocation, {
    windowsHide: true,
    encoding: null,
    maxBuffer: MAX_BUFFER,
    timeout: 15_000,
  });
  const stdout = result.stdout || Buffer.alloc(0);
  const stderr = decodeOutput(result.stderr).trim();
  const status = Number.isInteger(result.status) ? result.status : 255;
  if (!allowFailure && (result.error || status !== 0)) {
    const reason = result.error?.message || stderr || `${command} saiu com código ${status}`;
    throw new Error(`WSL_SYSTEM_COMMAND_FAILED: ${reason}`);
  }
  return { ok: !result.error && status === 0, status, stdout: raw ? stdout : decodeOutput(stdout), stderr };
}

function nsenter(pid, command, args = [], options = {}) {
  return runSystem('nsenter', ['-t', String(pid), '-m', '-p', '--', command, ...args], options);
}

function parseProcessInventory(text) {
  const processes = [];
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(/^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s*(.*)$/);
    if (!match) continue;
    processes.push({
      pid: Number(match[1]), ppid: Number(match[2]), uid: Number(match[3]), gid: Number(match[4]),
      user: match[5], stat: match[6], command: match[7], args: match[8],
    });
  }
  return processes;
}

function processDescendsFrom(processesByPid, pid, ancestorPid) {
  const visited = new Set();
  let current = processesByPid.get(pid);
  while (current && current.pid > 0 && !visited.has(current.pid)) {
    if (current.pid === ancestorPid) return true;
    visited.add(current.pid);
    current = processesByPid.get(current.ppid);
  }
  return false;
}

function processDepthFrom(processesByPid, pid, ancestorPid) {
  let depth = 0;
  let current = processesByPid.get(pid);
  const visited = new Set();
  while (current && current.pid > 0 && !visited.has(current.pid)) {
    if (current.pid === ancestorPid) return depth;
    visited.add(current.pid);
    depth += 1;
    current = processesByPid.get(current.ppid);
  }
  return Number.MAX_SAFE_INTEGER;
}

function ancestorsFor(processesByPid, pid) {
  const result = [];
  const visited = new Set();
  let current = processesByPid.get(pid);
  while (current && current.pid > 0 && !visited.has(current.pid)) {
    result.push(current);
    visited.add(current.pid);
    current = processesByPid.get(current.ppid);
  }
  return result;
}

function extractSessionName(args) {
  return args.match(/(?:^|\s)--session-name=(?:'([^']+)'|"([^"]+)"|(\S+))/)?.slice(1).find(Boolean) || null;
}

function displayAppears(args, display) {
  return new RegExp(`(?:^|\\s):${display}(?=\\s|$)`).test(args);
}

function parseEnvironment(buffer) {
  const result = {};
  for (const item of buffer.toString('utf8').split('\0')) {
    const separator = item.indexOf('=');
    if (separator > 0) result[item.slice(0, separator)] = item.slice(separator + 1);
  }
  return result;
}

function decodeMountPath(value) {
  return value.replace(/\\([0-7]{3})/g, (_match, octal) => String.fromCharCode(Number.parseInt(octal, 8)));
}

function parseMountInfo(text) {
  const mounts = [];
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim()) continue;
    const fields = line.trim().split(/\s+/);
    const separator = fields.indexOf('-');
    if (separator < 6) continue;
    mounts.push({
      mountId: Number(fields[0]), parentId: Number(fields[1]), majorMinor: fields[2],
      root: decodeMountPath(fields[3]), mountPoint: decodeMountPath(fields[4]),
      mountOptions: fields[5].split(','), optionalFields: fields.slice(6, separator),
      filesystem: fields[separator + 1], source: decodeMountPath(fields[separator + 2] || ''),
      superOptions: (fields[separator + 3] || '').split(','),
    });
  }
  return mounts;
}

function processEvidence(process) {
  return {
    pid: process.pid, ppid: process.ppid, uid: process.uid, gid: process.gid, user: process.user,
    stat: process.stat, command: process.command, args: process.args,
  };
}

function pathProbe(pid, target) {
  const type = nsenter(pid, 'stat', ['-Lc', '%F', '--', target], { allowFailure: true });
  if (!type.ok) return { path: target, exists: false };
  const mode = nsenter(pid, 'stat', ['-Lc', '%a', '--', target], { allowFailure: true });
  const identity = nsenter(pid, 'stat', ['-Lc', '%d:%i', '--', target], { allowFailure: true });
  const children = nsenter(pid, 'ls', ['-A', '--', target], { allowFailure: true });
  const executable = nsenter(pid, 'test', ['-x', target], { allowFailure: true });
  return {
    path: target, exists: true, type: type.stdout.trim(), mode: mode.ok ? mode.stdout.trim() : null,
    deviceInode: identity.ok ? identity.stdout.trim() : null,
    empty: children.ok ? children.stdout.trim().length === 0 : null, executable: executable.ok,
  };
}

function namespaceFor(pid, namespace) {
  const result = runSystem('readlink', [`/proc/${pid}/ns/${namespace}`], { allowFailure: true });
  return result.ok ? result.stdout.trim() : null;
}

function safeActual(value) {
  if (value === undefined) return null;
  if (typeof value === 'string') return value.slice(0, 1000);
  return value;
}

function assertionRecorder() {
  const assertions = [];
  return {
    assertions,
    check(id, condition, expected, actual, detail = null) {
      assertions.push({ id, ok: Boolean(condition), expected, actual: safeActual(actual), ...(detail ? { detail } : {}) });
      return Boolean(condition);
    },
  };
}

function collectEvidence(options) {
  const inventoryText = runSystem('ps', ['-ww', '-eo', 'pid=,ppid=,uid=,gid=,user=,stat=,comm=,args=']).stdout;
  const processes = parseProcessInventory(inventoryText);
  const processesByPid = new Map(processes.map(process => [process.pid, process]));
  const onDisplay = processes.filter(process =>
    /^(?:python\d*(?:\.\d+)?|xpra)$/.test(path.posix.basename(process.command))
      && process.args.includes('/xpra') && process.args.includes('seamless') && displayAppears(process.args, options.display)
  );
  const namedCandidates = onDisplay.filter(process => {
    const actual = extractSessionName(process.args);
    return options.sessionName ? actual === options.sessionName : Boolean(actual);
  });
  if (namedCandidates.length !== 1) {
    throw new Error(`XPRA_SESSION_CORRELATION_FAILED: esperada 1 sessão em :${options.display}${options.sessionName ? ` com nome ${options.sessionName}` : ''}; encontradas ${namedCandidates.length}`);
  }

  const xpra = namedCandidates[0];
  const sessionName = extractSessionName(xpra.args);
  const appBasename = options.app.toLowerCase();
  const appCandidates = processes.filter(process => {
    if (process.pid === xpra.pid || !processDescendsFrom(processesByPid, process.pid, xpra.pid)) return false;
    const command = path.posix.basename(process.command).toLowerCase();
    const firstArg = path.posix.basename(process.args.trim().split(/\s+/)[0] || '').toLowerCase();
    return command === appBasename || firstArg === appBasename;
  }).sort((left, right) =>
    processDepthFrom(processesByPid, left.pid, xpra.pid) - processDepthFrom(processesByPid, right.pid, xpra.pid) || left.pid - right.pid
  );
  if (appCandidates.length === 0) throw new Error(`APP_PROCESS_MISSING: ${options.app} não é descendente da sessão Xpra correlacionada.`);
  const app = appCandidates[0];

  const xServers = processes.filter(process =>
    process.pid !== xpra.pid && processDescendsFrom(processesByPid, process.pid, xpra.pid)
      && /(?:Xvfb|Xorg)/i.test(`${process.command} ${process.args}`) && displayAppears(process.args, options.display)
  );
  if (xServers.length !== 1) throw new Error(`X_SERVER_CORRELATION_FAILED: esperado 1 Xvfb/Xorg descendente em :${options.display}; encontrados ${xServers.length}`);
  const xServer = xServers[0];

  const envRaw = runSystem('cat', [`/proc/${app.pid}/environ`], { raw: true }).stdout;
  const appEnvironment = parseEnvironment(envRaw);
  const allowedEnvironmentNames = [
    'DISPLAY', 'XAUTHORITY', 'GDK_BACKEND', 'QT_QPA_PLATFORM', 'SDL_VIDEODRIVER', 'CLUTTER_BACKEND',
    'XDG_SESSION_TYPE', 'XDG_RUNTIME_DIR', 'HOME', 'USER', 'LOGNAME', 'PATH', 'MOZ_ENABLE_WAYLAND',
    'ELECTRON_OZONE_PLATFORM_HINT',
  ];
  const environmentEvidence = Object.fromEntries(
    allowedEnvironmentNames.filter(name => Object.hasOwn(appEnvironment, name)).map(name => [name, appEnvironment[name]])
  );
  const forbiddenEnvironmentNames = ['WAYLAND_*', 'PULSE_*', 'WSL_INTEROP', 'WSLENV', 'XPRA_PASSWORD'];
  const forbiddenEnvironmentPresent = Object.keys(appEnvironment).filter(name =>
    name.startsWith('WAYLAND_') || name.startsWith('PULSE_') || ['WSL_INTEROP', 'WSLENV', 'XPRA_PASSWORD'].includes(name)
  ).sort();

  const mountInfoText = runSystem('cat', [`/proc/${app.pid}/mountinfo`]).stdout;
  const mounts = parseMountInfo(mountInfoText);
  const mountByPath = new Map(mounts.map(mount => [mount.mountPoint, mount]));
  const relevantMountPaths = ['/tmp', '/run/user', '/run/xpra', '/mnt/wslg', '/run/WSL', '/run/systemd', '/run/dbus', '/init'];
  const relevantMounts = relevantMountPaths.map(target => mountByPath.get(target)).filter(Boolean);
  const pathProbes = Object.fromEntries(['/mnt/wslg', '/run/WSL', '/init', '/run/xpra'].map(target => [target, pathProbe(app.pid, target)]));
  const x0Visible = nsenter(app.pid, 'test', ['-S', '/tmp/.X11-unix/X0'], { allowFailure: true }).ok;
  const containedXSocket = nsenter(app.pid, 'test', ['-S', `/tmp/.X11-unix/X${options.display}`], { allowFailure: true }).ok;
  const waylandVisible = nsenter(app.pid, 'test', ['-S', '/mnt/wslg/runtime-dir/wayland-0'], { allowFailure: true }).ok;
  const unixSocketTable = runSystem('cat', [`/proc/${app.pid}/net/unix`], { allowFailure: true });
  const abstractWslgX0 = unixSocketTable.ok
    ? unixSocketTable.stdout.split(/\r?\n/).filter(line => line.includes('@/tmp/.X11-unix/X0'))
    : ['socket table unavailable'];
  const xpraSocketFind = nsenter(app.pid, 'find', ['/run/xpra', '-maxdepth', '3', '-type', 's', '-print'], { allowFailure: true });
  const xpraSockets = xpraSocketFind.ok ? xpraSocketFind.stdout.split(/\r?\n/).map(value => value.trim()).filter(Boolean) : [];
  const matchingXpraSockets = xpraSockets.filter(socketPath => new RegExp(`(?:^|[-_:])${options.display}(?:$|[-_.:])`).test(path.posix.basename(socketPath)));

  const interopProbe = nsenter(app.pid, 'cat', ['/proc/sys/fs/binfmt_misc/WSLInterop'], { allowFailure: true });
  const interopState = interopProbe.ok ? interopProbe.stdout.trim() : 'unregistered';
  const namespaceNames = ['mnt', 'pid', 'user', 'net'];
  const namespaces = Object.fromEntries(namespaceNames.map(name => [name, namespaceFor(app.pid, name)]));
  const xpraNamespaces = Object.fromEntries(namespaceNames.map(name => [name, namespaceFor(xpra.pid, name)]));
  const xServerNamespaces = Object.fromEntries(namespaceNames.map(name => [name, namespaceFor(xServer.pid, name)]));
  const ancestors = ancestorsFor(processesByPid, xpra.pid);
  const ancestorNamespaces = ancestors.map(process => ({
    pid: process.pid, command: process.command, mnt: namespaceFor(process.pid, 'mnt'), pidNamespace: namespaceFor(process.pid, 'pid'),
  }));
  const outsideMountAncestor = ancestorNamespaces.find(item => item.mnt && item.mnt !== namespaces.mnt) || null;

  const bindTcp = xpra.args.match(/--bind-tcp=([^\s,]+):(\d+),auth=env/);
  const tcpBinding = bindTcp ? { host: bindTcp[1], port: Number(bindTcp[2]), auth: 'env' } : null;
  const listenerText = runSystem('ss', ['-ltnp'], { allowFailure: true }).stdout;
  const listenerLines = tcpBinding ? listenerText.split(/\r?\n/).filter(line => line.includes(`${tcpBinding.host}:${tcpBinding.port}`)) : [];

  const relevantTree = processes.filter(process => processDescendsFrom(processesByPid, process.pid, xpra.pid)).sort((left, right) => left.pid - right.pid);
  const wslgTreeMembers = relevantTree.filter(process => /(?:WSLGd|weston|Xwayland|msrdc\.exe|wayland-0|\/mnt\/wslg)/i.test(`${process.command} ${process.args}`));
  const globalWslgProcesses = processes.filter(process => /(?:WSLGd|weston|Xwayland|msrdc\.exe)/i.test(`${process.command} ${process.args}`));

  const { assertions, check } = assertionRecorder();
  check('xpra.unique-display-session', namedCandidates.length === 1, 'exactly one Xpra process matching display and session-name', namedCandidates.map(item => item.pid));
  check('xpra.session-name-exact', sessionName === (options.sessionName || sessionName), options.sessionName || 'unique inferred session-name', sessionName);
  check('xpra.display-exact', displayAppears(xpra.args, options.display), `:${options.display}`, xpra.args);
  check('xpra.bind-noabstract', xpra.args.includes('--bind=noabstract'), '--bind=noabstract', xpra.args.includes('--bind=noabstract'));
  check('xpra.tcp-authenticated', Boolean(tcpBinding?.host) && tcpBinding?.auth === 'env', 'declared TCP binding with auth=env', tcpBinding);
  check('xpra.tcp-listener-present', listenerLines.length >= 1, 'one listener for the correlated authenticated Xpra port', listenerLines);
  check('process.app-descendant', processDescendsFrom(processesByPid, app.pid, xpra.pid), `app descends from PID ${xpra.pid}`, { appPid: app.pid, appPpid: app.ppid });
  check('process.xserver-descendant', processDescendsFrom(processesByPid, xServer.pid, xpra.pid), `X server descends from PID ${xpra.pid}`, { xServerPid: xServer.pid, xServerPpid: xServer.ppid });
  check('process.uid-nonroot-xpra', xpra.uid > 0, 'UID > 0', xpra.uid);
  check('process.uid-nonroot-xserver', xServer.uid > 0, 'UID > 0', xServer.uid);
  check('process.uid-nonroot-app', app.uid > 0, 'UID > 0', app.uid);
  check('process.same-mount-namespace', namespaces.mnt && namespaces.mnt === xpraNamespaces.mnt && namespaces.mnt === xServerNamespaces.mnt, 'Xpra, X server and app share the isolated mount namespace', { app: namespaces.mnt, xpra: xpraNamespaces.mnt, xServer: xServerNamespaces.mnt });
  check('process.same-pid-namespace', namespaces.pid && namespaces.pid === xpraNamespaces.pid && namespaces.pid === xServerNamespaces.pid, 'Xpra, X server and app share the isolated PID namespace', { app: namespaces.pid, xpra: xpraNamespaces.pid, xServer: xServerNamespaces.pid });
  check('namespace.private-mount', Boolean(outsideMountAncestor), 'at least one ancestor remains outside the session mount namespace', outsideMountAncestor);
  check('tree.no-wslg-process', wslgTreeMembers.length === 0, 'no WSLg/RAIL process in the correlated tree', wslgTreeMembers.map(processEvidence));
  check('env.display', appEnvironment.DISPLAY === `:${options.display}`, `:${options.display}`, appEnvironment.DISPLAY || null);
  check('env.gdk-x11', appEnvironment.GDK_BACKEND === 'x11', 'x11', appEnvironment.GDK_BACKEND || null);
  check('env.qt-xcb', appEnvironment.QT_QPA_PLATFORM === 'xcb', 'xcb', appEnvironment.QT_QPA_PLATFORM || null);
  check('env.forbidden-absent', forbiddenEnvironmentPresent.length === 0, `absent: ${forbiddenEnvironmentNames.join(', ')}`, forbiddenEnvironmentPresent);
  check('env.path-no-windows', !/(?:^|:)\/mnt\/[a-z](?:\/|:|$)/i.test(appEnvironment.PATH || ''), 'PATH contains no Windows mount', appEnvironment.PATH || null);
  check('mount.tmp-private', mountByPath.get('/tmp')?.filesystem === 'tmpfs', '/tmp is tmpfs', mountByPath.get('/tmp') || null);
  check('mount.runtime-private', mountByPath.get('/run/user')?.filesystem === 'tmpfs', '/run/user is tmpfs', mountByPath.get('/run/user') || null);
  check('mount.xpra-private', mountByPath.get('/run/xpra')?.filesystem === 'tmpfs', '/run/xpra is tmpfs', mountByPath.get('/run/xpra') || null);
  for (const target of ['/mnt/wslg', '/run/WSL']) {
    const probe = pathProbes[target];
    const mount = mountByPath.get(target);
    const safe = !probe.exists || (Boolean(mount) && probe.mode === '0' && probe.empty === true);
    check(`mask.${target === '/mnt/wslg' ? 'mnt-wslg' : 'run-wsl'}`, safe, `${target} absent or an empty mode-000 mount`, { probe, mount: mount || null });
  }
  const initProbe = pathProbes['/init'];
  const initMount = mountByPath.get('/init');
  const initOptions = new Set([...(initMount?.mountOptions || []), ...(initMount?.superOptions || [])]);
  check('mask.init-file', initProbe.exists && initProbe.type === 'regular empty file' && initProbe.mode === '0' && initProbe.executable === false, '/init is a non-executable mode-000 regular empty file', initProbe);
  check('mask.init-mount-flags', Boolean(initMount) && ['ro', 'noexec', 'nosuid', 'nodev'].every(flag => initOptions.has(flag)), '/init mount is ro,noexec,nosuid,nodev', initMount || null);
  check('mask.wslg-x11-hidden', !x0Visible, '/tmp/.X11-unix/X0 is not visible', x0Visible);
  check('mask.wslg-abstract-x11-absent', unixSocketTable.ok && abstractWslgX0.length === 0, 'no abstract @/tmp/.X11-unix/X0 socket in the session network view', abstractWslgX0);
  check('mask.wslg-wayland-hidden', !waylandVisible, '/mnt/wslg/runtime-dir/wayland-0 is not visible', waylandVisible);
  check('xserver.display-socket', containedXSocket, `/tmp/.X11-unix/X${options.display} is a socket`, containedXSocket);
  check('xpra.private-socket', xpraSocketFind.ok && matchingXpraSockets.length >= 1, `Xpra filesystem socket for :${options.display} under private /run/xpra`, { sockets: xpraSockets, matching: matchingXpraSockets });
  check('interop.disabled', interopState === 'unregistered' || interopState.startsWith('disabled'), 'WSLInterop disabled or unregistered inside the session', interopState);

  return {
    schemaVersion: 1, collectedAt: new Date().toISOString(), collector: 'scripts/collect-linux-containment-evidence.mjs', failClosed: true,
    inputs: {
      distribution: options.distribution, display: options.display, app: options.app,
      requestedSessionName: options.sessionName, correlatedSessionName: sessionName,
    },
    verdict: assertions.every(assertion => assertion.ok) ? 'PASS' : 'FAIL', assertions,
    processes: {
      xpra: processEvidence(xpra), xServer: processEvidence(xServer), app: processEvidence(app),
      appCandidates: appCandidates.map(processEvidence), correlatedTree: relevantTree.map(processEvidence),
      globalWslgProcesses: globalWslgProcesses.map(processEvidence),
    },
    environment: { allowed: environmentEvidence, forbiddenNames: forbiddenEnvironmentNames, forbiddenPresent: forbiddenEnvironmentPresent },
    namespaces: { app: namespaces, xpra: xpraNamespaces, xServer: xServerNamespaces, ancestors: ancestorNamespaces, outsideMountAncestor },
    mounts: { relevant: relevantMounts, probes: pathProbes },
    sockets: {
      x11: { wslgDisplay0Visible: x0Visible, abstractWslgDisplay0: abstractWslgX0, containedDisplayVisible: containedXSocket },
      xpra: xpraSockets, tcpBinding, tcpListeners: listenerLines,
    },
    interop: interopState,
  };
}

function humanLog(evidence) {
  const lines = [
    `CLOUDOS LINUX CONTAINMENT EVIDENCE: ${evidence.verdict}`,
    `collectedAt=${evidence.collectedAt}`,
    `failClosed=${evidence.failClosed}`,
  ];
  if (evidence.inputs) {
    lines.push(
      `distribution=${evidence.inputs.distribution}`,
      `display=:${evidence.inputs.display}`,
      `sessionName=${evidence.inputs.correlatedSessionName || evidence.inputs.requestedSessionName || '<unresolved>'}`,
      `app=${evidence.inputs.app}`,
    );
  }
  if (evidence.processes) {
    for (const key of ['xpra', 'xServer', 'app']) {
      const process = evidence.processes[key];
      lines.push(`${key}: pid=${process.pid} ppid=${process.ppid} uid=${process.uid} gid=${process.gid} command=${process.command}`);
    }
  }
  lines.push('', 'ASSERTIONS');
  for (const assertion of evidence.assertions || []) {
    lines.push(`${assertion.ok ? 'PASS' : 'FAIL'} ${assertion.id} expected=${assertion.expected} actual=${JSON.stringify(assertion.actual)}`);
  }
  if (evidence.fatalError) lines.push('', `FATAL ${evidence.fatalError}`);
  lines.push('');
  return lines.join('\n');
}

function writeEvidence(options, evidence) {
  mkdirSync(options.outputDir, { recursive: true });
  const jsonPath = path.join(options.outputDir, `${options.prefix}.json`);
  const logPath = path.join(options.outputDir, `${options.prefix}.log`);
  writeFileSync(jsonPath, `${JSON.stringify(evidence, null, 2)}\n`, 'utf8');
  writeFileSync(logPath, humanLog(evidence), 'utf8');
  return { jsonPath, logPath };
}

let options;
try {
  options = parseArgs(process.argv.slice(2));
} catch (error) {
  process.stderr.write(`${error.message}\n\n${usage()}\n`);
  process.exit(2);
}

let evidence;
let exitCode;
try {
  evidence = collectEvidence(options);
  exitCode = evidence.verdict === 'PASS' ? 0 : 1;
} catch (error) {
  evidence = {
    schemaVersion: 1, collectedAt: new Date().toISOString(), collector: 'scripts/collect-linux-containment-evidence.mjs', failClosed: true,
    inputs: { distribution: options.distribution, display: options.display, app: options.app, requestedSessionName: options.sessionName },
    verdict: 'FAIL',
    assertions: [{ id: 'collection.complete', ok: false, expected: 'complete physical evidence for one exactly correlated session', actual: 'collection failed' }],
    fatalError: error instanceof Error ? error.message : String(error),
  };
  exitCode = 2;
}

try {
  const outputs = writeEvidence(options, evidence);
  process.stdout.write(`${humanLog(evidence)}JSON=${outputs.jsonPath}\nLOG=${outputs.logPath}\n`);
} catch (error) {
  process.stderr.write(`EVIDENCE_WRITE_FAILED: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(2);
}

process.exit(exitCode);
