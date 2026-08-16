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

export function normalizeLinuxFilters(value?: Partial<NormalizedLinuxFilters> & Record<string, unknown>): NormalizedLinuxFilters;

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
