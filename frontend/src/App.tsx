// ============================================
// ObsidianOS - Main Application
// ============================================
import { useEffect, useState } from 'react';
import { useSystem } from './stores/systemStore';
import BootScreen from './components/Boot/BootScreen';
import BSOD from './components/Boot/BSOD';
import RecoveryMode from './components/Boot/RecoveryMode';
import { useFileSystem } from './stores/fileSystem';
import { useProcessManager } from './stores/processManager';
import { useWindowManager } from './stores/windowManager';
import { useRegistry } from './stores/registry';
import kernel from './core/kernel';
import LockScreen from './components/LockScreen/LockScreen';
import SetupWizard from './components/Setup/SetupWizard';
import StartMenu from './components/StartMenu/StartMenu';
import WindowRenderer from './components/Window/WindowRenderer';
import { useContextMenuStore } from './stores/contextMenuStore';
import ContextMenu from './components/ContextMenu/ContextMenu';
import { NotificationContainer } from './components/Notifications/NotificationContainer';
import { NotificationCenter } from './components/Notifications/NotificationCenter';
import { useUserStore } from './stores/userStore';
import { nativeHostBridge } from './services/nativeHostBridge';
import './index.css';

export default function App() {
  const { bootPhase, theme } = useSystem();
  const [isBSOD, setIsBSOD] = useState(false);
  const [bsodInfo, setBsodInfo] = useState<any>(null);
  const [isRecovery] = useState(() => {
    const count = parseInt(localStorage.getItem('obsidianos_crash_count') ?? '0', 10);
    return count >= 3;
  });
  const getRegValue = useRegistry(s => s.getValue);
  const { currentUser, validateSession } = useUserStore();

  useEffect(() => {
    validateSession();
  }, [validateSession]);

  // Confirma que o bundle React realmente montou, inclusive nas telas de
  // primeiro acesso e login. O bootstrap nativo usa esse handshake para não
  // considerar uma página vazia como um shell pronto.
  useEffect(() => {
    if (nativeHostBridge.available) {
      void nativeHostBridge.connect().catch(() => {});
    }
  }, []);

  // SYNC: Ensure Kernel user matches persisted Local User Store
  useEffect(() => {
    if (currentUser) {
      (kernel as any)._user = currentUser;
      (kernel as any)._emitSystemSnapshot();
    }
  }, [currentUser]);

  // Sync Hardware from Registry
  useEffect(() => {
    if (bootPhase === 'desktop') {
      // Successful boot — reset crash counter
      localStorage.removeItem('obsidianos_crash_count');
      const ram = getRegValue('HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management\\PhysicalMemoryMB');
      if (typeof ram === 'number') {
        (kernel as any)._resources.totalMemory = ram;
      }
    }
  }, [bootPhase, getRegValue]);

  // Apply theme-based CSS variables
  useEffect(() => {
    const root = document.documentElement;
    root.style.setProperty('--accent', theme.accentColor);

    // Set document title
    document.title = 'ObsidianOS';
  }, [theme]);

  // Handle global BSOD listening
  useEffect(() => {
    const unsub = kernel.on('bootPhaseChange', (phase) => {
      if (phase === 'BSOD') {
        setBsodInfo(kernel.bsodInfo);
        setIsBSOD(true);
      } else if (phase === 'OFF') {
        setIsBSOD(false);
      }
    });
    
    if (kernel.bootPhase === 'BSOD') {
      setBsodInfo(kernel.bsodInfo);
      setIsBSOD(true);
    }
    
    return unsub;
  }, []);

  const openWindow = useWindowManager(s => s.openWindow);
  const createProcess = useProcessManager(s => s.createProcess);

  // Handle keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Ctrl+Shift+Escape = Task Manager
      if (e.ctrlKey && e.shiftKey && e.key === 'Escape') {
        e.preventDefault();
        const pid = createProcess('taskmgr.obx', 'Gerenciador de Tarefas', '📊');
        openWindow({
          appId: 'task-manager',
          title: 'Gerenciador de Tarefas',
          icon: '📊',
          width: 800,
          height: 550,
          processId: pid,
        });
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [openWindow, createProcess]);

  // DEEP REALISM: Watch critical system files & processes
  const gdi32 = useFileSystem(s => !!s.nodes['C:\\ObsidianOS\\System32\\gdi32.dll']);
  const user32 = useFileSystem(s => !!s.nodes['C:\\ObsidianOS\\System32\\user32.dll']);
  const explorerRunning = useProcessManager(s => s.processes.some(p => p.name === 'explorer.obx'));

  // GDI32 Failure Corrupts the screen visually
  useEffect(() => {
    if (!gdi32 && bootPhase !== 'off') {
      document.body.classList.add('gdi-failure');
      const timer = setTimeout(() => {
        kernel.triggerBSOD({
          stopCode: 'WIN32K_CRITICAL_FAILURE',
          technicalInfo: 'GDI Subsystem completely failed. Missing component: gdi32.dll.',
          failedComponent: 'gdi32.dll',
          bugCheckCode: '0x0000003B',
          parameters: ['0xC0000006', '0x00000000', '0x00000000', '0x00000000']
        });
        document.body.classList.remove('gdi-failure');
      }, 4000);
      return () => clearTimeout(timer);
    } else {
      document.body.classList.remove('gdi-failure');
    }
  }, [gdi32, bootPhase]);

  // USER32 Failure makes system unresponsive
  useEffect(() => {
    if (!user32 && bootPhase !== 'off') {
      document.body.style.pointerEvents = 'none';
      const timer = setTimeout(() => {
        kernel.triggerBSOD({
          stopCode: 'CLIENT_SERVER_RUNTIME_ISSUE',
          technicalInfo: 'USER32 subsystem terminated unexpectedly.',
          failedComponent: 'user32.dll',
          bugCheckCode: '0x000000F4',
          parameters: ['0x00000003', '0x00000000', '0x00000000', '0x00000000']
        });
        document.body.style.pointerEvents = '';
      }, 5000);
      return () => { clearTimeout(timer); document.body.style.pointerEvents = ''; };
    }
  }, [user32, bootPhase]);

  // DEEP REALISM: CPU/RAM monitorados via scheduler (kernel.startScheduler() called on finalizeBoot)
  // No manual interval needed here — the kernel scheduler emits cpuChange every 100ms
  const processes = useProcessManager(s => s.processes);

  // Window Size tracking for responsive layout
  const [windowSize, setWindowSize] = useState({ w: window.innerWidth, h: window.innerHeight });
  useEffect(() => {
    const handleResize = () => setWindowSize({ w: window.innerWidth, h: window.innerHeight });
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  const taskbarPosition = String(useRegistry(s => s.hives['HKEY_CURRENT_USER\\Software\\ObsidianOS\\Taskbar']?.Position?.value || 'bottom'));

  const { moveWindow, resizeWindow } = useWindowManager();

  // Start Shell Components as Windows (DEEP REALISM: Taskbar as a Window)
  useEffect(() => {
    if (bootPhase === 'desktop' && explorerRunning) {
      const proc = processes.find(p => p.name === 'explorer.obx');
      if (proc) {
        let tbX = 0, tbY = 0, tbW = windowSize.w, tbH = 48;
        let dtX = 0, dtY = 0, dtW = windowSize.w, dtH = windowSize.h - 48;

        switch (taskbarPosition) {
          case 'top':
            tbX = 0; tbY = 0; tbW = windowSize.w; tbH = 48;
            dtX = 0; dtY = 48; dtW = windowSize.w; dtH = windowSize.h - 48;
            break;
          case 'left':
            tbX = 0; tbY = 0; tbW = 48; tbH = windowSize.h;
            dtX = 48; dtY = 0; dtW = windowSize.w - 48; dtH = windowSize.h;
            break;
          case 'right':
            tbX = windowSize.w - 48; tbY = 0; tbW = 48; tbH = windowSize.h;
            dtX = 0; dtY = 0; dtW = windowSize.w - 48; dtH = windowSize.h;
            break;
          case 'bottom':
          default:
            tbX = 0; tbY = windowSize.h - 48; tbW = windowSize.w; tbH = 48;
            dtX = 0; dtY = 0; dtW = windowSize.w; dtH = windowSize.h - 48;
            break;
        }

        const taskbarWin = kernel.getWindows().find(w => w.appId === 'taskbar');
        if (!taskbarWin) {
          openWindow({
            appId: 'taskbar', title: 'Taskbar', icon: '', processId: proc.pid,
            width: tbW, height: tbH, minWidth: 0, minHeight: 0, hasFrame: false, isSystem: true, params: { x: tbX, y: tbY }
          });
        } else {
          if (taskbarWin.x !== tbX || taskbarWin.y !== tbY) moveWindow(taskbarWin.id, tbX, tbY);
          if (taskbarWin.width !== tbW || taskbarWin.height !== tbH) resizeWindow(taskbarWin.id, tbW, tbH);
        }

        const desktopWin = kernel.getWindows().find(w => w.appId === 'desktop');
        if (!desktopWin) {
          openWindow({
            appId: 'desktop', title: 'Desktop', icon: '', processId: proc.pid,
            width: dtW, height: dtH, minWidth: 0, minHeight: 0, hasFrame: false, isSystem: true, zIndex: 1, params: { x: dtX, y: dtY }
          });
        } else {
          if (desktopWin.x !== dtX || desktopWin.y !== dtY) moveWindow(desktopWin.id, dtX, dtY);
          if (desktopWin.width !== dtW || desktopWin.height !== dtH) resizeWindow(desktopWin.id, dtW, dtH);
        }
      }
    }
  }, [bootPhase, explorerRunning, processes, openWindow, moveWindow, resizeWindow, windowSize, taskbarPosition]);

  const { isOpen, x, y, items, closeContextMenu } = useContextMenuStore();

  return (
    <div className="obsidianos-root" data-theme={theme.mode}>
      {isRecovery ? (
        <RecoveryMode />
      ) : isBSOD && bsodInfo ? (
        <BSOD info={bsodInfo} />
      ) : (
        <>
          {/* Boot Screen */}
          {(bootPhase === 'off' || bootPhase === 'bios' || bootPhase === 'loading') && (
            <BootScreen />
          )}

          {/* Lock Screen */}
          {bootPhase === 'login' && (
            <LockScreen />
          )}

          {/* Desktop Environment */}
          {bootPhase === 'desktop' && (
            <>
              <WindowRenderer />
              {explorerRunning && <StartMenu />}
            </>
          )}

          {/* OOBE / Initial Setup */}
          {bootPhase === 'setup' && <SetupWizard />}

          {/* System Dialogs & Overlays */}
          <NotificationContainer />
          <NotificationCenter />

          {/* Global Context Menu */}
          {isOpen && (
            <ContextMenu
              x={x}
              y={y}
              items={items}
              onClose={closeContextMenu}
            />
          )}
        </>
      )}
    </div>
  );
}
