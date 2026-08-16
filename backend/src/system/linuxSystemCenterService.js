import { createWslCoreRpcSession } from './wslCoreRpcSession.js';
import { WSL_CORE_PROTECTION, WSL_CORE_PROTOCOL } from '../terminal/wslCoreAdapter.js';
import { getPreferred, listInstalled } from '../wsl/distroService.js';

const MAX_CONCURRENT = 2;
const AUDIT_LIMIT = 100;
const REQUEST_TIMEOUT_MS = 5000;

function enabled(env = process.env) {
  return env.CLOUDOS_WSL_CORE_FOUNDATION === '1' && env.CLOUDOS_WSL_CORE_SYSTEM_CENTER === '1';
}

function fallbackAllowed(env = process.env) {
  return env.CLOUDOS_WSL_CORE_SYSTEM_CENTER_FALLBACK === '1';
}

function sanitizeCode(error) {
  const code = typeof error?.code === 'string' ? error.code : 'SYSTEM_CENTER_UNAVAILABLE';
  return /^[A-Z0-9_]{2,64}$/.test(code) ? code : 'SYSTEM_CENTER_UNAVAILABLE';
}

function safeError(error) {
  const code = sanitizeCode(error);
  const known = {
    FEATURE_DISABLED: 'Linux System Center is disabled.',
    CORE_PATH_INVALID: 'Linux System Center core path is invalid.',
    DISTRO_INVALID: 'Linux distribution is invalid.',
    DISTRO_NOT_WSL2: 'Linux System Center requires WSL2.',
    REQUEST_TIMEOUT: 'Linux System Center request timed out.',
    CHANNEL_CLOSED: 'Linux System Center channel closed.',
    PROCESS_NOT_FOUND: 'The Linux process no longer exists.',
    PROCESS_PROTECTED: 'The Linux process is protected.',
    PROCESS_DENIED: 'The Linux process action is not allowed.',
    PID_REUSED: 'The Linux process identity changed.',
    SIGNAL_RATE_LIMIT: 'Linux process signal rate limit reached.',
    CGROUP_CONTROL_DISABLED: 'Cgroup control is disabled.',
    CGROUP_CONTROL_UNAVAILABLE: 'Cgroup control is unavailable.',
    CGROUP_POLICY_INVALID: 'Cgroup policy is invalid.',
    CGROUP_PROCESS_OUTSIDE_CORE: 'The process is outside the CloudOS cgroup.',
  };
  return { code, message: known[code] || 'Linux System Center operation failed.' };
}

class LinuxSystemCenterService {
  constructor() {
    this.session = null;
    this.connecting = null;
    this.active = 0;
    this.waiters = [];
    this.audit = [];
  }

  configuration() {
    const active = enabled();
    const path = process.env.CLOUDOS_WSL_CORE_LINUX_PATH || '';
    let distribution = null;
    let wsl2 = false;
    if (active) {
      try {
        distribution = getPreferred();
        const entry = listInstalled().find(item => item.name.toLowerCase() === String(distribution || '').toLowerCase());
        wsl2 = entry?.version === 2;
      } catch {}
    }
    return {
      enabled: active,
      fallbackAllowed: fallbackAllowed(),
      distribution,
      wsl2,
      corePathConfigured: path.startsWith('/'),
      protocol: WSL_CORE_PROTOCOL,
      protection: WSL_CORE_PROTECTION,
      cgroupControlRequested: process.env.CLOUDOS_WSL_CORE_CGROUP_CONTROL === '1',
    };
  }

  async status() {
    const config = this.configuration();
    if (!config.enabled) return { ...config, available: false, source: 'linux-real', reason: 'FEATURE_DISABLED' };
    if (!config.distribution) return { ...config, available: false, source: 'linux-real', reason: 'DISTRO_NOT_FOUND' };
    if (!config.wsl2) return { ...config, available: false, source: 'linux-real', reason: 'DISTRO_NOT_WSL2' };
    if (!config.corePathConfigured) return { ...config, available: false, source: 'linux-real', reason: 'CORE_PATH_INVALID' };
    try {
      const session = await this.#ensureSession();
      const health = await session.request('health', null, 4000);
      return { ...config, available: true, source: 'linux-real', mode: 'wsl-core-v2', distro: health?.distro || null, activeSessions: health?.activeSessions ?? 0 };
    } catch (error) {
      return { ...config, available: false, source: 'linux-real', reason: sanitizeCode(error) };
    }
  }

  async request(method, params = null, timeoutMs = REQUEST_TIMEOUT_MS) {
    if (!enabled()) throw Object.assign(new Error('disabled'), { code: 'FEATURE_DISABLED' });
    await this.#acquire();
    try {
      const session = await this.#ensureSession();
      return await session.request(method, params, Math.max(500, Math.min(8000, timeoutMs)));
    } catch (error) {
      if (['CHANNEL_CLOSED', 'CHANNEL_TIMEOUT', 'REQUEST_TIMEOUT'].includes(sanitizeCode(error))) await this.#resetSession();
      throw error;
    } finally {
      this.#release();
    }
  }

  recordAudit(entry) {
    const safe = {
      at: new Date().toISOString(),
      userId: Number.isInteger(entry?.userId) ? entry.userId : null,
      action: String(entry?.action || '').slice(0, 48),
      pid: Number.isInteger(entry?.pid) ? entry.pid : null,
      signal: String(entry?.signal || '').slice(0, 16),
      result: String(entry?.result || '').slice(0, 48),
    };
    this.audit.push(safe);
    if (this.audit.length > AUDIT_LIMIT) this.audit.splice(0, this.audit.length - AUDIT_LIMIT);
  }

  getAudit() { return this.audit.map(item => ({ ...item })); }
  safeError(error) { return safeError(error); }

  async dispose() { await this.#resetSession(); }

  async #ensureSession() {
    if (this.session) return this.session;
    if (this.connecting) return await this.connecting;
    const config = this.configuration();
    if (!config.distribution) throw Object.assign(new Error('distribution missing'), { code: 'DISTRO_NOT_FOUND' });
    if (!config.wsl2) throw Object.assign(new Error('not wsl2'), { code: 'DISTRO_NOT_WSL2' });
    const linuxCorePath = process.env.CLOUDOS_WSL_CORE_LINUX_PATH || '';
    this.connecting = createWslCoreRpcSession({
      distribution: config.distribution,
      linuxCorePath,
      cgroupControl: process.env.CLOUDOS_WSL_CORE_CGROUP_CONTROL === '1',
    }).then(session => {
      this.session = session;
      return session;
    }).finally(() => { this.connecting = null; });
    return await this.connecting;
  }

  async #resetSession() {
    const session = this.session;
    this.session = null;
    if (session) { try { await session.close(); } catch {} }
  }

  async #acquire() {
    if (this.active < MAX_CONCURRENT) { this.active += 1; return; }
    await new Promise(resolve => this.waiters.push(resolve));
    this.active += 1;
  }
  #release() {
    this.active = Math.max(0, this.active - 1);
    this.waiters.shift()?.();
  }
}

export const linuxSystemCenterService = new LinuxSystemCenterService();
export { enabled as linuxSystemCenterEnabled, fallbackAllowed as linuxSystemCenterFallbackAllowed, safeError as sanitizeLinuxSystemCenterError };
