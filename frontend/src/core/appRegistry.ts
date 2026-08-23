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
  'office-viewer': lazy(() => import('../apps/OfficeViewer/OfficeViewer')),
  'taskbar': lazy(() => import('../components/Taskbar/Taskbar')),
  'desktop': lazy(() => import('../components/Desktop/Desktop')),
};

// O novo Motor de Renderização Gráfica intercepta scripts puros que querem desenhar tela
const HwndRenderer = lazy(() => import('../components/Window/HwndRenderer'));

interface AppRegistryState {
  apps: Record<string, AppDefinition>;
  isReady: boolean;
  registerApp: (app: AppDefinition) => void;
  getApp: (id: string) => AppDefinition | undefined;
  setReady: (ready: boolean) => void;
}

export const useAppRegistry = create<AppRegistryState>((set, get) => ({
  apps: {},
  isReady: false,
  registerApp: (app) => set((state) => ({ 
    apps: { ...state.apps, [app.id]: app } 
  })),
  getApp: (id) => get().apps[id],
  setReady: (ready) => set({ isReady: ready }),
}));

// Helper to get component by ID — falls back to HwndRenderer for Pure-JS executables
export const getAppComponent = (id: string) => components[id] ?? HwndRenderer;

// Backward compatibility or for things that need a list
export const getAppList = () => Object.values(useAppRegistry.getState().apps);

// Initial empty registry (will be populated by Kernel)
export const appRegistry: Record<string, AppDefinition> = {};
export const appList: any[] = [];
