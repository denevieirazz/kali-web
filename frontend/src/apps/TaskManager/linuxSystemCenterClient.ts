import { apiClient } from '../../services/apiClient';

export type SystemCenterSource = 'linux-real' | 'cloudos-virtual' | 'host-windows';
export type LinuxSignal = 'SIGINT' | 'SIGTERM' | 'SIGKILL';

export interface LinuxProcessInfo {
  pid: number; ppid: number; state: string; uid: number; user: string; name: string;
  executable?: string; args?: string[]; cpuPercent: number; rssBytes: number; virtualBytes: number;
  threads: number; startTimeTicks: number; uptimeSeconds?: number; cgroup?: string;
  protected: boolean; protectedReason?: string;
}
export interface LinuxProcessPage { source: 'linux-real'; mode: 'wsl-core-v2'; processes: LinuxProcessInfo[]; total: number; page: number; pageSize: number; truncated: boolean; sampledAt: string; }
export interface LinuxStatus { enabled: boolean; available: boolean; fallbackAllowed: boolean; distribution: string | null; wsl2: boolean; protocol: number; protection: string; source: 'linux-real'; mode?: 'wsl-core-v2'; reason?: string; }
export interface CgroupCapabilities { version: number; mounted: boolean; currentPath: string; controllersAvailable: string[]; controllersDelegated: string[]; writableFiles: Record<string, boolean>; controllerSupport: Record<string, boolean>; systemd: boolean; controlEnabled: boolean; controlAvailable: boolean; readOnly: boolean; reason?: string; }
export interface LinuxMetrics { source: 'linux-real'; mode: 'wsl-core-v2'; uptimeSeconds: number; load1: number; load5: number; load15: number; memoryTotalBytes: number; memoryAvailableBytes: number; processCount: number; cgroupV2: boolean; cgroupPath: string; cgroupMetrics?: Record<string, unknown>; cgroupCapabilities: CgroupCapabilities; resourceMetrics: Record<string, unknown>; }
export interface CgroupPolicy { memoryMaxBytes?: number; memoryHighBytes?: number; cpuPercent?: number; pidsMax?: number; }
export interface CgroupAssignment { id: string; pid: number; originalPath: string; cgroupPath: string; policy: CgroupPolicy; appliedAt: string; }

const qs = (params: Record<string, string | number | undefined>) => {
  const value = new URLSearchParams();
  for (const [key, field] of Object.entries(params)) if (field !== undefined && field !== '') value.set(key, String(field));
  const text = value.toString(); return text ? `?${text}` : '';
};

export const linuxSystemCenterClient = {
  status: (signal?: AbortSignal) => apiClient<LinuxStatus>('/api/system/linux/status', { signal, timeoutMs: 6000 }),
  processes: (params: { page?: number; pageSize?: number; query?: string; state?: string; user?: string; sortBy?: string; sortDir?: string }, signal?: AbortSignal) => apiClient<LinuxProcessPage>(`/api/system/linux/processes${qs(params)}`, { signal, timeoutMs: 6000 }),
  metrics: (signal?: AbortSignal) => apiClient<LinuxMetrics>('/api/system/linux/metrics', { signal, timeoutMs: 6000 }),
  cgroups: (signal?: AbortSignal) => apiClient<{ source: 'linux-real'; capabilities: CgroupCapabilities; metrics: Record<string, unknown> }>('/api/system/linux/cgroups/capabilities', { signal, timeoutMs: 6000 }),
  signal: (process: LinuxProcessInfo, signalName: LinuxSignal) => apiClient<{ accepted: boolean }> (`/api/system/linux/processes/${process.pid}/signal`, { method: 'POST', body: JSON.stringify({ confirmed: true, startTimeTicks: process.startTimeTicks, signal: signalName }), timeoutMs: 6000 }),
  applyPolicy: (process: LinuxProcessInfo, policy: CgroupPolicy) => apiClient<{ applied: true; assignment: CgroupAssignment }>('/api/system/linux/cgroups/policy', { method: 'POST', body: JSON.stringify({ confirmed: true, pid: process.pid, startTimeTicks: process.startTimeTicks, policy }), timeoutMs: 6000 }),
  clearPolicy: (id: string) => apiClient<{ cleared: true }>(`/api/system/linux/cgroups/assignments/${encodeURIComponent(id)}`, { method: 'DELETE', body: JSON.stringify({ confirmed: true }), timeoutMs: 6000 }),
  hostMetrics: (signal?: AbortSignal) => apiClient<any>('/api/system/metrics', { signal, timeoutMs: 6000 }),
};
