// ============================================
// App Registry - Dynamic System Discovery
// ============================================
import { lazy } from 'react';
import { create } from 'zustand';
import type { AppDefinition } from '../types';

// Static definitions of the *Components* (The "Binaries" on disk)
// We still need these imports for the bundle, but they will be mapped dynamically
const components: Record<string, ReturnType<typeof lazy>> = {
  'terminal': lazy(() => import('../apps/Terminal/Terminal')),
  'notepad': lazy(() => import('../apps/Notepad/Notepad')),
  'calculator': lazy(() => import('../apps/Calculator/Calculator')),
  'file-explorer': lazy(() => import('../apps/FileExplorer/FileExplorer')),
  'settings': lazy(() => import('../apps/Settings/Settings')),
  'task-manager': lazy(() => import('../apps/TaskManager/TaskManager')),
  'browser': lazy(() => import('../apps/Browser/Browser')),
  'windows-installer': lazy(() => import('../apps/WindowsInstaller/WindowsInstaller')),
  'regedit': lazy(() => import('../apps/Regedit/Regedit')),
  'obsidian-code': lazy(() => import('../apps/ObsidianCode/ObsidianCode')),
  'obs-record': lazy(() => import('../apps/ObsRecord/ObsRecord')),
  'media-player': lazy(() => import('../apps/MediaPlayer/MediaPlayer')),
  'obsidian-store': lazy(() => import('../apps/ObsidianStore/ObsidianStore')),
  'sdk-app-runner': lazy(() => import('../apps/SdkAppRunner/SdkAppRunner')),
  'cloudos-terminal': lazy(() => import('../apps/CloudOSTerminal/CloudOSTerminal')),
  'cloudos-files': lazy(() => import('../apps/CloudOSFiles/CloudOSFiles')),
  'workflow-workspace': lazy(() => import('../apps/WorkflowWorkspace/WorkflowWorkspace')),
  'system-monitor': lazy(() => import('../apps/SystemMonitor/SystemMonitor')),
  'install-linux': lazy(() => import('../apps/InstallLinux/InstallLinux')),
  'linux-runtime-poc': lazy(() => import('../apps/LinuxRuntimePoc/LinuxRuntimePoc')),
  'linux-app-runner': lazy(() => import('../apps/LinuxAppWindow/LinuxAppWindow')),
  'env-doctor': lazy(() => import('../apps/EnvDoctor/EnvDoctor')),
  'kali-tool-center': lazy(() => import('../apps/KaliToolCenter/KaliToolCenter')),
  'network-inspector': lazy(() => import('../apps/NetworkInspector/NetworkInspector')),
  'wifi-inspector': lazy(() => import('../apps/WifiInspector/WifiInspector')),
  'network-shield': lazy(() => import('../apps/NetworkShield/NetworkShield')),
  'dns-inspector': lazy(() => import('../apps/DnsInspector/DnsInspector')),
  'office-viewer': lazy(() => import('../apps/OfficeViewer/OfficeViewer')),
  'taskbar': lazy(() => import('../components/Taskbar/Taskbar')),
  'desktop': lazy(() => import('../components/Desktop/Desktop')),
};

// O novo Motor de Renderização Gráfica intercepta scripts puros que querem desenhar tela
const HwndRenderer = lazy(() => import('../components/Window/HwndRenderer'));
// Aplicativos reais do catálogo do Windows usam a ponte nativa, nunca o renderer JS legado.
const NativeAppWindow = lazy(() => import('../apps/NativeAppWindow/NativeAppWindow'));

interface AppRegistryState {
  apps: Record<string, AppDefinition>;
  isReady: boolean;
  discoveredSources: Record<'windows' | 'linux', boolean>;
  registerApp: (app: AppDefinition) => void;
  syncDiscoveredApps: (source: 'windows' | 'linux', apps: AppDefinition[]) => void;
  getApp: (id: string) => AppDefinition | undefined;
  setReady: (ready: boolean) => void;
}

function normalizedRegistration(app: AppDefinition): AppDefinition {
  // Legacy Windows discovery in App.tsx predates source-aware synchronization.
  // Its opaque native-* IDs are still catalog-owned and must not become immortal
  // entries when the backend removes an application from its next snapshot.
  if (!app.catalogSource && app.id.startsWith('native-')) {
    return { ...app, catalogSource: 'windows', source: 'windows', isNative: true, nativeAppId: app.id };
  }
  return app;
}

export const useAppRegistry = create<AppRegistryState>((set, get) => ({
  apps: {},
  isReady: false,
  discoveredSources: { windows: false, linux: false },
  registerApp: (app) => set((state) => {
    // App.tsx may finish its legacy Windows-only fetch after the unified snapshot.
    // Never let that narrower shape overwrite the metadata-rich catalog entry.
    if (!app.catalogSource && app.id.startsWith('native-') && (state.discoveredSources.windows || state.apps[app.id]?.catalogSource)) return state;
    return { apps: { ...state.apps, [app.id]: normalizedRegistration(app) } };
  }),
  syncDiscoveredApps: (source, discoveredApps) => set((state) => {
    const apps: Record<string, AppDefinition> = {};
    for (const [id, app] of Object.entries(state.apps)) {
      if (app.catalogSource !== source) apps[id] = app;
    }
    for (const candidate of discoveredApps) {
      if (candidate.catalogSource !== source || candidate.source !== source) continue;
      const existing = apps[candidate.id];
      // Backend IDs are opaque, but a collision must never replace a bundled app.
      if (existing && !existing.catalogSource) continue;
      apps[candidate.id] = candidate;
    }
    return { apps, discoveredSources: { ...state.discoveredSources, [source]: true } };
  }),
  getApp: (id) => get().apps[id],
  setReady: (ready) => set({ isReady: ready }),
}));

// Helper to get component by ID. Opaque native-* IDs are host-owned Windows apps.
// Unknown non-native IDs keep the Pure-JS HwndRenderer compatibility path.
export const getAppComponent = (id: string) => id.startsWith('native-') ? NativeAppWindow : (components[id] ?? HwndRenderer);

// Backward compatibility or for things that need a list
export const getAppList = () => Object.values(useAppRegistry.getState().apps);

// Initial empty registry (will be populated by Kernel)
export const appRegistry: Record<string, AppDefinition> = {};
export const appList: any[] = [];
