import { apiClient } from '../../services/apiClient';
import {
  normalizeCgroupSnapshot,
  normalizeLinuxMetrics,
  normalizeLinuxProcessPage,
  normalizeLinuxStatus,
  type NormalizedCgroupCapabilities,
  type NormalizedLinuxMetrics,
  type NormalizedLinuxProcessInfo,
  type NormalizedLinuxProcessPage,
  type NormalizedLinuxStatus,
} from './linuxSystemCenterModel.js';

export type SystemCenterSource = 'linux-real' | 'cloudos-virtual' | 'host-windows';
export type LinuxSignal = 'SIGINT' | 'SIGTERM' | 'SIGKILL';
export type LinuxProcessInfo = NormalizedLinuxProcessInfo;
export type LinuxProcessPage = NormalizedLinuxProcessPage;
export type LinuxStatus = NormalizedLinuxStatus;
export type CgroupCapabilities = NormalizedCgroupCapabilities;
export type LinuxMetrics = NormalizedLinuxMetrics;

export interface CgroupPolicy { memoryMaxBytes?: number; memoryHighBytes?: number; cpuPercent?: number; pidsMax?: number; }
export interface CgroupAssignment { id: string; pid: number; originalPath: string; cgroupPath: string; policy: CgroupPolicy; appliedAt: string; }

const qs = (params: Record<string, string | number | undefined>) => {
  const value = new URLSearchParams();
  for (const [key, field] of Object.entries(params)) if (field !== undefined && field !== '') value.set(key, String(field));
  const text = value.toString(); return text ? `?${text}` : '';
};

export const linuxSystemCenterClient = {
  status: async (signal?: AbortSignal): Promise<LinuxStatus> =>
    normalizeLinuxStatus(await apiClient<unknown>('/api/system/linux/status', { signal, timeoutMs: 6000 })),

  processes: async (
    params: { page?: number; pageSize?: number; query?: string; state?: string; user?: string; sortBy?: string; sortDir?: string },
    signal?: AbortSignal,
  ): Promise<LinuxProcessPage> => normalizeLinuxProcessPage(
    await apiClient<unknown>(`/api/system/linux/processes${qs(params)}`, { signal, timeoutMs: 6000 }),
  ),

  metrics: async (signal?: AbortSignal): Promise<LinuxMetrics> =>
    normalizeLinuxMetrics(await apiClient<unknown>('/api/system/linux/metrics', { signal, timeoutMs: 6000 })),

  cgroups: async (signal?: AbortSignal) => normalizeCgroupSnapshot(
    await apiClient<unknown>('/api/system/linux/cgroups/capabilities', { signal, timeoutMs: 6000 }),
  ),

  signal: (process: LinuxProcessInfo, signalName: LinuxSignal) => apiClient<{ accepted: boolean }>(
    `/api/system/linux/processes/${process.pid}/signal`,
    { method: 'POST', body: JSON.stringify({ confirmed: true, startTimeTicks: process.startTimeTicks, signal: signalName }), timeoutMs: 6000 },
  ),

  applyPolicy: (process: LinuxProcessInfo, policy: CgroupPolicy) => apiClient<{ applied: true; assignment: CgroupAssignment }>(
    '/api/system/linux/cgroups/policy',
    { method: 'POST', body: JSON.stringify({ confirmed: true, pid: process.pid, startTimeTicks: process.startTimeTicks, policy }), timeoutMs: 6000 },
  ),

  clearPolicy: (id: string) => apiClient<{ cleared: true }>(
    `/api/system/linux/cgroups/assignments/${encodeURIComponent(id)}`,
    { method: 'DELETE', body: JSON.stringify({ confirmed: true }), timeoutMs: 6000 },
  ),

  hostMetrics: (signal?: AbortSignal) => apiClient<any>('/api/system/metrics', { signal, timeoutMs: 6000 }),
};
