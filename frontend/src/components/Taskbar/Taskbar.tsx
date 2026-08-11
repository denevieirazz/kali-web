// ============================================
// Taskbar Component
// ============================================
import { useState, useEffect } from 'react';
import { useSystem } from '../../stores/systemStore';
import { useWindowManager } from '../../stores/windowManager';
import { useProcessManager } from '../../stores/processManager';
import { useContextMenuStore } from '../../stores/contextMenuStore';
import { useRegistry } from '../../stores/registry';
import './Taskbar.css';

export default function Taskbar() {
  const { bootPhase, toggleStartMenu, isStartMenuOpen, volume, isMuted, isWifiConnected, toggleNotificationCenter } = useSystem();
  const { windows, focusWindow, minimizeWindow, openWindow } = useWindowManager();
  const { createProcess } = useProcessManager();
  const { openContextMenu } = useContextMenuStore();
  const [time, setTime] = useState(new Date());

  const position = String(useRegistry(s => s.hives['HKEY_CURRENT_USER\\Software\\ObsidianOS\\Taskbar']?.Position?.value || 'bottom'));
  const alignment = String(useRegistry(s => s.hives['HKEY_CURRENT_USER\\Software\\ObsidianOS\\Taskbar']?.Alignment?.value || 'center'));

  useEffect(() => {
    const timer = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  if (bootPhase !== 'desktop') return null;

  const hours = time.getHours().toString().padStart(2, '0');
  const minutes = time.getMinutes().toString().padStart(2, '0');
  const dateStr = time.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });

  const taskbarWindows = windows.filter(w => !w.isSystem);

  const handleTaskbarItemClick = (windowId: string) => {
    const win = windows.find(w => w.id === windowId);
    if (!win) return;

    if (win.isActive && !win.isMinimized) {
      minimizeWindow(windowId);
    } else {
      focusWindow(windowId);
    }
  };

  const handleTaskbarContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    openContextMenu(e.clientX, e.clientY, [
      { 
        id: 'task-manager', 
        label: 'Gerenciador de Tarefas', 
        icon: '📊', 
        onClick: () => {
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
      },
      { id: 'sep1', label: '', separator: true },
      { id: 'taskbar-settings', label: 'Configurações da barra de tarefas', icon: '⚙️', onClick: () => {} },
    ]);
  };

  return (
    <div className={`taskbar acrylic position-${position} alignment-${alignment}`} onContextMenu={handleTaskbarContextMenu}>
      {/* Left section - Empty or system icons */}
      <div className="taskbar-left">
      </div>

      {/* Center - Start Button & Running Apps */}
      <div className="taskbar-center">
        <button
          className={`taskbar-btn start-btn ${isStartMenuOpen ? 'active' : ''}`}
          onClick={toggleStartMenu}
          title="Iniciar"
        >
          <svg width="20" height="20" viewBox="0 0 88 88" fill="none">
            <rect x="2" y="2" width="38" height="38" rx="3" fill="currentColor" opacity="0.95"/>
            <rect x="48" y="2" width="38" height="38" rx="3" fill="currentColor" opacity="0.75"/>
            <rect x="2" y="48" width="38" height="38" rx="3" fill="currentColor" opacity="0.75"/>
            <rect x="48" y="48" width="38" height="38" rx="3" fill="currentColor" opacity="0.55"/>
          </svg>
        </button>

        {taskbarWindows.map(win => (
          <button
            key={win.id}
            className={`taskbar-app-btn ${win.isActive ? 'active' : ''} ${win.isMinimized ? 'minimized' : ''}`}
            onClick={() => handleTaskbarItemClick(win.id)}
            title={win.title}
          >
            <span className="taskbar-app-icon">{win.icon}</span>
            <div className="taskbar-app-indicator" />
          </button>
        ))}
      </div>

      {/* Right - System Tray */}
      <div className="taskbar-right">
        {/* System tray icons */}
        <div className="system-tray">
          <button className="tray-btn" title={isWifiConnected ? 'Wi-Fi conectado' : 'Wi-Fi desconectado'}>
            {isWifiConnected ? (
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M1 9l2 2c4.97-4.97 13.03-4.97 18 0l2-2C16.93 2.93 7.08 2.93 1 9zm8 8l3 3 3-3c-1.65-1.66-4.34-1.66-6 0zm-4-4l2 2c2.76-2.76 7.24-2.76 10 0l2-2C15.14 9.14 8.87 9.14 5 13z"/></svg>
            ) : (
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M21 11l2-2c-3.73-3.73-8.87-5.15-13.7-4.31l2.58 2.58c3.3-.02 6.61 1.22 9.12 3.73zm-2 2l-2-2c-1.58-1.58-3.54-2.44-5.56-2.59l3.03 3.03L19 13zm-4 4l-2-2c.55-.55.94-1.27.94-2.06L17 17zM3.41 1.64L2 3.05 5.05 6.1C3.59 6.83 2.22 7.79 1 9l2 2c1.05-1.05 2.3-1.89 3.65-2.49l2.09 2.09C7.19 11.32 5.79 12.29 5 13l2 2c1.39-1.39 3.15-2.2 4.99-2.44l2.41 2.41C13.18 15.38 12.12 16 12 17l3 3 .34-.34L20.95 22l1.41-1.41L3.41 1.64z"/></svg>
            )}
          </button>

          <button className="tray-btn" title={`Volume: ${isMuted ? 'Mudo' : volume + '%'}`}>
            {isMuted || volume === 0 ? (
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z"/></svg>
            ) : (
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/></svg>
            )}
          </button>

          <button className="tray-btn" title={`Bateria: 85%`}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M15.67 4H14V2h-4v2H8.33C7.6 4 7 4.6 7 5.33v15.33C7 21.4 7.6 22 8.33 22h7.33c.74 0 1.34-.6 1.34-1.33V5.33C17 4.6 16.4 4 15.67 4z"/></svg>
          </button>
        </div>

        {/* Clock */}
        <button className="taskbar-clock" onClick={toggleNotificationCenter}>
          <div className="clock-time">{hours}:{minutes}</div>
          <div className="clock-date">{dateStr}</div>
        </button>

        {/* Show Desktop */}
        <div className="show-desktop-btn" title="Mostrar área de trabalho" />
      </div>
    </div>
  );
}
