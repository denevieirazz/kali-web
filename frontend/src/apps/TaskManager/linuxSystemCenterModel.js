export const LINUX_SYSTEM_CENTER_POLL_MS = 3000;
export const LINUX_SYSTEM_CENTER_MAX_ROWS = 100;

function record(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function has(value, key) {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function finite(value, fallback = 0, minimum = 0) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric < minimum) return fallback;
  return numeric;
}

function integer(value, fallback = 0, minimum = 0) {
  const numeric = Number(value);
  if (!Number.isSafeInteger(numeric) || numeric < minimum) return fallback;
  return numeric;
}

function text(value, fallback = '', limit = 4096) {
  if (typeof value !== 'string') return fallback;
  return value.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, ' ').slice(0, limit);
}

function stringList(value, limit = 128, fieldLimit = 1024) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, limit).filter(item => typeof item === 'string').map(item => text(item, '', fieldLimit));
}

function booleanMap(value) {
  const source = record(value);
  const output = {};
  for (const [key, item] of Object.entries(source).slice(0, 128)) {
    if (typeof item === 'boolean') output[text(key, '', 128)] = item;
  }
  return output;
}

function safeRecord(value) {
  const source = record(value);
  const output = {};
  for (const [key, item] of Object.entries(source).slice(0, 128)) {
    const safeKey = text(key, '', 128);
    if (!safeKey) continue;
    if (typeof item === 'string') output[safeKey] = text(item, '', 4096);
    else if (typeof item === 'number' && Number.isFinite(item)) output[safeKey] = item;
    else if (typeof item === 'boolean' || item === null) output[safeKey] = item;
    else if (Array.isArray(item)) output[safeKey] = item.slice(0, 128).filter(v => ['string','number','boolean'].includes(typeof v));
    else if (item && typeof item === 'object') output[safeKey] = safeRecord(item);
  }
  return output;
}

export function normalizeLinuxFilters(value = {}) {
  return {
    query: String(value.query || '').slice(0, 128),
    state: String(value.state || '').slice(0, 16),
    user: String(value.user || '').slice(0, 64),
    sortBy: ['pid','cpu','memory','name','user'].includes(value.sortBy) ? value.sortBy : 'pid',
    sortDir: value.sortDir === 'desc' ? 'desc' : 'asc',
    page: Math.max(1, Number.parseInt(value.page, 10) || 1),
    pageSize: Math.max(1, Math.min(LINUX_SYSTEM_CENTER_MAX_ROWS, Number.parseInt(value.pageSize, 10) || 50)),
  };
}

export function normalizeLinuxStatus(value) {
  const source = record(value);
  return {
    enabled: source.enabled === true,
    available: source.available === true,
    fallbackAllowed: source.fallbackAllowed === true,
    distribution: typeof source.distribution === 'string' ? text(source.distribution, '', 80) : null,
    wsl2: source.wsl2 === true,
    corePathConfigured: source.corePathConfigured === true,
    protocol: integer(source.protocol, 0, 0),
    protection: text(source.protection, '', 64),
    source: 'linux-real',
    mode: source.mode === 'wsl-core-v2' ? 'wsl-core-v2' : undefined,
    reason: typeof source.reason === 'string' ? text(source.reason, '', 96) : undefined,
  };
}

const REQUIRED_PROCESS_FIELDS = ['ppid','state','uid','user','name','cpuPercent','rssBytes','virtualBytes','threads','startTimeTicks','protected'];

export function normalizeLinuxProcessInfo(value) {
  const source = record(value);
  const pid = integer(source.pid, 0, 1);
  if (pid <= 0) return null;

  const startTimeTicks = integer(source.startTimeTicks, 0, 0);
  const uid = integer(source.uid, -1, -1);
  const name = text(source.name, `[pid ${pid}]`, 256) || `[pid ${pid}]`;
  const user = text(source.user, '', 128) || (uid >= 0 ? `UID ${uid}` : 'desconhecido');
  const identityIncomplete = startTimeTicks <= 0;
  const protectedProcess = source.protected === true || identityIncomplete;
  const protectedReason = text(source.protectedReason, '', 128) || (identityIncomplete ? 'identity-incomplete' : '');

  return {
    pid,
    ppid: integer(source.ppid, 0, 0),
    state: text(source.state, '?', 16) || '?',
    uid,
    user,
    name,
    executable: text(source.executable, '', 1024),
    args: stringList(source.args, 64, 256),
    cpuPercent: finite(source.cpuPercent, 0, 0),
    rssBytes: finite(source.rssBytes, 0, 0),
    virtualBytes: finite(source.virtualBytes, 0, 0),
    threads: integer(source.threads, 0, 0),
    startTimeTicks,
    uptimeSeconds: finite(source.uptimeSeconds, 0, 0),
    cgroup: text(source.cgroup, '', 1024),
    protected: protectedProcess,
    protectedReason,
  };
}

export function normalizeLinuxProcessPage(value) {
  const source = record(value);
  const input = Array.isArray(source.processes) ? source.processes : [];
  const processes = [];
  let droppedRows = 0;
  let partialRows = 0;

  for (const item of input.slice(0, LINUX_SYSTEM_CENTER_MAX_ROWS)) {
    const raw = record(item);
    const normalized = normalizeLinuxProcessInfo(raw);
    if (!normalized) {
      droppedRows += 1;
      continue;
    }
    if (REQUIRED_PROCESS_FIELDS.some(field => !has(raw, field))) partialRows += 1;
    processes.push(normalized);
  }

  const declaredTotal = integer(source.total, processes.length, 0);
  return {
    source: 'linux-real',
    mode: 'wsl-core-v2',
    processes,
    total: Math.max(declaredTotal, processes.length),
    page: integer(source.page, 1, 1),
    pageSize: Math.max(1, Math.min(LINUX_SYSTEM_CENTER_MAX_ROWS, integer(source.pageSize, Math.max(1, processes.length), 1))),
    truncated: source.truncated === true,
    sampledAt: text(source.sampledAt, '', 96),
    droppedRows,
    partialRows,
  };
}

export function normalizeCgroupCapabilities(value) {
  const source = record(value);
  const hasCapabilities = Object.keys(source).length > 0;
  const readOnly = typeof source.readOnly === 'boolean' ? source.readOnly : true;
  const controlAvailable = source.controlAvailable === true && readOnly === false;
  return {
    version: integer(source.version, 0, 0),
    mounted: source.mounted === true,
    currentPath: text(source.currentPath, '', 1024),
    controllersAvailable: stringList(source.controllersAvailable, 64, 64),
    controllersDelegated: stringList(source.controllersDelegated, 64, 64),
    writableFiles: booleanMap(source.writableFiles),
    controllerSupport: booleanMap(source.controllerSupport),
    systemd: source.systemd === true,
    controlEnabled: source.controlEnabled === true,
    controlAvailable,
    readOnly,
    reason: text(source.reason, hasCapabilities ? '' : 'metrics-incomplete', 128),
  };
}

const REQUIRED_METRIC_FIELDS = [
  'uptimeSeconds','load1','load5','load15','memoryTotalBytes','memoryAvailableBytes',
  'processCount','cgroupV2','cgroupCapabilities','resourceMetrics',
];

export function normalizeLinuxMetrics(value) {
  const source = record(value);
  const missingFields = REQUIRED_METRIC_FIELDS.filter(field => !has(source, field));
  return {
    source: 'linux-real',
    mode: 'wsl-core-v2',
    uptimeSeconds: finite(source.uptimeSeconds, 0, 0),
    load1: finite(source.load1, 0, 0),
    load5: finite(source.load5, 0, 0),
    load15: finite(source.load15, 0, 0),
    memoryTotalBytes: finite(source.memoryTotalBytes, 0, 0),
    memoryAvailableBytes: finite(source.memoryAvailableBytes, 0, 0),
    processCount: integer(source.processCount, 0, 0),
    cgroupV2: source.cgroupV2 === true,
    cgroupPath: text(source.cgroupPath, '', 1024),
    cgroupMetrics: safeRecord(source.cgroupMetrics),
    cgroupCapabilities: normalizeCgroupCapabilities(source.cgroupCapabilities),
    resourceMetrics: safeRecord(source.resourceMetrics),
    partial: missingFields.length > 0,
    missingFields,
  };
}

export function normalizeCgroupSnapshot(value) {
  const source = record(value);
  return {
    source: 'linux-real',
    capabilities: normalizeCgroupCapabilities(source.capabilities),
    metrics: safeRecord(source.metrics),
  };
}

export class LatestRequestGate {
  constructor() { this.sequence = 0; this.controller = null; this.disposed = false; }
  next() { this.controller?.abort(); this.controller = new AbortController(); const sequence = ++this.sequence; return { sequence, signal: this.controller.signal, current: () => !this.disposed && sequence === this.sequence }; }
  dispose() { this.disposed = true; this.sequence += 1; this.controller?.abort(); this.controller = null; }
}

export function safeSystemCenterError(error) {
  const message = typeof error?.message === 'string' ? error.message : 'Linux System Center indisponível.';
  return message.replace(/(?:secret|token|password|nonce|port|pid)\s*[:=]\s*\S+/gi, '[redacted]').slice(0, 240);
}

export function processMatches(process, { query = '', state = '', user = '' } = {}) {
  const needle = String(query).trim().toLowerCase();
  if (needle && !`${process.name || ''} ${process.executable || ''} ${(process.args || []).join(' ')} ${process.pid}`.toLowerCase().includes(needle)) return false;
  if (state && String(process.state).toLowerCase() !== String(state).toLowerCase()) return false;
  if (user && String(process.user).toLowerCase() !== String(user).toLowerCase() && String(process.uid) !== String(user)) return false;
  return true;
}

export function sortLinuxProcesses(processes, sortBy = 'pid', sortDir = 'asc') {
  const direction = sortDir === 'desc' ? -1 : 1;
  const key = process => sortBy === 'cpu' ? Number(process.cpuPercent || 0) : sortBy === 'memory' ? Number(process.rssBytes || 0) : sortBy === 'name' ? String(process.name || '').toLowerCase() : sortBy === 'user' ? String(process.user || '').toLowerCase() : Number(process.pid || 0);
  return [...processes].sort((left,right) => { const a=key(left),b=key(right); return a < b ? -direction : a > b ? direction : Number(left.pid||0)-Number(right.pid||0); });
}
