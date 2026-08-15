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
import './index.css';

export default function App() {
  const bootPhase = useSystem(state => state.bootPhase);
  const theme = useSystem(state => state.theme);
  const currentUser = useUserStore(state => state.currentUser);
  const validateSession = useUserStore(state => state.validateSession);
  const getRegistryValue = useRegistry(state => state.getValue);

  const [isRecovery] = useState(() => {
    const crashCount = Number.parseInt(localStorage.getItem('obsidianos_crash_count') ?? '0', 10);
    return Number.isFinite(crashCount) && crashCount >= 3;
  });

  useEffect(() => {
    void validateSession();
  }, [validateSession]);

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
              {explorerPid !== null && <StartMenu />}
            </>
          )}

          {bootPhase === 'setup' && <SetupWizard />}

          <NotificationContainer />
          <NotificationCenter />

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
