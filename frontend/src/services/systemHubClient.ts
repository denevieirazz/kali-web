import { apiClient } from './apiClient';
import { nativeHostBridge } from './nativeHostBridge';

export interface WslDistribution {
  name: string;
  version: number | null;
  state: string;
  isDefault?: boolean;
}

export interface HostCapabilities {
  host: {
    platform: string;
    release: string;
    architecture: string;
    hostname: string;
    windows: boolean;
  };
  wsl: {
    installed: boolean;
    operational: boolean;
    errorCode: string | null;
    error: string | null;
    wslVersion: string | null;
    kernelVersion: string | null;
    wslgVersion: string | null;
    distributions: WslDistribution[];
    default: string | null;
    preferred: string | null;
  };
  integration: {
    terminal: boolean;
    windowsApps: boolean;
    linuxGuiApps: boolean;
    windowMode: 'native-external' | 'native-managed' | 'streamed';
    nativeHostActive: boolean;
    managedNativeWindows: boolean;
    embeddedNativeWindows: boolean;
    nativeHostRequired: boolean;
    nativeWindowContainment?: 'anchored-overlay' | 'external';
  };
  limitations: string[];
}

export interface DistroCatalogItem {
  id: string;
  name: string;
}

export interface NativeApp {
  id: string;
  name: string;
  source: 'windows' | 'wsl';
  distribution: string | null;
  icon: string;
  windowMode: 'native-external' | 'native-managed' | 'streamed';
  availability?: 'contained' | 'fallback' | 'blocked';
  fallbackAppId?: string | null;
  blockedReason?: string | null;
}

export interface NativeLaunchResult {
  name: string;
  source: string;
  distribution: string | null;
  pid: number;
  windowMode: string;
  managed?: boolean;
  managementReason?: string | null;
  sessionId?: string | null;
  contained?: boolean;
  containmentMode?: 'anchored-overlay' | 'external';
}

export interface SystemOperation {
  id: string;
  type: string;
  target: string | null;
  status: 'queued' | 'running' | 'cancelling' | 'completed' | 'failed' | 'cancelled';
  progress: number;
  step: string;
  message: string;
  output: string[];
  createdAt: string;
  updatedAt: string;
  finishedAt: string | null;
  exitCode: number | null;
  errorCode: string | null;
}

export const systemHubClient = {
  capabilities: async () => {
    const capabilities = await apiClient<HostCapabilities>('/api/host/capabilities');
    if (!nativeHostBridge.available) return capabilities;
    try {
      await nativeHostBridge.connect();
      const host = await nativeHostBridge.getHostState();
      return {
        ...capabilities,
        integration: {
          ...capabilities.integration,
          nativeHostActive: host.nativeHost,
          managedNativeWindows: host.managedWindows,
          embeddedNativeWindows: host.embeddedNativeWindows,
          nativeWindowContainment: host.nativeWindowContainment,
          windowMode: host.managedWindows ? 'native-managed' as const : capabilities.integration.windowMode
        }
      };
    } catch {
      return capabilities;
    }
  },
  distributions: () => apiClient<{
    available: boolean;
    installed: boolean;
    operational: boolean;
    errorCode: string | null;
    error: string | null;
    default: string | null;
    preferred: string | null;
    distributions: WslDistribution[];
  }>('/api/wsl/distributions'),
  catalog: () => apiClient<{ distributions: DistroCatalogItem[] }>('/api/wsl/catalog', { timeoutMs: 25000 }),
  install: (distribution: string, webDownload: boolean) => apiClient<{ operationId: string; operation: SystemOperation }>('/api/wsl/installations', {
    method: 'POST',
    body: JSON.stringify({ distribution, webDownload }),
    timeoutMs: 30000
  }),
  updateWsl: () => apiClient<{ operationId: string; operation: SystemOperation }>('/api/wsl/update', { method: 'POST' }),
  startDistro: (name: string) => apiClient(`/api/wsl/distributions/${encodeURIComponent(name)}/start`, { method: 'POST' }),
  stopDistro: (name: string) => apiClient(`/api/wsl/distributions/${encodeURIComponent(name)}/stop`, { method: 'POST', timeoutMs: 35000 }),
  setDefaultDistro: (name: string) => apiClient(`/api/wsl/distributions/${encodeURIComponent(name)}/set-default`, { method: 'POST', timeoutMs: 35000 }),
  setDistroVersion: (name: string, version: 1 | 2) => apiClient<{ operationId: string; operation: SystemOperation }>(`/api/wsl/distributions/${encodeURIComponent(name)}/set-version`, {
    method: 'POST',
    body: JSON.stringify({ version })
  }),
  operations: () => apiClient<{ operations: SystemOperation[] }>('/api/operations'),
  cancelOperation: (id: string) => apiClient<SystemOperation>(`/api/operations/${encodeURIComponent(id)}/cancel`, { method: 'POST' }),
  apps: (refresh = false) => apiClient<{ apps: NativeApp[] }>(`/api/apps${refresh ? '?refresh=true' : ''}`, { timeoutMs: 30000 }),
  launchApp: async (id: string): Promise<NativeLaunchResult> => nativeHostBridge.available
    ? nativeHostBridge.connect().then(() => nativeHostBridge.launchApp(id))
    : apiClient<NativeLaunchResult>(`/api/apps/${encodeURIComponent(id)}/launch`, { method: 'POST' })
};
