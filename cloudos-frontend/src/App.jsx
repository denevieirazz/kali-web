import { useState, useEffect, useCallback } from 'react';
import { Search, Wifi, Volume2, Battery, Cpu, MemoryStick, RefreshCw, Power } from 'lucide-react';
import Window from './Window';
import { AppList, AppRegistry } from './registry';
import BootScreen from './BootScreen';
import LoginScreen from './LoginScreen';

export default function App() {
  const [booting, setBooting] = useState(true);
  const [isAuthenticated, setIsAuthenticated] = useState(() => !!localStorage.getItem('cloudos_token'));
  const [windows, setWindows] = useState([]);
  const [zIndex, setZIndex] = useState(100);
  const [startOpen, setStartOpen] = useState(false);
  const [time, setTime] = useState(new Date());
  const [bg, setBg] = useState(() => localStorage.getItem('cloudos_bg') || 'https://images.unsplash.com/photo-1579546929518-9e396f3cc809?q=80&w=2070');
  
  const [selectedIcons, setSelectedIcons] = useState([]);
  const [contextMenu, setContextMenu] = useState({ visible: false, x: 0, y: 0 });
  const [iconPositions, setIconPositions] = useState(() => JSON.parse(localStorage.getItem('cloudos_icon_pos') || '{}'));

  useEffect(() => {
    const timer = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  const openApp = (appId, payload = null) => {
    const existing = windows.find(w => w.appId === appId);
    if (existing) return focusWindow(existing.id);
    
    const w = Math.min(800, window.innerWidth - 100);
    const h = Math.min(550, window.innerHeight - 100);
    setWindows(prev => [...prev, { id: Date.now(), appId, x: 50 + Math.random()*100, y: 50, w, h, z: zIndex + 1, payload }]);
    setZIndex(prev => prev + 1);
    setStartOpen(false);
  };

  const closeApp = (id) => setWindows(prev => prev.filter(w => w.id !== id));
  const focusWindow = (id) => {
    setWindows(prev => prev.map(w => w.id === id ? { ...w, z: zIndex + 1 } : w));
    setZIndex(prev => prev + 1);
  };

  const handleDesktopClick = (e) => {
    if (e.target.classList.contains('desktop')) setSelectedIcons([]);
    setContextMenu({ ...contextMenu, visible: false });
    setStartOpen(false);
  };

  const handleContextMenu = (e) => {
    e.preventDefault();
    setContextMenu({ visible: true, x: e.clientX, y: e.clientY });
  };

  // Atalhos do teclado (F2, Delete)
  const handleKeyDown = useCallback((e) => {
    if (e.key === 'F2' && selectedIcons.length === 1) {
      alert('Renomear ícone (em implementação)');
    }
    if (e.key === 'Delete' && selectedIcons.length > 0) {
      alert('Remover ícones selecionados (em implementação)');
    }
  }, [selectedIcons]);

  const handleLogout = () => {
    localStorage.removeItem('cloudos_token');
    window.location.reload();
  };

  if (booting) return <BootScreen onBootComplete={() => setBooting(false)} />;
  if (!isAuthenticated) return <LoginScreen onLogin={() => setIsAuthenticated(true)} />;

  return (
    <div 
      className="desktop" 
      style={{ background: bg.startsWith('http') ? `url(${bg}) center/cover no-repeat` : bg }} 
      onClick={handleDesktopClick}
      onContextMenu={handleContextMenu}
      onKeyDown={handleKeyDown}
      tabIndex={0}
    >
      <div className="desktop-widget">
        <div className="widget-clock">{time.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</div>
        <div className="widget-date">{time.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })}</div>
        <div className="widget-stats">
          <div className="stat-item"><Cpu size={14} /> <div className="stat-bar"><div className="stat-fill" style={{width: '45%'}}></div></div></div>
          <div className="stat-item"><MemoryStick size={14} /> <div className="stat-bar"><div className="stat-fill" style={{width: '62%'}}></div></div></div>
        </div>
      </div>

      <div className="desktop-icons-container">
        {AppList.map(app => {
          const Icon = app.icon;
          const pos = iconPositions[app.id] || { x: 20, y: 20 };
          return (
            <div 
              key={app.id} 
              className={`d-icon ${selectedIcons.includes(app.id) ? 'selected' : ''}`}
              style={{ position: 'relative' }}
              onClick={(e) => { e.stopPropagation(); setSelectedIcons([app.id]); }}
              onDoubleClick={() => openApp(app.id)}
            >
              <Icon size={42} color="white" />
              <span>{app.title}</span>
            </div>
          );
        })}
      </div>

      {windows.map(win => {
        const appConfig = AppRegistry[win.appId];
        if (!appConfig) return null;
        const AppComp = appConfig.Component;
        return (
          <Window key={win.id} win={{ ...win, title: appConfig.title, icon: appConfig.icon }} onClose={() => closeApp(win.id)} onFocus={() => focusWindow(win.id)}>
            <AppComp payload={win.payload} openApp={openApp} setBg={setBg} />
          </Window>
        );
      })}

      {contextMenu.visible && (
        <div className="context-menu" style={{ top: contextMenu.y, left: contextMenu.x }} onClick={(e) => e.stopPropagation()}>
          <div className="context-item" onClick={() => window.location.reload()}><RefreshCw size={14} /> Atualizar</div>
          <div className="context-divider"></div>
          <div className="context-item danger" onClick={handleLogout}><Power size={14} /> Sair / Logout</div>
        </div>
      )}

      <div className="taskbar" onClick={(e) => e.stopPropagation()}>
        <div className="taskbar-app" onClick={() => setStartOpen(!startOpen)}><Search size={24} /></div>
        {AppList.map(app => {
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
