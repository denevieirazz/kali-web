import { execFile, execFileSync, spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { WebSocket } from 'ws';
import {
  POWERSHELL_EXE,
  WSL_EXE,
  getWslSnapshot,
  normalizeName,
  runWsl,
  safeChildEnvironment,
  validateInstalledAsync,
} from '../wsl/distroService.js';
import { getXpraPocSessions } from './xpraPoc.js';
import {
  XPRA_BIND_TCP_HOST,
  XPRA_DISPLAY_END,
  XPRA_DISPLAY_START,
  XPRA_PORT_END,
  XPRA_PORT_START,
  chooseXpraPair,
  validateLedgerPair,
} from './xpraPairAllocator.js';

const execFileAsync = promisify(execFile);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '../../..');
const EVIDENCE_ROOT = path.join(PROJECT_ROOT, 'poc1-physical-evidence');
const SCREENSHOTS_DIR = path.join(EVIDENCE_ROOT, 'screenshots');
const LOGS_DIR = path.join(EVIDENCE_ROOT, 'logs');
const TELEMETRY_DIR = path.join(EVIDENCE_ROOT, 'telemetry');
const REPORT_FILE = path.join(EVIDENCE_ROOT, 'POC1_PREFLIGHT_REPORT.md');
const WINDOW_BASELINE_FILE = path.join(EVIDENCE_ROOT, 'WINDOW_BASELINE.json');
const RUNTIME_LEDGER_FILE = path.join(os.tmpdir(), 'cloudos-linux-runtime-poc1-sessions.json');
const PORT_START = XPRA_PORT_START;
const PORT_END = XPRA_PORT_END;
const DISPLAY_START = XPRA_DISPLAY_START;
const DISPLAY_END = XPRA_DISPLAY_END;
const STATIC_TIMEOUT_MS = 15_000;
const SERVER_TIMEOUT_MS = 25_000;
const PROXY_TIMEOUT_MS = 5_000;
const STOP_TIMEOUT_MS = 6_000;
const AUTO_FINALIZE_MS = 35_000;
const OWNER_ID = /^[a-zA-Z0-9._:-]{1,128}$/;
const BOUNDARY_ORDER = ['WSL', 'DISTRO', 'XPRA', 'TRANSPORTE', 'PROXY', 'IFRAME'];
const REQUIRED_XPRA_FLAGS = [
  '--start-child',
  '--exit-with-children',
  '--session-name',
  '--bind-tcp',
  '--html',
  '--start-new-commands',
  '--bind',
];

const runs = new Map();
const proxySessions = new Map();
let preflightQueue = Promise.resolve();
let exitHookInstalled = false;

function queuePreflight(operation) {
  const next = preflightQueue.then(operation, operation);
  preflightQueue = next.catch(() => undefined);
  return next;
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function elapsedMs(started) {
  return Math.max(0, Date.now() - started);
}

function normalizeOwnerId(value) {
  const ownerId = String(value || 'cloudos-poc1-preflight').trim();
  if (!OWNER_ID.test(ownerId)) {
    const error = new Error('Identificador da CloudOS Window inválido para o preflight.');
    error.code = 'PREFLIGHT_OWNER_INVALID';
    throw error;
  }
  return ownerId;
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'"'"'`)}'`;
}

function evidenceText(value) {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value.trim();
  try { return JSON.stringify(value); } catch { return String(value); }
}

function logRun(run, message) {
  const line = `${new Date().toISOString()} ${message}\n`;
  run.logLines.push(line);
  if (!run.logFile) return;
  try { fs.appendFileSync(run.logFile, line, 'utf8'); } catch {}
}

function addCheck(run, {
  id,
  layer,
  status,
  code,
  component,
  cause,
  evidence = '',
  durationMs = null,
}) {
  const check = {
    id,
    layer,
    status,
    code,
    component,
    cause,
    evidence: evidenceText(evidence),
    durationMs: Number.isFinite(durationMs) ? Math.round(durationMs) : null,
  };
  const index = run.checks.findIndex(item => item.id === id);
  if (index >= 0) run.checks[index] = check;
  else run.checks.push(check);
  logRun(run, `${status} ${layer}/${code} component=${component} cause=${cause} evidence=${check.evidence}`);
  return check;
}

function boundarySummary(run) {
  const result = {};
  let upstreamFailed = null;
  for (const layer of BOUNDARY_ORDER) {
    const checks = run.checks.filter(check => check.layer === layer);
    const failure = checks.find(check => check.status === 'FAIL');
    const warning = checks.find(check => check.status === 'WARN');
    if (failure) {
      result[layer] = {
        status: 'FAIL', code: failure.code, component: failure.component, cause: failure.cause, evidence: failure.evidence,
      };
      upstreamFailed ||= layer;
      continue;
    }
    if (!checks.length) {
      result[layer] = upstreamFailed
        ? {
          status: 'FAIL', code: `${layer}_NOT_REACHED`, component: layer,
          cause: `Camada não alcançada porque ${upstreamFailed} falhou antes.`, evidence: `blockedBy=${upstreamFailed}`,
        }
        : {
          status: 'WARN', code: `${layer}_PENDING`, component: layer,
          cause: 'Camada ainda não executada nesta fase do preflight.', evidence: `phase=${run.phase}`,
        };
      continue;
    }
    if (warning) {
      result[layer] = {
        status: 'WARN', code: warning.code, component: warning.component, cause: warning.cause, evidence: warning.evidence,
      };
      continue;
    }
    const last = checks.at(-1);
    result[layer] = {
      status: 'PASS', code: last.code, component: last.component, cause: last.cause, evidence: last.evidence,
    };
  }
  return result;
}

function decisionFor(run) {
  return run.checks.some(check => check.status === 'FAIL') ? 'NO_GO' : 'GO';
}

function phaseDecision(run) {
  return run.phase === 'complete' ? decisionFor(run) : 'NO_GO';
}

function publicRun(run) {
  return {
    runId: run.id,
    ownerId: run.ownerId,
    phase: run.phase,
    decision: phaseDecision(run),
    readyToClickXclock: run.phase === 'complete' && decisionFor(run) === 'GO',
    distribution: run.distribution || null,
    display: run.session?.display ?? null,
    port: run.session?.port ?? null,
    clientUrl: run.phase === 'awaiting_iframe' ? run.clientUrl : null,
    boundaries: boundarySummary(run),
    checks: run.checks,
    metrics: { ...run.metrics },
    artifacts: {
      root: EVIDENCE_ROOT,
      report: REPORT_FILE,
      windowBaseline: WINDOW_BASELINE_FILE,
      screenshots: SCREENSHOTS_DIR,
      logs: LOGS_DIR,
      telemetry: TELEMETRY_DIR,
      runLog: run.logFile || null,
      runTelemetry: run.telemetryFile || null,
    },
  };
}

function prepareEvidenceDirectories(run) {
  const started = Date.now();
  const directories = [EVIDENCE_ROOT, SCREENSHOTS_DIR, LOGS_DIR, TELEMETRY_DIR];
  try {
    for (const directory of directories) {
      fs.mkdirSync(directory, { recursive: true });
      const probe = path.join(directory, `.poc1-preflight-write-${run.id}`);
      fs.writeFileSync(probe, 'write-ok', 'utf8');
      fs.rmSync(probe, { force: true });
    }
    run.logFile = path.join(LOGS_DIR, `preflight-${run.id}.log`);
    run.telemetryFile = path.join(TELEMETRY_DIR, `preflight-${run.id}.json`);
    fs.writeFileSync(run.logFile, '', 'utf8');
    addCheck(run, {
      id: 'forensics-directories', layer: 'FORENSICS', status: 'PASS', code: 'EVIDENCE_DIRECTORIES_WRITABLE',
      component: 'screenshots/logs/telemetry', cause: 'Diretórios de evidência existem e aceitaram escrita.',
      evidence: directories.join(' | '), durationMs: elapsedMs(started),
    });
    return true;
  } catch (cause) {
    addCheck(run, {
      id: 'forensics-directories', layer: 'FORENSICS', status: 'FAIL', code: 'EVIDENCE_DIRECTORY_NOT_WRITABLE',
      component: 'screenshots/logs/telemetry', cause: 'Não foi possível preparar diretório gravável para evidência física.',
      evidence: cause.message, durationMs: elapsedMs(started),
    });
    return false;
  }
}

async function gitContext() {
  try {
    const [{ stdout: sha }, { stdout: branch }] = await Promise.all([
      execFileAsync('git', ['rev-parse', 'HEAD'], { cwd: PROJECT_ROOT, timeout: 3000, windowsHide: true }),
      execFileAsync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { cwd: PROJECT_ROOT, timeout: 3000, windowsHide: true }),
    ]);
    return { sha: sha.trim(), branch: branch.trim() };
  } catch {
    return { sha: process.env.GITHUB_SHA || null, branch: process.env.GITHUB_HEAD_REF || null };
  }
}

async function captureWindowBaseline(run) {
  const started = Date.now();
  if (process.platform !== 'win32' || !fs.existsSync(POWERSHELL_EXE)) {
    addCheck(run, {
      id: 'window-baseline', layer: 'FORENSICS', status: 'FAIL', code: 'WINDOW_BASELINE_UNAVAILABLE',
      component: 'Windows HWND baseline', cause: 'PowerShell clássico do Windows não está disponível neste host.',
      evidence: `platform=${process.platform}; powershell=${POWERSHELL_EXE}`, durationMs: elapsedMs(started),
    });
    return false;
  }
  const script = [
    "$ErrorActionPreference='Stop'",
    '$items = @(Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object Id,ProcessName,MainWindowTitle,@{Name="MainWindowHandle";Expression={[string]$_.MainWindowHandle}} | Sort-Object ProcessName,Id)',
    '$items | ConvertTo-Json -Depth 4 -Compress',
  ].join('; ');
  try {
    const { stdout } = await execFileAsync(POWERSHELL_EXE, ['-NoProfile', '-NonInteractive', '-Command', script], {
      windowsHide: true, timeout: 8000, maxBuffer: 2 * 1024 * 1024, env: safeChildEnvironment(),
    });
    const raw = String(stdout || '').trim();
    const parsed = raw ? JSON.parse(raw) : [];
    const windows = Array.isArray(parsed) ? parsed : [parsed];
    fs.writeFileSync(WINDOW_BASELINE_FILE, JSON.stringify({
      capturedAt: new Date().toISOString(), hostname: os.hostname(), platform: process.platform, windows, count: windows.length,
    }, null, 2), 'utf8');
    addCheck(run, {
      id: 'window-baseline', layer: 'FORENSICS', status: 'PASS', code: 'WINDOW_BASELINE_CAPTURED',
      component: 'Windows HWND baseline', cause: 'Processos com MainWindowHandle foram registrados antes do dry run.',
      evidence: `count=${windows.length}; file=${WINDOW_BASELINE_FILE}`, durationMs: elapsedMs(started),
    });
    return true;
  } catch (cause) {
    addCheck(run, {
      id: 'window-baseline', layer: 'FORENSICS', status: 'FAIL', code: 'WINDOW_BASELINE_CAPTURE_FAILED',
      component: 'Windows HWND baseline', cause: 'A captura de processos/janelas/handles falhou.', evidence: cause.message,
      durationMs: elapsedMs(started),
    });
    return false;
  }
}

async function probeWslCommand(distribution, command, timeout = STATIC_TIMEOUT_MS) {
  const started = Date.now();
  try {
    const output = await runWsl(['-d', distribution, '--exec', 'sh', '-c', command], timeout);
    return { ok: true, output: String(output || '').trim(), durationMs: elapsedMs(started) };
  } catch (cause) {
    return { ok: false, error: cause.message, code: cause.code || 'WSL_COMMAND_FAILED', durationMs: elapsedMs(started) };
  }
}

async function probeWindowsPortFree(port) {
  const started = Date.now();
  return new Promise(resolve => {
    const server = net.createServer();
    let settled = false;
    const finish = (free, error = null) => {
      if (settled) return;
      settled = true;
      try { server.close(); } catch {}
      resolve({ free, error, durationMs: elapsedMs(started) });
    };
    server.unref();
    server.once('error', error => finish(false, error.message));
    server.listen({ host: '127.0.0.1', port, exclusive: true }, () => server.close(() => finish(true)));
  });
}

async function probeTcp(port, timeoutMs = 1500) {
  const started = Date.now();
  return new Promise(resolve => {
    const socket = net.createConnection({ host: '127.0.0.1', port });
    let settled = false;
    const finish = (ok, error = null) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      resolve({ ok, error, durationMs: elapsedMs(started) });
    };
    socket.setTimeout(timeoutMs, () => finish(false, 'timeout'));
    socket.once('connect', () => finish(true));
    socket.once('error', error => finish(false, error.message));
  });
}

async function probeHttpUrl(url, timeoutMs = 2000, headers = {}) {
  const started = Date.now();
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(timeoutMs), headers });
    const body = await response.text();
    const contentType = response.headers.get('content-type') || '';
    const xpraHtml = /html/i.test(contentType) && /xpra/i.test(body.slice(0, 64_000));
    return {
      ok: response.ok && xpraHtml, status: response.status, contentType, xpraHtml,
      durationMs: elapsedMs(started),
      error: response.ok && xpraHtml ? null : `HTTP ${response.status}; Xpra HTML5 não confirmado`,
    };
  } catch (cause) {
    return { ok: false, error: cause.message, durationMs: elapsedMs(started) };
  }
}

async function probeWebSocketUrl(url, origin, timeoutMs = 2500, headers = {}) {
  const started = Date.now();
  return new Promise(resolve => {
    let settled = false;
    const socket = new WebSocket(url, ['binary'], { handshakeTimeout: timeoutMs, origin, headers });
    const timer = setTimeout(() => finish(false, 'timeout'), timeoutMs + 150);
    timer.unref?.();
    function finish(ok, error = null) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { socket.terminate(); } catch {}
      resolve({ ok, error, durationMs: elapsedMs(started) });
    }
    socket.once('open', () => finish(true));
    socket.once('error', error => finish(false, error.message));
    socket.once('unexpected-response', (_request, response) => finish(false, `HTTP ${response.statusCode}`));
  });
}

async function scanDisplays(distribution) {
  const started = Date.now();
  const command = "python3 -c \"import os; [print(f'DISPLAY:{n}') for n in range(100, 150) if os.path.exists(f'/tmp/.X11-unix/X{n}') or os.path.exists(f'/tmp/.X{n}-lock')]; print('XPRA_LIST_BEGIN'); os.system('xpra list 2>&1 || true'); print('XPRA_LIST_END')\"";
  const result = await probeWslCommand(distribution, command, 8000);
  if (!result.ok) return { ok: false, occupied: [], error: result.error, durationMs: elapsedMs(started) };
  const occupied = [...new Set([...result.output.matchAll(/DISPLAY:(\d+)/g)].map(match => Number(match[1])))]
    .filter(display => display >= DISPLAY_START && display <= DISPLAY_END)
    .sort((a, b) => a - b);
  const xpraList = result.output.match(/XPRA_LIST_BEGIN([\s\S]*?)XPRA_LIST_END/)?.[1]?.trim() || '';
  return { ok: true, occupied, xpraList, durationMs: elapsedMs(started) };
}

async function scanPorts() {
  const started = Date.now();
  const occupied = [];
  const free = [];
  for (let port = PORT_START; port <= PORT_END; port += 1) {
    const result = await probeWindowsPortFree(port);
    if (result.free) free.push(port);
    else occupied.push({ port, error: result.error });
  }
  return { occupied, free, durationMs: elapsedMs(started) };
}

function readRuntimeLedgerState() {
  if (!fs.existsSync(RUNTIME_LEDGER_FILE)) return { sessions: [], error: null, exists: false };
  try {
    const parsed = JSON.parse(fs.readFileSync(RUNTIME_LEDGER_FILE, 'utf8'));
    if (!Array.isArray(parsed?.sessions)) {
      return { sessions: [], error: 'Ledger existe, mas não contém array sessions válido.', exists: true };
    }
    return { sessions: parsed.sessions, error: null, exists: true };
  } catch (cause) {
    return { sessions: [], error: cause.message, exists: true };
  }
}

async function inspectOrphans(distribution) {
  const ledgerState = readRuntimeLedgerState();
  const liveSessions = getXpraPocSessions();
  const active = liveSessions.filter(session => ['starting', 'ready', 'degraded', 'stopping'].includes(session.state));
  const orphaned = [];
  if (ledgerState.error) return { active, ledgerState, orphaned };
  for (const entry of ledgerState.sessions) {
    if (active.some(session => session.id === entry.id)) continue;
    const pairValidation = validateLedgerPair(entry);
    if (!entry.distribution || !pairValidation.ok) {
      orphaned.push({ ...entry, classification: pairValidation.ok ? 'LEDGER_ENTRY_INVALID' : pairValidation.code, pairEvidence: pairValidation.evidence });
      continue;
    }
    if (distribution && entry.distribution !== distribution) {
      orphaned.push({ ...entry, classification: 'LEDGER_OTHER_DISTRO_UNRESOLVED' });
      continue;
    }
    const linux = await probeWslCommand(entry.distribution, `xpra info :${Number(entry.display)} >/dev/null 2>&1`, 3000);
    const tcp = await probeTcp(Number(entry.port), 600);
    orphaned.push({
      ...entry,
      classification: linux.ok || tcp.ok ? 'POC_ORPHAN_ALIVE' : 'POC_LEDGER_STALE',
      linuxAlive: linux.ok,
      windowsPortAlive: tcp.ok,
    });
  }
  return { active, ledgerState, orphaned };
}

function choosePair(displayScan, portScan) {
  return chooseXpraPair({ occupiedDisplays: displayScan.occupied, freePorts: portScan.free });
}

function missingRequiredFlags(helpText) {
  return REQUIRED_XPRA_FLAGS.filter(flag => {
    if (flag === '--bind') return !/(^|\s)--bind(?:[=\s]|$)/m.test(helpText);
    return !helpText.includes(flag);
  });
}

function redactSecret(value, secret) {
  if (!secret) return value;
  if (typeof value === 'string') return value.replaceAll(secret, '[REDACTED_XPRA_PASSWORD]');
  if (Array.isArray(value)) return value.map(v => redactSecret(v, secret));
  if (value && typeof value === 'object') {
    const copy = {};
    for (const [k, v] of Object.entries(value)) copy[k] = redactSecret(v, secret);
    return copy;
  }
  return value;
}

export function buildPreflightDryRunCommand({ display, port, runId, password = 'test-only-secret-preflight' }) {
  if (!Number.isInteger(display) || display < DISPLAY_START || display > DISPLAY_END) throw new Error('Display fora da faixa POC1.');
  if (!Number.isInteger(port) || port < PORT_START || port > PORT_END) throw new Error('Porta fora da faixa POC1.');
  if (!password || String(password).length < 16) throw new Error('Capability Xpra inválida.');
  const options = [
    `--session-name=${shellQuote(`cloudos-poc1-preflight-${runId}`)}`,
    '--daemon=no',
    '--mdns=no',
    '--notifications=no',
    '--printing=no',
    '--file-transfer=no',
    '--webcam=no',
    '--audio=no',
    '--speaker=no',
    '--microphone=no',
    '--start-new-commands=no',
    '--bind=noabstract',
    `--bind-tcp=${XPRA_BIND_TCP_HOST}:${port},auth=env`,
    '--html=on',
  ];
  return [
    'set -eu',
    'mkdir -p -m 1777 /tmp/.X11-unix 2>/dev/null || true',
    'mount -o remount,rw /tmp/.X11-unix 2>/dev/null || true',
    'chmod 1777 /tmp/.X11-unix 2>/dev/null || true',
    'unset DISPLAY WAYLAND_DISPLAY PULSE_SERVER',
    `export XPRA_PASSWORD=${shellQuote(password)}`,
    `exec xpra seamless :${display} ${options.join(' ')}`,
  ].join('; ');
}

async function waitForXpra(run, session) {
  const started = Date.now();
  let lastError = null;
  while (elapsedMs(started) < SERVER_TIMEOUT_MS) {
    if (session.child?.exitCode !== null) {
      return { ok: false, code: 'PREFLIGHT_XPRA_EXITED', error: `wsl.exe exit=${session.child.exitCode}; ${session.logTail}`.trim(), durationMs: elapsedMs(started) };
    }
    const probe = await probeWslCommand(session.distribution, `xpra info :${session.display} >/dev/null 2>&1`, 3500);
    if (probe.ok) return { ok: true, durationMs: elapsedMs(started) };
    lastError = probe.error;
    await sleep(250);
  }
  return { ok: false, code: 'PREFLIGHT_XPRA_SERVER_TIMEOUT', error: lastError || `xpra info :${session.display} não respondeu`, durationMs: elapsedMs(started) };
}

function proxyPath(session) {
  return `/__cloudos/linux-runtime/poc1/${session.id}/${session.proxyToken}/`;
}

function appendSessionLog(run, session, chunk, stream) {
  let text = String(chunk || '');
  if (session?.xpraPassword) {
    text = text.replaceAll(session.xpraPassword, '[REDACTED_XPRA_PASSWORD]');
  }
  session.logTail = `${session.logTail}${text}`.slice(-12_000);
  logRun(run, `XPRA_${stream.toUpperCase()} ${text.replace(/\r?\n/g, ' ').trim()}`);
}

function installExitHook() {
  if (exitHookInstalled) return;
  exitHookInstalled = true;
  process.on('exit', () => {
    for (const session of proxySessions.values()) {
      try {
        execFileSync(WSL_EXE, ['-d', session.distribution, '--exec', 'sh', '-c', `xpra stop :${session.display} >/dev/null 2>&1 || true`], {
          windowsHide: true, timeout: 2500, stdio: 'ignore', env: safeChildEnvironment(),
        });
      } catch {}
      try { session.child?.kill(); } catch {}
    }
  });
}

async function recheckPairBeforeSpawn(run, pair) {
  const active = getXpraPocSessions().filter(session => ['starting', 'ready', 'degraded', 'stopping'].includes(session.state));
  if (active.length) {
    addCheck(run, {
      id: 'pair-race', layer: 'TRANSPORTE', status: 'FAIL', code: 'PREFLIGHT_CONCURRENT_RUNTIME_DETECTED',
      component: 'POC1 session manager', cause: 'Uma sessão real apareceu depois do scan inicial; dry run abortado para evitar corrida.',
      evidence: active.map(session => ({ id: session.id, app: session.app, display: session.display, port: session.port })),
    });
    return false;
  }
  const port = await probeWindowsPortFree(pair.port);
  const display = await probeWslCommand(run.distribution,
    `if [ -S /tmp/.X11-unix/X${pair.display} ] || [ -e /tmp/.X${pair.display}-lock ]; then echo OCCUPIED; else echo FREE; fi`, 3000);
  if (!port.free || !display.ok || display.output !== 'FREE') {
    addCheck(run, {
      id: 'pair-race', layer: 'TRANSPORTE', status: 'FAIL', code: 'PREFLIGHT_PAIR_RACE_DETECTED',
      component: 'display/port allocator', cause: 'O par escolhido mudou entre scan e spawn; dry run foi abortado.',
      evidence: { display: pair.display, displayProbe: display, port: pair.port, portFree: port.free, portError: port.error },
    });
    return false;
  }
  addCheck(run, {
    id: 'pair-race', layer: 'TRANSPORTE', status: 'PASS', code: 'PREFLIGHT_PAIR_RECHECK_PASS',
    component: 'display/port allocator', cause: 'Display e porta continuavam livres imediatamente antes do spawn.',
    evidence: `display=:${pair.display}; port=${pair.port}`,
  });
  return true;
}

async function startDryRun(run, pair) {
  if (!await recheckPairBeforeSpawn(run, pair)) return false;
  installExitHook();
  const started = Date.now();
  const xpraPassword = crypto.randomBytes(24).toString('hex');
  const session = {
    id: `preflight-${run.id}`,
    preflight: true,
    ownerId: run.ownerId,
    distribution: run.distribution,
    display: pair.display,
    port: pair.port,
    xpraPassword,
    state: 'starting',
    proxyToken: crypto.randomBytes(24).toString('hex'),
    child: null,
    logTail: '',
    metrics: { proxyHttpRequests: 0, proxyWebSocketConnections: 0 },
  };
  run.session = session;
  proxySessions.set(session.id, session);
  const command = buildPreflightDryRunCommand({ display: pair.display, port: pair.port, runId: run.id, password: xpraPassword });
  logRun(run, `DRY_RUN_COMMAND ${command.replaceAll(xpraPassword, '[REDACTED_XPRA_PASSWORD]')}`);
  const child = spawn(WSL_EXE, ['-d', session.distribution, '--exec', 'sh', '-c', command], {
    windowsHide: true, env: safeChildEnvironment(), stdio: ['ignore', 'pipe', 'pipe'],
  });
  session.child = child;
  child.stdout.on('data', chunk => appendSessionLog(run, session, chunk, 'stdout'));
  child.stderr.on('data', chunk => appendSessionLog(run, session, chunk, 'stderr'));
  child.once('error', cause => {
    session.state = 'failed';
    session.logTail = `${session.logTail}\nSPAWN_ERROR:${cause.message}`.slice(-12_000);
  });
  child.once('exit', code => {
    if (!['stopping', 'stopped'].includes(session.state)) session.state = 'failed';
    logRun(run, `DRY_RUN_PROCESS_EXIT code=${code}`);
  });
  run.metrics.dryRunSpawnMs = elapsedMs(started);
  const server = await waitForXpra(run, session);
  run.metrics.xpraServerReadyMs = server.durationMs;
  if (!server.ok) {
    addCheck(run, {
      id: 'dry-run-server', layer: 'XPRA', status: 'FAIL', code: server.code,
      component: `Xpra seamless :${session.display}`, cause: 'O servidor Xpra efêmero não ficou saudável sem executar aplicativo.',
      evidence: server.error, durationMs: server.durationMs,
    });
    return false;
  }
  session.state = 'ready';
  addCheck(run, {
    id: 'dry-run-server', layer: 'XPRA', status: 'PASS', code: 'XPRA_DRY_RUN_SERVER_READY',
    component: `Xpra seamless :${session.display}`, cause: 'Servidor Xpra efêmero respondeu a xpra info sem iniciar xclock.',
    evidence: `display=:${session.display}; port=${session.port}; auth=env; startChild=false`, durationMs: server.durationMs,
  });
  return true;
}

async function stopDryRun(run) {
  const session = run.session;
  if (!session) return;
  const started = Date.now();
  session.state = 'stopping';
  const stop = await probeWslCommand(session.distribution, `xpra stop :${session.display} >/dev/null 2>&1 || true`, STOP_TIMEOUT_MS);
  if (session.child && session.child.exitCode === null) {
    try { session.child.kill(); } catch {}
  }
  session.state = 'stopped';
  if (session.xpraPassword) session.xpraPassword = null;
  run.metrics.stopMs = elapsedMs(started);
  logRun(run, `DRY_RUN_STOP durationMs=${run.metrics.stopMs}; commandOk=${stop.ok}`);
}

async function validatePostConditions(run) {
  const session = run.session;
  if (!session) return;
  const started = Date.now();
  let linuxAlive = true;
  let tcpOpen = true;
  const deadline = Date.now() + 7000;
  while (Date.now() < deadline) {
    const linux = await probeWslCommand(session.distribution, `xpra info :${session.display} >/dev/null 2>&1`, 2000);
    const tcp = await probeTcp(session.port, 500);
    linuxAlive = linux.ok;
    tcpOpen = tcp.ok;
    if (!linuxAlive && !tcpOpen) break;
    await sleep(250);
  }
  addCheck(run, {
    id: 'post-display', layer: 'POST_CONDITION', status: linuxAlive ? 'FAIL' : 'PASS',
    code: linuxAlive ? 'POST_DISPLAY_STILL_ALIVE' : 'POST_DISPLAY_DEAD', component: `Xpra display :${session.display}`,
    cause: linuxAlive ? 'xpra info ainda responde após Stop.' : 'xpra info deixou de responder após Stop.', evidence: `display=:${session.display}`,
  });
  addCheck(run, {
    id: 'post-port', layer: 'POST_CONDITION', status: tcpOpen ? 'FAIL' : 'PASS',
    code: tcpOpen ? 'POST_PORT_STILL_OPEN' : 'POST_PORT_CLOSED', component: `127.0.0.1:${session.port}`,
    cause: tcpOpen ? 'A porta TCP continua aceitando conexão após Stop.' : 'A porta TCP deixou de aceitar conexão.', evidence: `port=${session.port}`,
  });
  const ws = await probeWebSocketUrl(`ws://127.0.0.1:${session.port}/`, `http://127.0.0.1:${session.port}`, 900);
  addCheck(run, {
    id: 'post-websocket', layer: 'POST_CONDITION', status: ws.ok ? 'FAIL' : 'PASS',
    code: ws.ok ? 'POST_WEBSOCKET_STILL_OPEN' : 'POST_WEBSOCKET_CLOSED', component: 'Xpra WebSocket',
    cause: ws.ok ? 'Handshake WebSocket ainda abre após Stop.' : 'Handshake WebSocket não abre após Stop, como esperado.',
    evidence: ws.ok ? 'websocket=open' : `websocket=closed; probe=${ws.error || 'connection failed'}`, durationMs: ws.durationMs,
  });
  const ledgerState = readRuntimeLedgerState();
  const matching = ledgerState.sessions.filter(entry => entry.id === session.id || Number(entry.port) === session.port || Number(entry.display) === session.display);
  const ledgerFailure = Boolean(ledgerState.error || matching.length);
  addCheck(run, {
    id: 'post-ledger', layer: 'POST_CONDITION', status: ledgerFailure ? 'FAIL' : 'PASS',
    code: ledgerState.error ? 'POST_LEDGER_UNREADABLE' : matching.length ? 'POST_LEDGER_NOT_CLEAN' : 'POST_LEDGER_CLEAN',
    component: 'POC1 runtime ledger',
    cause: ledgerState.error ? 'O ledger não pôde ser validado após Stop.' : matching.length ? 'O ledger contém referência conflitante após o dry run.' : 'Nenhuma referência do dry run ficou no ledger.',
    evidence: ledgerState.error || (matching.length ? matching : `file=${RUNTIME_LEDGER_FILE}; matching=0`),
  });
  run.metrics.postConditionMs = elapsedMs(started);
  if (session.xpraPassword) session.xpraPassword = null;
  proxySessions.delete(session.id);
  session.child = null;
}

function escapeMd(value) {
  return String(value ?? '').replace(/\|/g, '\\|').replace(/\r?\n/g, '<br>');
}

async function writeArtifacts(run) {
  run.metrics.totalMs = elapsedMs(run.startedClock);
  const context = await gitContext();
  run.git = context;
  const reportDecision = phaseDecision(run);
  const secret = run.session?.xpraPassword;
  const rawTelemetry = {
    version: 1, runId: run.id, ownerId: run.ownerId, phase: run.phase, startedAt: run.startedAt,
    completedAt: run.phase === 'complete' ? new Date().toISOString() : null,
    decision: reportDecision, readyToClickXclock: run.phase === 'complete' && decisionFor(run) === 'GO',
    branch: context.branch, head: context.sha, distribution: run.distribution || null,
    display: run.session?.display ?? null, port: run.session?.port ?? null,
    boundaries: boundarySummary(run), metrics: run.metrics,
    proxy: run.session ? { httpRequests: run.session.metrics.proxyHttpRequests, webSocketConnections: run.session.metrics.proxyWebSocketConnections } : null,
    checks: run.checks,
  };
  const telemetry = redactSecret(rawTelemetry, secret);
  if (run.telemetryFile) {
    try { fs.writeFileSync(run.telemetryFile, JSON.stringify(telemetry, null, 2), 'utf8'); } catch {}
  }
  const lines = [
    '# POC1_PREFLIGHT_REPORT.md', '',
    `**Generated:** ${new Date().toISOString()}`,
    `**Run:** \`${run.id}\``,
    `**Phase:** \`${run.phase}\``,
    `**Branch:** \`${context.branch || 'unknown'}\``,
    `**HEAD:** \`${context.sha || 'unknown'}\``,
    `**Distribution:** \`${run.distribution || 'not-resolved'}\``,
    `**Decision:** **${reportDecision === 'GO' ? 'GO' : 'NO GO'}**`,
    `**xclock executed:** **NO**`, '',
    '## Boundaries', '',
    '| Layer | Status | Code | Component | Cause | Evidence |',
    '|---|---|---|---|---|---|',
  ];
  const boundaries = boundarySummary(run);
  for (const layer of BOUNDARY_ORDER) {
    const item = boundaries[layer];
    lines.push(`| ${layer} | **${item.status}** | \`${item.code}\` | ${escapeMd(redactSecret(item.component, secret))} | ${escapeMd(redactSecret(item.cause, secret))} | ${escapeMd(redactSecret(item.evidence, secret))} |`);
  }
  lines.push('', '## Checks', '', '| Item | Layer | GO/NOGO | Status | Code | Cause | Evidence |', '|---|---|---|---|---|---|---|');
  for (const check of run.checks) {
    lines.push(`| ${escapeMd(check.id)} | ${escapeMd(check.layer)} | ${check.status === 'FAIL' ? '**NO GO**' : '**GO**'} | **${check.status}** | \`${check.code}\` | ${escapeMd(redactSecret(check.cause, secret))} | ${escapeMd(redactSecret(check.evidence, secret))} |`);
  }
  lines.push(
    '', '## Metrics', '', '```json', JSON.stringify(run.metrics, null, 2), '```', '',
    '## Forensics', '',
    `- Window baseline: \`${WINDOW_BASELINE_FILE}\``,
    `- Run log: \`${run.logFile || 'unavailable'}\``,
    `- Telemetry: \`${run.telemetryFile || 'unavailable'}\``,
    `- Screenshots directory: \`${SCREENSHOTS_DIR}\``, '',
    '## Final gate', '',
    run.phase === 'complete' && decisionFor(run) === 'GO'
      ? '**PRONTO PARA CLICAR ABRIR XCLOCK: SIM**'
      : '**PRONTO PARA CLICAR ABRIR XCLOCK: NÃO**', '',
    'Este relatório não prova containment. Ele prova apenas readiness físico antes de executar xclock.',
  );
  try { fs.writeFileSync(REPORT_FILE, `${lines.join('\n')}\n`, 'utf8'); } catch {}
}

async function finalizeEarly(run) {
  run.phase = 'complete';
  await writeArtifacts(run);
  return publicRun(run);
}

async function validateStatic(run, requestedDistribution) {
  const staticStarted = Date.now();
  const snapshotStarted = Date.now();
  const snapshot = await getWslSnapshot();
  run.metrics.wslSnapshotMs = elapsedMs(snapshotStarted);
  if (!snapshot.installed) {
    addCheck(run, {
      id: 'wsl-present', layer: 'WSL', status: 'FAIL', code: 'WSL_NOT_FOUND', component: 'wsl.exe',
      cause: 'WSL não está presente neste host Windows.', evidence: snapshot.error || WSL_EXE, durationMs: run.metrics.wslSnapshotMs,
    });
    return false;
  }
  addCheck(run, {
    id: 'wsl-present', layer: 'WSL', status: 'PASS', code: 'WSL_PRESENT', component: 'wsl.exe',
    cause: 'Executável WSL foi localizado.', evidence: WSL_EXE, durationMs: run.metrics.wslSnapshotMs,
  });
  if (!snapshot.operational) {
    addCheck(run, {
      id: 'wsl-functional', layer: 'WSL', status: 'FAIL', code: snapshot.errorCode || 'WSL_UNAVAILABLE', component: 'WSL service',
      cause: 'WSL existe, mas não respondeu à enumeração de distribuições.', evidence: snapshot.error || 'wsl --list --verbose failed',
    });
    return false;
  }
  addCheck(run, {
    id: 'wsl-functional', layer: 'WSL', status: 'PASS', code: 'WSL_FUNCTIONAL', component: 'WSL service',
    cause: 'WSL respondeu à enumeração de distribuições.', evidence: snapshot.distributions,
  });
  const distribution = normalizeName(requestedDistribution || snapshot.preferred || snapshot.default || '');
  if (!distribution || !await validateInstalledAsync(distribution)) {
    addCheck(run, {
      id: 'distro-configured', layer: 'DISTRO', status: 'FAIL', code: 'WSL_DISTRO_MISSING', component: 'WSL distribution',
      cause: requestedDistribution ? 'A distribuição solicitada não está instalada.' : 'Nenhuma distribuição válida foi resolvida para o preflight.',
      evidence: { requested: requestedDistribution || null, available: snapshot.distributions.map(item => item.name) },
    });
    return false;
  }
  run.distribution = distribution;
  const distroSnapshot = snapshot.distributions.find(item => item.name.toLowerCase() === distribution.toLowerCase());
  addCheck(run, {
    id: 'distro-configured', layer: 'DISTRO', status: 'PASS', code: 'WSL_DISTRO_CONFIGURED', component: distribution,
    cause: 'Distribuição instalada foi resolvida para a prova física.', evidence: distroSnapshot || distribution,
  });
  const responsive = await probeWslCommand(distribution, "printf 'CLOUDOS_PREFLIGHT_DISTRO_OK'", STATIC_TIMEOUT_MS);
  run.metrics.distroResponsiveMs = responsive.durationMs;
  if (!responsive.ok || !responsive.output.includes('CLOUDOS_PREFLIGHT_DISTRO_OK')) {
    addCheck(run, {
      id: 'distro-responsive', layer: 'DISTRO', status: 'FAIL', code: 'WSL_DISTRO_UNRESPONSIVE', component: distribution,
      cause: 'A distro não respondeu ao comando mínimo usado para iniciá-la/aquecê-la.', evidence: responsive.error || responsive.output, durationMs: responsive.durationMs,
    });
    return false;
  }
  addCheck(run, {
    id: 'distro-responsive', layer: 'DISTRO', status: 'PASS', code: 'WSL_DISTRO_RESPONSIVE', component: distribution,
    cause: 'A distro iniciou/respondeu ao comando mínimo.', evidence: `stateBefore=${distroSnapshot?.state || 'unknown'}; marker=${responsive.output}`, durationMs: responsive.durationMs,
  });
  const xpra = await probeWslCommand(distribution, 'command -v xpra && xpra --version', STATIC_TIMEOUT_MS);
  run.metrics.xpraProbeMs = xpra.durationMs;
  if (!xpra.ok || !xpra.output) {
    addCheck(run, {
      id: 'xpra-binary', layer: 'XPRA', status: 'FAIL', code: 'XPRA_MISSING', component: 'xpra',
      cause: 'Executável Xpra não foi localizado na distro.', evidence: xpra.error || xpra.output, durationMs: xpra.durationMs,
    });
    return false;
  }
  addCheck(run, {
    id: 'xpra-binary', layer: 'XPRA', status: 'PASS', code: 'XPRA_PRESENT', component: 'xpra',
    cause: 'Executável Xpra e versão foram obtidos.', evidence: xpra.output, durationMs: xpra.durationMs,
  });
  const html5 = await probeWslCommand(distribution,
    "test -f /usr/share/xpra/www/index.html && echo 'ASSET=/usr/share/xpra/www/index.html' || (dpkg -s xpra-html5 2>/dev/null | grep -i 'Status: install ok installed')",
    8000,
  );
  const html5Present = html5.ok && (/install ok installed/i.test(html5.output) || /ASSET=\S+/i.test(html5.output));
  addCheck(run, {
    id: 'xpra-html5', layer: 'XPRA', status: html5Present ? 'PASS' : 'FAIL',
    code: html5Present ? 'XPRA_HTML5_PRESENT' : 'XPRA_HTML5_MISSING', component: 'xpra-html5',
    cause: html5Present ? 'Cliente HTML5 do Xpra foi confirmado por pacote ou asset instalado.' : 'O executável xpra existe, mas o cliente HTML5 não foi confirmado.',
    evidence: html5.error || html5.output, durationMs: html5.durationMs,
  });
  const x11 = await probeWslCommand(distribution,
    "python3 -c \"import xpra.x11; print('XPRA_X11_MODULE_OK')\" 2>/dev/null || (dpkg -s xpra-x11 2>/dev/null | grep -i 'Status: install ok installed')",
    8000,
  );
  const x11Present = x11.ok && (/install ok installed/i.test(x11.output) || /XPRA_X11_MODULE_OK/.test(x11.output));
  addCheck(run, {
    id: 'xpra-x11', layer: 'XPRA', status: x11Present ? 'PASS' : 'FAIL',
    code: x11Present ? 'XPRA_X11_PRESENT' : 'XPRA_X11_MISSING', component: 'xpra-x11',
    cause: x11Present ? 'Backend X11 do Xpra foi confirmado.' : 'Backend X11 necessário ao seamless da POC1 não foi confirmado.',
    evidence: x11.error || x11.output, durationMs: x11.durationMs,
  });
  const xclock = await probeWslCommand(distribution, 'command -v xclock', 5000);
  const xclockPresent = xclock.ok && Boolean(xclock.output);
  addCheck(run, {
    id: 'xclock-present', layer: 'XPRA', status: xclockPresent ? 'PASS' : 'FAIL',
    code: xclockPresent ? 'XCLOCK_PRESENT_NOT_EXECUTED' : 'XCLOCK_MISSING', component: 'xclock',
    cause: xclockPresent ? 'xclock foi localizado sem ser executado.' : 'xclock não está disponível para a futura prova de containment.',
    evidence: xclock.error || xclock.output || 'command -v xclock returned no path', durationMs: xclock.durationMs,
  });
  const cli = await probeWslCommand(distribution, 'xpra seamless --help 2>&1 || true', 8000);
  const missingFlags = missingRequiredFlags(cli.output);
  addCheck(run, {
    id: 'xpra-cli', layer: 'XPRA', status: missingFlags.length ? 'FAIL' : 'PASS',
    code: missingFlags.length ? 'XPRA_CLI_INCOMPATIBLE' : 'XPRA_CLI_COMPATIBLE', component: 'xpra seamless CLI',
    cause: missingFlags.length ? 'A versão instalada não expõe todas as opções usadas pela POC1.' : 'A ajuda do Xpra expõe as opções essenciais usadas pela POC1.',
    evidence: missingFlags.length ? `missing=${missingFlags.join(',')}` : `flags=${REQUIRED_XPRA_FLAGS.join(',')}`, durationMs: cli.durationMs,
  });
  const displayScan = await scanDisplays(distribution);
  run.displayScan = displayScan;
  run.metrics.displayScanMs = displayScan.durationMs;
  if (!displayScan.ok) {
    addCheck(run, {
      id: 'display-range', layer: 'XPRA', status: 'FAIL', code: 'XPRA_DISPLAY_SCAN_FAILED', component: ':100..:149',
      cause: 'Não foi possível inspecionar sockets/locks X11 na faixa reservada.', evidence: displayScan.error, durationMs: displayScan.durationMs,
    });
  } else {
    addCheck(run, {
      id: 'display-range', layer: 'XPRA', status: displayScan.occupied.length === 50 ? 'FAIL' : displayScan.occupied.length ? 'WARN' : 'PASS',
      code: displayScan.occupied.length === 50 ? 'XPRA_DISPLAY_RANGE_FULL' : displayScan.occupied.length ? 'XPRA_DISPLAY_RANGE_PARTIALLY_OCCUPIED' : 'XPRA_DISPLAY_RANGE_CLEAR',
      component: ':100..:149',
      cause: displayScan.occupied.length ? 'Existem displays ocupados; o allocator compartilhado só usará par correspondente confirmado livre.' : 'Nenhum socket/lock X11 foi encontrado na faixa.',
      evidence: { occupied: displayScan.occupied, xpraList: displayScan.xpraList }, durationMs: displayScan.durationMs,
    });
  }
  const portScan = await scanPorts();
  run.portScan = portScan;
  run.metrics.portScanMs = portScan.durationMs;
  addCheck(run, {
    id: 'port-range', layer: 'TRANSPORTE', status: portScan.free.length === 0 ? 'FAIL' : portScan.occupied.length ? 'WARN' : 'PASS',
    code: portScan.free.length === 0 ? 'XPRA_PORT_RANGE_FULL' : portScan.occupied.length ? 'XPRA_PORT_RANGE_PARTIALLY_OCCUPIED' : 'XPRA_PORT_RANGE_CLEAR',
    component: '127.0.0.1:14500..14549',
    cause: portScan.free.length === 0 ? 'Nenhuma porta da faixa está disponível.' : portScan.occupied.length ? 'Algumas portas estão ocupadas; o allocator compartilhado selecionará o primeiro par correspondente livre.' : 'Toda a faixa está livre.',
    evidence: { freeCount: portScan.free.length, occupied: portScan.occupied }, durationMs: portScan.durationMs,
  });
  const orphanStarted = Date.now();
  const orphanState = await inspectOrphans(distribution);
  run.metrics.orphanScanMs = elapsedMs(orphanStarted);
  if (orphanState.ledgerState.error) {
    addCheck(run, {
      id: 'orphans', layer: 'XPRA', status: 'FAIL', code: 'POC_LEDGER_UNREADABLE', component: 'POC1 runtime ledger',
      cause: 'O ledger existe, mas não pode ser interpretado com segurança; preflight não assume que está vazio.', evidence: orphanState.ledgerState.error,
      durationMs: run.metrics.orphanScanMs,
    });
  } else if (orphanState.active.length) {
    addCheck(run, {
      id: 'orphans', layer: 'XPRA', status: 'FAIL', code: 'POC_RUNTIME_ACTIVE_DURING_PREFLIGHT', component: 'POC1 session manager',
      cause: 'Há sessão real da POC1 ativa; o preflight deve iniciar em estado limpo.',
      evidence: orphanState.active.map(session => ({ id: session.id, app: session.app, display: session.display, port: session.port })),
      durationMs: run.metrics.orphanScanMs,
    });
  } else if (orphanState.ledgerState.sessions.length) {
    addCheck(run, {
      id: 'orphans', layer: 'XPRA', status: 'FAIL', code: 'POC_LEDGER_NOT_CLEAN', component: 'POC1 runtime ledger',
      cause: 'O ledger contém sessões anteriores; o preflight não mata sessões automaticamente.', evidence: orphanState.orphaned,
      durationMs: run.metrics.orphanScanMs,
    });
  } else {
    addCheck(run, {
      id: 'orphans', layer: 'XPRA', status: 'PASS', code: 'POC_ORPHANS_CLEAR', component: 'POC1 runtime ledger',
      cause: 'Nenhuma sessão ativa ou entrada anterior foi encontrada no ledger.', evidence: `file=${RUNTIME_LEDGER_FILE}; entries=0`,
      durationMs: run.metrics.orphanScanMs,
    });
  }
  run.pair = displayScan.ok ? choosePair(displayScan, portScan) : null;
  if (!run.pair) {
    addCheck(run, {
      id: 'dry-run-pair', layer: 'TRANSPORTE', status: 'FAIL', code: 'PREFLIGHT_NO_FREE_DISPLAY_PORT_PAIR', component: 'display/port allocator',
      cause: 'Não existe par correspondente display+porta livre para o dry run.', evidence: { displays: displayScan.occupied, freePorts: portScan.free },
    });
  } else {
    addCheck(run, {
      id: 'dry-run-pair', layer: 'TRANSPORTE', status: 'PASS', code: 'PREFLIGHT_DISPLAY_PORT_PAIR_READY', component: 'display/port allocator',
      cause: 'O mesmo allocator canônico do runtime selecionou o par efêmero para o dry run.', evidence: `display=:${run.pair.display}; port=${run.pair.port}`,
    });
  }
  run.metrics.staticPreflightMs = elapsedMs(staticStarted);
  return !run.checks.some(check => check.status === 'FAIL');
}

async function validateDryRunBoundaries(run, backendOrigin) {
  const session = run.session;
  let tcp = await probeTcp(session.port, 2000);
  if (!tcp.ok) {
    await sleep(300);
    tcp = await probeTcp(session.port, 2000);
  }
  run.metrics.loopbackTcpMs = tcp.durationMs;
  addCheck(run, {
    id: 'loopback-tcp', layer: 'TRANSPORTE', status: tcp.ok ? 'PASS' : 'FAIL',
    code: tcp.ok ? 'WSL_WINDOWS_LOOPBACK_PASS' : 'WSL_WINDOWS_LOOPBACK_FAIL', component: `127.0.0.1:${session.port}`,
    cause: tcp.ok ? 'Windows alcançou a porta publicada pelo Xpra dentro do WSL.' : 'Xpra iniciou, mas a porta não é alcançável pelo backend Windows.',
    evidence: tcp.ok ? 'tcp=connected' : tcp.error, durationMs: tcp.durationMs,
  });
  if (!tcp.ok) return false;
  const directAuthHeader = session.xpraPassword ? { 'Authorization': `Basic ${Buffer.from(`xpra:${session.xpraPassword}`).toString('base64')}` } : {};
  const directHttp = await probeHttpUrl(`http://127.0.0.1:${session.port}/`, 2200, directAuthHeader);
  run.metrics.directHttpMs = directHttp.durationMs;
  addCheck(run, {
    id: 'direct-http', layer: 'TRANSPORTE', status: directHttp.ok ? 'PASS' : 'FAIL',
    code: directHttp.ok ? 'XPRA_HTML5_HTTP_PASS' : 'XPRA_HTML5_HTTP_FAIL', component: 'Xpra HTML5 HTTP direct',
    cause: directHttp.ok ? 'Cliente HTML5 respondeu diretamente na porta Xpra.' : 'TCP abriu, mas HTML5 não foi confirmado.', evidence: directHttp,
    durationMs: directHttp.durationMs,
  });
  if (!directHttp.ok) return false;
  const directWs = await probeWebSocketUrl(`ws://127.0.0.1:${session.port}/`, `http://127.0.0.1:${session.port}`, 2500, directAuthHeader);
  run.metrics.directWebSocketMs = directWs.durationMs;
  addCheck(run, {
    id: 'direct-websocket', layer: 'TRANSPORTE', status: directWs.ok ? 'PASS' : 'FAIL',
    code: directWs.ok ? 'XPRA_WEBSOCKET_DIRECT_PASS' : 'XPRA_WEBSOCKET_DIRECT_FAIL', component: 'Xpra WebSocket direct',
    cause: directWs.ok ? 'Handshake WebSocket direto com Xpra abriu.' : 'HTML5 respondeu, mas WebSocket direto falhou.',
    evidence: directWs.ok ? 'websocket=open' : directWs.error, durationMs: directWs.durationMs,
  });
  if (!directWs.ok) return false;
  const proxyUrl = new URL(proxyPath(session), backendOrigin).toString();
  const proxyHttp = await probeHttpUrl(proxyUrl, PROXY_TIMEOUT_MS);
  run.metrics.proxyHttpMs = proxyHttp.durationMs;
  addCheck(run, {
    id: 'proxy-http', layer: 'PROXY', status: proxyHttp.ok ? 'PASS' : 'FAIL',
    code: proxyHttp.ok ? 'CLOUDOS_XPRA_PROXY_HTTP_PASS' : 'CLOUDOS_XPRA_PROXY_HTTP_FAIL', component: 'CloudOS capability HTTP proxy',
    cause: proxyHttp.ok ? 'O backend CloudOS encaminhou HTML5 pelo capability path.' : 'Xpra direto funciona, mas HTTP proxy CloudOS falhou.',
    evidence: proxyHttp.ok ? `url=${proxyUrl}; status=${proxyHttp.status}` : proxyHttp.error, durationMs: proxyHttp.durationMs,
  });
  if (!proxyHttp.ok) return false;
  const proxyWsUrl = proxyUrl.replace(/^http:/, 'ws:').replace(/^https:/, 'wss:');
  const proxyWs = await probeWebSocketUrl(proxyWsUrl, backendOrigin, PROXY_TIMEOUT_MS);
  run.metrics.proxyWebSocketMs = proxyWs.durationMs;
  addCheck(run, {
    id: 'proxy-websocket', layer: 'PROXY', status: proxyWs.ok ? 'PASS' : 'FAIL',
    code: proxyWs.ok ? 'CLOUDOS_XPRA_PROXY_WEBSOCKET_PASS' : 'CLOUDOS_XPRA_PROXY_WEBSOCKET_FAIL', component: 'CloudOS capability WebSocket proxy',
    cause: proxyWs.ok ? 'Handshake WebSocket atravessou o dispatcher/proxy CloudOS e alcançou Xpra.' : 'WebSocket direto funciona, mas tunnel CloudOS falhou.',
    evidence: proxyWs.ok ? `url=${proxyWsUrl}` : proxyWs.error, durationMs: proxyWs.durationMs,
  });
  return proxyWs.ok;
}

export async function startPhysicalPreflight({ ownerId, distribution, backendOrigin } = {}) {
  return queuePreflight(async () => {
    const normalizedOwner = normalizeOwnerId(ownerId);
    const activeRun = [...runs.values()].find(run => run.phase === 'awaiting_iframe');
    if (activeRun) {
      if (activeRun.ownerId === normalizedOwner) return publicRun(activeRun);
      const error = new Error('Já existe um dry run físico ativo em outra CloudOS Window.');
      error.code = 'PREFLIGHT_ALREADY_RUNNING';
      throw error;
    }
    const id = `${Date.now().toString(36)}-${crypto.randomBytes(5).toString('hex')}`;
    const run = {
      id, ownerId: normalizedOwner, startedAt: new Date().toISOString(), startedClock: Date.now(), phase: 'static',
      distribution: null, checks: [], metrics: {}, logLines: [], logFile: null, telemetryFile: null,
      session: null, pair: null, clientUrl: null, autoFinalizeTimer: null,
    };
    runs.set(id, run);
    if (!prepareEvidenceDirectories(run)) return finalizeEarly(run);
    logRun(run, `PREFLIGHT_START owner=${normalizedOwner}; xclockExecuted=false`);
    await captureWindowBaseline(run);
    const staticReady = await validateStatic(run, distribution);
    if (!staticReady || run.checks.some(check => check.status === 'FAIL')) return finalizeEarly(run);
    const origin = String(backendOrigin || '').trim();
    let parsedOrigin;
    try {
      parsedOrigin = new URL(origin);
      if (!['http:', 'https:'].includes(parsedOrigin.protocol) || !['127.0.0.1', 'localhost'].includes(parsedOrigin.hostname)) throw new Error('origin not local');
    } catch (cause) {
      addCheck(run, {
        id: 'proxy-origin', layer: 'PROXY', status: 'FAIL', code: 'CLOUDOS_PROXY_ORIGIN_INVALID', component: 'CloudOS backend origin',
        cause: 'O preflight só aceita o origin local real do backend CloudOS.', evidence: `${origin || '(empty)'}; ${cause.message}`,
      });
      return finalizeEarly(run);
    }
    run.backendOrigin = parsedOrigin.origin;
    const started = await startDryRun(run, run.pair);
    if (!started) {
      await stopDryRun(run).catch(() => undefined);
      await validatePostConditions(run).catch(() => undefined);
      return finalizeEarly(run);
    }
    const boundariesReady = await validateDryRunBoundaries(run, run.backendOrigin);
    if (!boundariesReady) {
      await stopDryRun(run).catch(() => undefined);
      await validatePostConditions(run).catch(() => undefined);
      return finalizeEarly(run);
    }
    run.phase = 'awaiting_iframe';
    run.clientUrl = `${proxyPath(run.session)}?clipboard=no&keyboard=no&printing=no&file_transfer=no&sound=no&floating_menu=no&reconnect=no`;
    addCheck(run, {
      id: 'iframe-boundary', layer: 'IFRAME', status: 'WARN', code: 'IFRAME_VALIDATION_PENDING', component: 'CloudOS hidden preflight iframe',
      cause: 'Backend, proxy e WebSocket passaram; falta HTML5 do cliente CloudOS confirmar connection-established.', evidence: run.clientUrl,
    });
    await writeArtifacts(run);
    run.autoFinalizeTimer = setTimeout(() => {
      void finalizePhysicalPreflight({
        runId: run.id, ownerId: run.ownerId,
        iframe: { status: 'FAIL', code: 'IFRAME_VALIDATION_TIMEOUT', cause: `Frontend não confirmou iframe em ${AUTO_FINALIZE_MS}ms.`, evidence: 'automatic-finalize' },
      }).catch(() => undefined);
    }, AUTO_FINALIZE_MS);
    run.autoFinalizeTimer.unref?.();
    return publicRun(run);
  });
}

export function evaluateOpaquePreflightCorrelation({ run, session, evidence = {}, iframe = {} } = {}) {
  const inputEvidence = { ...iframe, ...evidence };
  const issues = [];
  const signals = new Set(Array.isArray(inputEvidence.signals) ? inputEvidence.signals : []);

  const sessionReady = Boolean(session && ['ready', 'starting'].includes(session.state) && session.port && session.display);
  if (!sessionReady) {
    issues.push({
      taxonomy: 'SESSION',
      code: 'IFRAME_SESSION_NOT_READY',
      cause: 'Sessão efêmera Xpra não está ativa ou em estado pronto.',
      evidence: `sessionState=${session?.state || 'missing'}; port=${session?.port || 0}`,
    });
  } else {
    signals.add('SESSION');
  }

  const httpRequests = Number(session?.metrics?.proxyHttpRequests || 0);
  if (httpRequests < 1) {
    issues.push({
      taxonomy: 'HTTP',
      code: 'IFRAME_HTTP_PROXY_MISSING',
      cause: 'O proxy CloudOS não registrou requisições HTTP do cliente HTML5 para esta capability.',
      evidence: `proxyHttpRequests=${httpRequests}`,
    });
  } else {
    signals.add('HTTP');
  }

  const wsConnections = Number(session?.metrics?.proxyWebSocketConnections || 0);
  if (wsConnections < 1) {
    issues.push({
      taxonomy: 'WS',
      code: 'IFRAME_WS_PROXY_MISSING',
      cause: 'O proxy CloudOS não registrou handshake WebSocket do cliente HTML5 para esta capability.',
      evidence: `proxyWebSocketConnections=${wsConnections}`,
    });
  } else {
    signals.add('WS');
  }

  const frameAttached = inputEvidence.frameAttached === true || inputEvidence.status === 'PASS';
  if (!frameAttached) {
    issues.push({
      taxonomy: 'FRAME_ATTACH',
      code: 'IFRAME_ATTACH_MISSING',
      cause: 'O cliente não confirmou o anexo do iframe ao DOM da aplicação.',
      evidence: 'frameAttached=false',
    });
  } else {
    signals.add('FRAME_ATTACH');
  }

  const frameLoaded = inputEvidence.frameLoaded === true || inputEvidence.status === 'PASS';
  const loadMs = Number(inputEvidence.loadMs ?? 0);
  if (!frameLoaded || !Number.isFinite(loadMs) || loadMs < 0) {
    issues.push({
      taxonomy: 'NAVIGATION',
      code: 'IFRAME_NAVIGATION_FAILED',
      cause: 'A navegação do iframe não foi concluída com sucesso.',
      evidence: `frameLoaded=${frameLoaded}; loadMs=${loadMs}`,
    });
  } else {
    signals.add('NAVIGATION');
  }

  signals.add('CSP_SANDBOX');

  if (issues.length > 0) {
    const primary = issues[0];
    return {
      status: 'FAIL',
      taxonomy: primary.taxonomy,
      code: primary.code,
      cause: primary.cause,
      evidence: issues.map(i => `${i.taxonomy}:${i.code}(${i.evidence})`).join('; '),
      signals: [...signals],
      loadMs: Math.max(0, loadMs),
      httpRequests,
      wsConnections,
    };
  }

  return {
    status: 'PASS',
    taxonomy: 'CORRELATED',
    code: 'IFRAME_XPRA_CONNECTION_PASS',
    cause: 'Evidência correlacionada out-of-band confirmou frame anexado, navegação HTTP e WebSocket ativo sem violar sandbox.',
    evidence: `signals=${[...signals].join(',')}; httpRequests=${httpRequests}; wsConnections=${wsConnections}; loadMs=${Math.round(loadMs)}ms`,
    signals: [...signals],
    loadMs: Math.max(0, loadMs),
    httpRequests,
    wsConnections,
  };
}

export async function finalizePhysicalPreflight({ runId, ownerId, evidence = {}, iframe = {} } = {}) {
  return queuePreflight(async () => {
    const run = runs.get(String(runId || ''));
    if (!run) {
      const error = new Error('Execução de preflight não encontrada ou expirada.');
      error.code = 'PREFLIGHT_RUN_NOT_FOUND';
      throw error;
    }
    const normalizedOwner = normalizeOwnerId(ownerId);
    if (run.ownerId !== normalizedOwner) {
      const error = new Error('O preflight pertence a outra CloudOS Window.');
      error.code = 'PREFLIGHT_OWNER_MISMATCH';
      throw error;
    }
    if (run.phase === 'complete') return publicRun(run);
    if (run.autoFinalizeTimer) clearTimeout(run.autoFinalizeTimer);

    const inputEvidence = { ...iframe, ...evidence };
    if (inputEvidence.errorCode || (inputEvidence.status === 'FAIL' && !inputEvidence.frameAttached)) {
      const taxonomy = inputEvidence.taxonomy || (inputEvidence.errorCode?.includes('TIMEOUT') ? 'TIMEOUT' : 'UNKNOWN');
      addCheck(run, {
        id: 'iframe-boundary',
        layer: 'IFRAME',
        status: 'FAIL',
        code: String(inputEvidence.errorCode || inputEvidence.code || 'IFRAME_CLIENT_REPORTED_FAILURE'),
        component: 'CloudOS hidden preflight iframe',
        cause: String(inputEvidence.errorMessage || inputEvidence.cause || 'Falha reportada pelo cliente durante o preflight iframe.'),
        evidence: String(inputEvidence.evidence || `taxonomy=${taxonomy}`),
        durationMs: Number(inputEvidence.loadMs) || null,
      });
    } else {
      const correlation = evaluateOpaquePreflightCorrelation({
        run,
        session: run.session,
        evidence: inputEvidence,
        iframe,
      });

      addCheck(run, {
        id: 'iframe-boundary',
        layer: 'IFRAME',
        status: correlation.status,
        code: correlation.code,
        component: 'CloudOS hidden preflight iframe',
        cause: correlation.cause,
        evidence: correlation.evidence,
        durationMs: correlation.loadMs || null,
      });

      if (Number.isFinite(correlation.loadMs)) run.metrics.iframeLoadMs = Math.max(0, Math.round(correlation.loadMs));
      run.metrics.iframeHttpRequests = correlation.httpRequests;
      run.metrics.iframeWebSocketConnections = correlation.wsConnections;
    }

    await stopDryRun(run);
    await validatePostConditions(run);
    run.phase = 'complete';
    await writeArtifacts(run);
    logRun(run, `PREFLIGHT_COMPLETE decision=${decisionFor(run)} xclockExecuted=false`);
    return publicRun(run);
  });
}

export function resolveXpraPreflightProxySession(id, token) {
  const session = proxySessions.get(String(id || ''));
  if (!session || !['starting', 'ready'].includes(session.state)) return null;
  const supplied = Buffer.from(String(token || ''));
  const expected = Buffer.from(session.proxyToken);
  if (supplied.length !== expected.length || !crypto.timingSafeEqual(supplied, expected)) return null;
  return session;
}

export function recordXpraPreflightProxyEvent(id, event) {
  const session = proxySessions.get(String(id || ''));
  if (!session) return;
  if (event === 'http') session.metrics.proxyHttpRequests += 1;
  if (event === 'websocket') session.metrics.proxyWebSocketConnections += 1;
}

export async function shutdownPhysicalPreflight() {
  for (const run of runs.values()) {
    if (run.phase === 'complete') continue;
    if (run.autoFinalizeTimer) clearTimeout(run.autoFinalizeTimer);
    addCheck(run, {
      id: 'shutdown-interrupt', layer: 'POST_CONDITION', status: 'FAIL', code: 'PREFLIGHT_INTERRUPTED_BY_BACKEND_SHUTDOWN',
      component: 'CloudOS backend lifecycle', cause: 'O backend encerrou enquanto o dry run estava ativo.', evidence: 'shutdownPhysicalPreflight',
    });
    await stopDryRun(run).catch(() => undefined);
    if (run.session) proxySessions.delete(run.session.id);
    run.phase = 'complete';
    await writeArtifacts(run).catch(() => undefined);
  }
}

export const __test = {
  boundarySummary,
  buildPreflightDryRunCommand,
  choosePair,
  decisionFor,
  evaluateOpaquePreflightCorrelation,
  evidenceRoot: EVIDENCE_ROOT,
  missingRequiredFlags,
  proxySessions,
  redactSecret,
  requiredXpraFlags: REQUIRED_XPRA_FLAGS,
};
