export const SYSTEM_CENTER_HISTORY_LIMIT: number;
export function clampPercent(value: unknown): number;
export function memoryPercent(resources: unknown): number;
export function diskPercent(resources: unknown): number;
export function appendHistory(history: number[], value: unknown, limit?: number): number[];
export function isSystemProcess(process: unknown): boolean;
export function healthSummary(input?: { processes?: any[]; services?: any[]; drivers?: any[]; resources?: any }): {
  status: 'healthy' | 'attention';
  alerts: string[];
  failedServices: number;
  failedDrivers: number;
  suspended: number;
  memory: number;
  cpu: number;
};
export function sortProcesses(processes: any[], field?: 'memory' | 'cpu' | 'pid' | 'name'): any[];
