export const LINUX_SYSTEM_CENTER_POLL_MS: number;
export const LINUX_SYSTEM_CENTER_MAX_ROWS: number;

export interface NormalizedLinuxFilters {
  query: string;
  state: string;
  user: string;
  sortBy: 'pid' | 'cpu' | 'memory' | 'name' | 'user';
  sortDir: 'asc' | 'desc';
  page: number;
  pageSize: number;
}

export interface NormalizedLinuxStatus {
  enabled: boolean;
  available: boolean;
  fallbackAllowed: boolean;
  distribution: string | null;
  wsl2: boolean;
  corePathConfigured: boolean;
  protocol: number;
  protection: string;
  source: 'linux-real';
  mode?: 'wsl-core-v2';
  reason?: string;
}

export interface NormalizedLinuxProcessInfo {
  pid: number;
  ppid: number;
  state: string;
  uid: number;
  user: string;
  name: string;
  executable: string;
  args: string[];
  cpuPercent: number;
  rssBytes: number;
  virtualBytes: number;
  threads: number;
  startTimeTicks: number;
  uptimeSeconds: number;
  cgroup: string;
  protected: boolean;
  protectedReason: string;
}

export interface NormalizedLinuxProcessPage {
  source: 'linux-real';
  mode: 'wsl-core-v2';
  processes: NormalizedLinuxProcessInfo[];
  total: number;
  page: number;
  pageSize: number;
  truncated: boolean;
  sampledAt: string;
  droppedRows: number;
  partialRows: number;
}

export interface NormalizedCgroupCapabilities {
  version: number;
  mounted: boolean;
  currentPath: string;
  controllersAvailable: string[];
  controllersDelegated: string[];
  writableFiles: Record<string, boolean>;
  controllerSupport: Record<string, boolean>;
  systemd: boolean;
  controlEnabled: boolean;
  controlAvailable: boolean;
  readOnly: boolean;
  reason: string;
}

export interface NormalizedLinuxMetrics {
  source: 'linux-real';
  mode: 'wsl-core-v2';
  uptimeSeconds: number;
  load1: number;
  load5: number;
  load15: number;
  memoryTotalBytes: number;
  memoryAvailableBytes: number;
  processCount: number;
  cgroupV2: boolean;
  cgroupPath: string;
  cgroupMetrics: Record<string, unknown>;
  cgroupCapabilities: NormalizedCgroupCapabilities;
  resourceMetrics: Record<string, unknown>;
  partial: boolean;
  missingFields: string[];
}

export interface NormalizedCgroupSnapshot {
  source: 'linux-real';
  capabilities: NormalizedCgroupCapabilities;
  metrics: Record<string, unknown>;
}

export function normalizeLinuxFilters(value?: Partial<NormalizedLinuxFilters> & Record<string, unknown>): NormalizedLinuxFilters;
export function normalizeLinuxStatus(value: unknown): NormalizedLinuxStatus;
export function normalizeLinuxProcessInfo(value: unknown): NormalizedLinuxProcessInfo | null;
export function normalizeLinuxProcessPage(value: unknown): NormalizedLinuxProcessPage;
export function normalizeCgroupCapabilities(value: unknown): NormalizedCgroupCapabilities;
export function normalizeLinuxMetrics(value: unknown): NormalizedLinuxMetrics;
export function normalizeCgroupSnapshot(value: unknown): NormalizedCgroupSnapshot;

export class LatestRequestGate {
  next(): { sequence: number; signal: AbortSignal; current: () => boolean };
  dispose(): void;
}

export function safeSystemCenterError(error: unknown): string;

export function processMatches(process: Record<string, unknown>, filters?: { query?: string; state?: string; user?: string }): boolean;

export function sortLinuxProcesses<T extends { pid?: number; cpuPercent?: number; rssBytes?: number; name?: string; user?: string }>(
  processes: T[],
  sortBy?: 'pid' | 'cpu' | 'memory' | 'name' | 'user',
  sortDir?: 'asc' | 'desc',
): T[];
