export const LINUX_SYSTEM_CENTER_POLL_MS = 3000;
export const LINUX_SYSTEM_CENTER_MAX_ROWS = 100;

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
