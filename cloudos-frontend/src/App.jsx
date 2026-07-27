import { useState, useEffect } from 'react';
import { Terminal as TerminalIcon, FileText, Settings, Search, Wifi, Volume2, Battery, Cpu, MemoryStick, RefreshCw, FolderOpen } from 'lucide-react';
import Window from './Window';
import { TerminalApp, NotepadApp, SettingsApp, FileManagerApp } from './apps';
import BootScreen from './BootScreen';

const APPS_CONFIG = {
  terminal: { id: 'terminal', title: 'Terminal Linux', icon: TerminalIcon, Component: TerminalApp },
  files: { id: 'files', title: 'Arquivos', icon: FolderOpen, Component: FileManagerApp },
  notepad: { id: 'notepad', title: 'Bloco de Notas', icon: FileText, Component: NotepadApp },
  settings: { id: 'settings', title: 'Configurações', icon: Settings, Component: SettingsApp }
};

const APPS_LIST = Object.values(APPS_CONFIG);

export default function App() {
  const [booting, setBooting] = useState(true);
  const [windows, setWindows] = useState(() => {
    try {
      const saved = localStorage.getItem('cloudos_windows');
      const parsed = saved ? JSON.parse(saved) : [];
      if (Array.isArray(parsed)) {
        return parsed.filter(w => w && APPS_CONFIG[w.appId]).map(w => ({
          id: w.id || Date.now(),
          appId: w.appId,
          x: w.x || 50,
          y: w.y || 50,
          w: w.w || 600,
          h: w.h || 400,
          z: w.z || 100
        }));
      }
      return [];
    } catch {
      return [];
    }
  });

  const [zIndex, setZIndex] = useState(100);
  const [startOpen, setStartOpen] = useState(false);
  const [time, setTime] = useState(new Date());
  const [bg, setBg] = useState(() => localStorage.getItem('cloudos_bg') || 'https://images.unsplash.com/photo-1579546929518-9e396f3cc809?q=80&w=2070');
  const [contextMenu, setContextMenu] = useState({ visible: false, x: 0, y: 0 });

  useEffect(() => {
    try {
      const cleanWindows = windows.map(({ id, appId, x, y, w, h, z }) => ({ id, appId, x, y, w, h, z }));
      localStorage.setItem('cloudos_windows', JSON.stringify(cleanWindows));
    } catch (e) {}
  }, [windows]);

  useEffect(() => {
    try { localStorage.setItem('cloudos_bg', bg); } catch (e) {}
  }, [bg]);

  useEffect(() => {
    if (booting) return;
    const timer = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, [booting]);

  const openApp = (appId) => {
    if (!APPS_CONFIG[appId]) return;
    const existing = windows.find(w => w.appId === appId);
    if (existing) return focusWindow(existing.id);
    
    const w = Math.min(700, window.innerWidth - 100);
    const h = Math.min(450, window.innerHeight - 100);
    const x = Math.max(10, Math.random() * (window.innerWidth - w - 20));
    const y = Math.max(10, Math.random() * (window.innerHeight - h - 60));
    
    const newWin = { id: Date.now(), appId, x, y, w, h, z: zIndex + 1 };
    setWindows(prev => [...prev, newWin]);
    setZIndex(prev => prev + 1);
    setStartOpen(false);
  };

  const closeApp = (id) => setWindows(prev => prev.filter(w => w.id !== id));
  const focusWindow = (id) => {
    setWindows(prev => prev.map(w => w.id === id ? { ...w, z: zIndex + 1 } : w));
    setZIndex(prev => prev + 1);
  };

  const handleContextMenu = (e) => { e.preventDefault(); setContextMenu({ visible: true, x: e.clientX, y: e.clientY }); };
  const closeContextMenu = () => setContextMenu({ ...contextMenu, visible: false });

  if (booting) {
    return <BootScreen onBootComplete={() => setBooting(false)} />;
  }

  return (
    <div 
      className="desktop" 
      style={{ background: bg.startsWith('http') ? `url(${bg}) center/cover no-repeat` : bg }} 
      onClick={() => { closeContextMenu(); startOpen && setStartOpen(false); }}
      onContextMenu={handleContextMenu}
    >
      <div className="desktop-widget">
        <div className="widget-clock">{time.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</div>
        <div className="widget-date">{time.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })}</div>
        <div className="widget-stats">
          <div className="stat-item"><Cpu size={14} /> <div className="stat-bar"><div className="stat-fill" style={{width: '45%'}}></div></div></div>
          <div className="stat-item"><MemoryStick size={14} /> <div className="stat-bar"><div className="stat-fill" style={{width: '62%'}}></div></div></div>
        </div>
      </div>

      <div className="desktop-icons">
        {APPS_LIST.map(app => {
          const Icon = app.icon;
          return (
            <div key={app.id} className="d-icon" onDoubleClick={() => openApp(app.id)}>
              <Icon size={42} color="white" />
              <span>{app.title}</span>
            </div>
          );
        })}
      </div>

      {windows.map(win => {
        const appConfig = APPS_CONFIG[win.appId];
        if (!appConfig) return null;
        const AppComp = appConfig.Component;
        return (
          <Window key={win.id} win={{ ...win, title: appConfig.title, icon: appConfig.icon }} onClose={() => closeApp(win.id)} onFocus={() => focusWindow(win.id)}>
            <AppComp setBg={setBg} />
          </Window>
        );
      })}

      {startOpen && (
        <div className="start-menu" onClick={(e) => e.stopPropagation()}>
          <input className="start-search" placeholder="Pesquisar apps..." />
          <div className="start-grid">
            {APPS_LIST.map(app => {
              const Icon = app.icon;
              return (
                <div key={app.id} className="start-app" onClick={() => openApp(app.id)}>
                  <Icon size={32} color="white" />
                  <span>{app.title}</span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {contextMenu.visible && (
        <div className="context-menu" style={{ top: contextMenu.y, left: contextMenu.x }} onClick={(e) => e.stopPropagation()}>
          <div className="context-item" onClick={() => window.location.reload()}><RefreshCw size={14} /> Atualizar</div>
          <div className="context-divider"></div>
          <div className="context-item" onClick={() => openApp('terminal')}><TerminalIcon size={14} /> Abrir Terminal</div>
          <div className="context-item" onClick={() => openApp('settings')}><Settings size={14} /> Personalizar</div>
        </div>
      )}

      <div className="taskbar" onClick={(e) => e.stopPropagation()}>
        <div className="taskbar-app" onClick={() => setStartOpen(!startOpen)}><Search size={24} /></div>
        {APPS_LIST.map(app => {
          const Icon = app.icon;
          return (
            <div key={app.id} className={`taskbar-app ${windows.some(w => w.appId === app.id) ? 'active' : ''}`} onClick={() => openApp(app.id)}>
              <Icon size={22} />
            </div>
          );
        })}
        <div className="taskbar-tray">
          <Wifi size={16} /><Volume2 size={16} /><Battery size={16} />
          <span>{time.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</span>
        </div>
      </div>
    </div>
  );
}
