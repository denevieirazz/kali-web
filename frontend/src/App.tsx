import { useEffect, useState } from 'react';
import BootScreen from './components/Boot/BootScreen';
import BSOD from './components/Boot/BSOD';
import RecoveryMode from './components/Boot/RecoveryMode';
import ContextMenu from './components/ContextMenu/ContextMenu';
import LockScreen from './components/LockScreen/LockScreen';
import { NotificationCenter } from './components/Notifications/NotificationCenter';
import { NotificationContainer } from './components/Notifications/NotificationContainer';
import SetupWizard from './components/Setup/SetupWizard';
import StartMenu from './components/StartMenu/StartMenu';
import WindowRenderer from './components/Window/WindowRenderer';
import WorkflowBatch4Shell from './components/Workflow/WorkflowBatch4Shell';
import WorkflowShell from './components/Workflow/WorkflowShell';
import OpenWithModal from './components/OpenWithModal/OpenWithModal';
import DownloadManagerModal from './components/DownloadManager/DownloadManagerModal';
import kernel from './core/kernel';
import {
  useCriticalSubsystemWatchdog,
  useDocumentTheme,
  useGlobalTaskManagerShortcut,
  useKernelBSOD,
  useKernelHardwareSync,
  useKernelIdentitySync,
  useNativeHostHandshake,
  useShellWindows,
  useViewportSize,
} from './hooks/useCloudOSRuntime';
import { useContextMenuStore } from './stores/contextMenuStore';
import { useFileSystem } from './stores/fileSystem';
import { useProcessManager } from './stores/processManager';
import { useRegistry } from './stores/registry';
import { useSystem } from './stores/systemStore';
import { useUserStore } from './stores/userStore';
import { useDownloadManager } from './stores/downloadManager';
import { openFile } from './services/fileLauncher';
import { refreshUnifiedAppRegistry } from './services/systemHubClient';
import './index.css';
import './cloudosEnhancements.css';

export default function App() {
  const bootPhase = useSystem(state => state.bootPhase);
  const setBootPhase = useSystem(state => state.setBootPhase);
  const theme = useSystem(state => state.theme);
  const currentUser = useUserStore(state => state.currentUser);
  const isAuthenticated = useUserStore(state => state.isAuthenticated);
  const setupStatus = useUserStore(state => state.setupStatus);
  const validateSession = useUserStore(state => state.validateSession);
  const getRegistryValue = useRegistry(state => state.getValue);

  const [isRecovery] = useState(() => {
    const crashCount = Number.parseInt(localStorage.getItem('obsidianos_crash_count') ?? '0', 10);
    return Number.isFinite(crashCount) && crashCount >= 3;
  });

  useEffect(() => {
    void validateSession();
    (window as any).__CLOUDOS_DEBUG__ = {
      useFileSystem,
      useDownloadManager,
      openFile,
    };
  }, [validateSession]);

  // Publish one source-aware Windows + Linux snapshot into the registry used by
  // CloudOS Start. The first desktop sync is forced; subsequent focus/visibility
  // and periodic syncs are cache-aware, so an app installed while CloudOS is open
  // appears without restarting the shell while the backend's discovery TTL prevents
  // repeated PowerShell/WSL scans. Paths and Exec values remain behind opaque IDs.
  useEffect(() => {
    if (bootPhase !== 'desktop' || !isAuthenticated) return undefined;

    let disposed = false;
    let refreshInFlight = false;

    const syncCatalog = async (force = false) => {
      if (disposed || refreshInFlight) return;
      refreshInFlight = true;
      try {
        await refreshUnifiedAppRegistry(force);
      } catch {
        // The shell remains usable while local discovery is warming up or unavailable.
      } finally {
        refreshInFlight = false;
      }
    };

    const syncWhenVisible = () => {
      if (document.visibilityState === 'visible') void syncCatalog(false);
    };

    const syncOnFocus = () => {
      if (document.visibilityState === 'visible') void syncCatalog(false);
    };

    void syncCatalog(true);
    document.addEventListener('visibilitychange', syncWhenVisible);
    window.addEventListener('focus', syncOnFocus);
    const interval = window.setInterval(syncWhenVisible, 30_000);

    return () => {
      disposed = true;
      document.removeEventListener('visibilitychange', syncWhenVisible);
      window.removeEventListener('focus', syncOnFocus);
      window.clearInterval(interval);
    };
  }, [bootPhase, isAuthenticated]);

  // The backend is the source of truth for whether first-boot setup still exists.
  // If the browser-local OOBE marker was lost but an administrator already exists,
  // hand off to Winlogon instead of mounting a second setup wizard. Do not perform
  // this handoff while the current OOBE has already authenticated/created its user,
  // because that flow still needs to finish its one-time recovery-code step.
  useEffect(() => {
    if (bootPhase !== 'setup' || setupStatus !== 'complete' || isAuthenticated || currentUser) return;
    localStorage.setItem('cloudos-oobe-completed', 'true');
    setBootPhase('login');
    kernel.bootPhase = 'WINLOGON';
  }, [bootPhase, currentUser, isAuthenticated, setBootPhase, setupStatus]);

  useNativeHostHandshake();
  useKernelIdentitySync(currentUser);
  useKernelHardwareSync(bootPhase, getRegistryValue);
  useDocumentTheme(theme);
  useGlobalTaskManagerShortcut();

  const bsodInfo = useKernelBSOD();
  const gdiAvailable = useFileSystem(state => Boolean(state.nodes['C:\\ObsidianOS\\System32\\gdi32.dll']));
  const user32Available = useFileSystem(state => Boolean(state.nodes['C:\\ObsidianOS\\System32\\user32.dll']));
  useCriticalSubsystemWatchdog({ bootPhase, gdiAvailable, user32Available });

  const explorerPid = useProcessManager(state =>
    state.processes.find(process => process.name === 'explorer.obx')?.pid ?? null,
  );
  const viewport = useViewportSize();
  const taskbarPosition = useRegistry(state =>
    state.hives['HKEY_CURRENT_USER\\Software\\ObsidianOS\\Taskbar']?.Position?.value ?? 'bottom',
  );
  useShellWindows({ bootPhase, explorerPid, viewport, taskbarPosition });

  const contextMenuOpen = useContextMenuStore(state => state.isOpen);
  const contextMenuX = useContextMenuStore(state => state.x);
  const contextMenuY = useContextMenuStore(state => state.y);
  const contextMenuItems = useContextMenuStore(state => state.items);
  const closeContextMenu = useContextMenuStore(state => state.closeContextMenu);

  return (
    <div className="obsidianos-root cloudos-root" data-theme={theme.mode}>
      {isRecovery ? (
        <RecoveryMode />
      ) : bsodInfo ? (
        <BSOD info={bsodInfo} />
      ) : (
        <>
          {(bootPhase === 'off' || bootPhase === 'bios' || bootPhase === 'loading') && <BootScreen />}
          {bootPhase === 'login' && <LockScreen />}

          {bootPhase === 'desktop' && (
            <>
              <WindowRenderer />
              <WorkflowShell />
              <WorkflowBatch4Shell />
              {explorerPid !== null && <StartMenu />}
            </>
          )}

          {bootPhase === 'setup' && <SetupWizard />}

          <NotificationContainer />
          <NotificationCenter />
          <OpenWithModal />
          <DownloadManagerModal />

          {contextMenuOpen && (
            <ContextMenu
              x={contextMenuX}
              y={contextMenuY}
              items={contextMenuItems}
              onClose={closeContextMenu}
            />
          )}
        </>
      )}
    </div>
  );
}
