import { useEffect, useRef, useState } from 'react';
import kernel, { type BSODInfo } from '../core/kernel';
import { kernelAdmin } from '../core/kernelHardening';
import { calculateShellLayout, normalizeTaskbarPosition } from '../core/shellLayout.js';
import { nativeHostBridge } from '../services/nativeHostBridge';
import { useProcessManager } from '../stores/processManager';
import type { BootPhase } from '../stores/systemStore';
import { useWindowManager } from '../stores/windowManager';
import type { SystemTheme, UserProfile } from '../types';

const PHYSICAL_MEMORY_REGISTRY_PATH = 'HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management\\PhysicalMemoryMB';

export function useNativeHostHandshake() {
  useEffect(() => {
    if (!nativeHostBridge.available) return;
    void nativeHostBridge.connect().catch(error => {
      console.warn('[CloudOS] Native host handshake failed.', error);
    });
  }, []);
}

export function useKernelIdentitySync(currentUser: UserProfile | null) {
  useEffect(() => {
    if (currentUser) kernelAdmin.setUserProfile(currentUser);
  }, [currentUser]);
}

export function useKernelHardwareSync(
  bootPhase: BootPhase,
  getRegistryValue: (path: string) => unknown,
) {
  useEffect(() => {
    if (bootPhase !== 'desktop') return;

    localStorage.removeItem('obsidianos_crash_count');
    const ram = getRegistryValue(PHYSICAL_MEMORY_REGISTRY_PATH);
    if (typeof ram === 'number' && Number.isFinite(ram)) {
      kernelAdmin.setTotalMemory(ram);
    }
  }, [bootPhase, getRegistryValue]);
}

export function useDocumentTheme(theme: SystemTheme) {
  useEffect(() => {
    const root = document.documentElement;
    root.style.setProperty('--accent', theme.accentColor);
    root.style.colorScheme = theme.mode;
    document.title = 'CloudOS';
  }, [theme.accentColor, theme.mode]);
}

export function useKernelBSOD() {
  const [info, setInfo] = useState<BSODInfo | null>(() =>
    kernel.bootPhase === 'BSOD' ? kernel.bsodInfo : null,
  );

  useEffect(() => {
    const unsubscribe = kernel.on('bootPhaseChange', (phase: string) => {
      if (phase === 'BSOD') setInfo(kernel.bsodInfo);
      if (phase === 'OFF') setInfo(null);
    });

    if (kernel.bootPhase === 'BSOD') setInfo(kernel.bsodInfo);
    return unsubscribe;
  }, []);

  return info;
}

export function useGlobalTaskManagerShortcut() {
  const createProcess = useProcessManager(state => state.createProcess);
  const openWindow = useWindowManager(state => state.openWindow);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (!event.ctrlKey || !event.shiftKey || event.key !== 'Escape') return;
      event.preventDefault();
      const pid = createProcess('taskmgr.obx', 'Gerenciador de Tarefas', '📊');
      openWindow({
        appId: 'task-manager',
        title: 'Gerenciador de Tarefas',
        icon: '📊',
        width: 800,
        height: 550,
        processId: pid,
      });
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [createProcess, openWindow]);
}

export function useCriticalSubsystemWatchdog({
  bootPhase,
  gdiAvailable,
  user32Available,
}: {
  bootPhase: BootPhase;
  gdiAvailable: boolean;
  user32Available: boolean;
}) {
  useEffect(() => {
    if (gdiAvailable || bootPhase === 'off') {
      document.body.classList.remove('gdi-failure');
      return;
    }

    document.body.classList.add('gdi-failure');
    const timer = window.setTimeout(() => {
      kernel.triggerBSOD({
        stopCode: 'WIN32K_CRITICAL_FAILURE',
        technicalInfo: 'GDI Subsystem completely failed. Missing component: gdi32.dll.',
        failedComponent: 'gdi32.dll',
        bugCheckCode: '0x0000003B',
        parameters: ['0xC0000006', '0x00000000', '0x00000000', '0x00000000'],
      });
      document.body.classList.remove('gdi-failure');
    }, 4000);

    return () => {
      window.clearTimeout(timer);
      document.body.classList.remove('gdi-failure');
    };
  }, [bootPhase, gdiAvailable]);

  useEffect(() => {
    if (user32Available || bootPhase === 'off') {
      document.body.style.pointerEvents = '';
      return;
    }

    document.body.style.pointerEvents = 'none';
    const timer = window.setTimeout(() => {
      kernel.triggerBSOD({
        stopCode: 'CLIENT_SERVER_RUNTIME_ISSUE',
        technicalInfo: 'USER32 subsystem terminated unexpectedly.',
        failedComponent: 'user32.dll',
        bugCheckCode: '0x000000F4',
        parameters: ['0x00000003', '0x00000000', '0x00000000', '0x00000000'],
      });
      document.body.style.pointerEvents = '';
    }, 5000);

    return () => {
      window.clearTimeout(timer);
      document.body.style.pointerEvents = '';
    };
  }, [bootPhase, user32Available]);
}

export function useViewportSize() {
  const [viewport, setViewport] = useState(() => ({
    width: window.innerWidth,
    height: window.innerHeight,
  }));
  const frame = useRef<number | null>(null);

  useEffect(() => {
    const update = () => {
      if (frame.current !== null) cancelAnimationFrame(frame.current);
      frame.current = requestAnimationFrame(() => {
        frame.current = null;
        setViewport(current => {
          const next = { width: window.innerWidth, height: window.innerHeight };
          return current.width === next.width && current.height === next.height ? current : next;
        });
      });
    };

    window.addEventListener('resize', update, { passive: true });
    return () => {
      window.removeEventListener('resize', update);
      if (frame.current !== null) cancelAnimationFrame(frame.current);
    };
  }, []);

  return viewport;
}

export function useShellWindows({
  bootPhase,
  explorerPid,
  viewport,
  taskbarPosition,
}: {
  bootPhase: BootPhase;
  explorerPid: number | null;
  viewport: { width: number; height: number };
  taskbarPosition: unknown;
}) {
  const openWindow = useWindowManager(state => state.openWindow);
  const moveWindow = useWindowManager(state => state.moveWindow);
  const resizeWindow = useWindowManager(state => state.resizeWindow);

  useEffect(() => {
    if (bootPhase !== 'desktop' || explorerPid === null) return;

    const layout = calculateShellLayout(viewport, normalizeTaskbarPosition(taskbarPosition));
    const syncSystemWindow = (
      appId: 'taskbar' | 'desktop',
      title: string,
      bounds: { x: number; y: number; width: number; height: number },
      zIndex: number,
    ) => {
      const existing = kernel.getWindows().find(window => window.appId === appId);
      if (!existing) {
        openWindow({
          appId,
          title,
          icon: '',
          processId: explorerPid,
          width: bounds.width,
          height: bounds.height,
          minWidth: 0,
          minHeight: 0,
          hasFrame: false,
          isSystem: true,
          zIndex,
          params: { x: bounds.x, y: bounds.y },
        });
        return;
      }

      if (existing.x !== bounds.x || existing.y !== bounds.y) {
        moveWindow(existing.id, bounds.x, bounds.y);
      }
      if (existing.width !== bounds.width || existing.height !== bounds.height) {
        resizeWindow(existing.id, bounds.width, bounds.height);
      }
    };

    syncSystemWindow('desktop', 'Desktop', layout.desktop, 1);
    syncSystemWindow('taskbar', 'Taskbar', layout.taskbar, 1000);
    kernelAdmin.reconcileActiveWindow();
  }, [
    bootPhase,
    explorerPid,
    moveWindow,
    openWindow,
    resizeWindow,
    taskbarPosition,
    viewport.height,
    viewport.width,
  ]);
}
