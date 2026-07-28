import { useState, useEffect } from 'react';
import { Search, Wifi, Volume2, Battery, Bell, Power, Lock } from 'lucide-react';
import Window from './Window';
import { AppList, AppRegistry } from './registry';
import BootScreen from './BootScreen';
import LoginScreen from './LoginScreen';
import { CommandPalette } from './components/CommandPalette';
import { CloudOSProvider, useCloudOS } from './store/CloudOSContext';

function Desktop() {
  const { settings, setBg, isLocked, lockSystem, notifications, fetchNotifications } = useCloudOS();
  const [booting, setBooting] = useState(true);
  const [isAuthenticated, setIsAuthenticated] = useState(() => !!localStorage.getItem('cloudos_token'));
  const [windows, setWindows] = useState([]);
  const [zIndex, setZIndex] = useState(100);
  const [startOpen, setStartOpen] = useState(false);
  const [time, setTime] = useState(new Date());
  const [contextMenu, setContextMenu] = useState({ visible: false, x: 0, y: 0 });
  const [isPaletteOpen, setIsPaletteOpen] = useState(false);
  const [showNotifs, setShowNotifs] = useState(false);
  const [selectedIcons, setSelectedIcons] = useState([]);

  useEffect(() => {
    const timer = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  const openApp = (appId, payload = null) => {
    const existing = windows.find(w => w.appId === appId);
    if (existing) return focusWindow(existing.id);
    const w = Math.min(800, window.innerWidth - 100);
    const h = Math.min(550, window.innerHeight - 100);
    setWindows(prev => [...prev, { id: Date.now(), appId, x: 50 + Math.random()*50, y: 50, w, h, z: zIndex + 1, payload }]);
    setZIndex(prev => prev + 1);
    setStartOpen(false);
  };

  const closeApp = (id) => setWindows(prev => prev.filter(w => w.id !== id));
  const focusWindow = (id) => {
    setWindows(prev => prev.map(w => w.id === id ? { ...w, z: zIndex + 1 } : w));
    setZIndex(prev => prev + 1);
  };

  const handleLogout = () => {
    localStorage.removeItem('cloudos_token');
    window.location.reload();
  };

  const wallpaperUrl = settings?.wallpaper || 'https://images.unsplash.com/photo-1579546929518-9e396f3cc809?q=80&w=2070';

  if (booting) return <BootScreen onBootComplete={() => setBooting(false)} />;
  if (!isAuthenticated) return <LoginScreen onLogin={() => setIsAuthenticated(true)} />;
  if (isLocked) return <LoginScreen onLogin={() => window.location.reload()} isLockScreen={true} />;

  return (
    <div 
      className="desktop" 
      style={{ background: wallpaperUrl.startsWith('http') ? `url(${wallpaperUrl}) center/cover no-repeat` : wallpaperUrl }} 
      onClick={() => { setContextMenu({...contextMenu, visible: false}); setShowNotifs(false); setStartOpen(false); setSelectedIcons([]); }}
      onContextMenu={(e) => { e.preventDefault(); setContextMenu({ visible: true, x: e.clientX, y: e.clientY }); }}
    >
      <CommandPalette 
        isOpen={isPaletteOpen} 
        onClose={() => setIsPaletteOpen(false)} 
        openApp={openApp}
        actions={{ togglePalette: () => setIsPaletteOpen(!isPaletteOpen), lock: lockSystem }}
      />

      {/* Desktop Icons */}
      <div className="desktop-icons-container">
        {AppList.map(app => {
          const Icon = app.icon;
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

      {/* Windows */}
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

      {/* Start Menu */}
      {startOpen && (
        <div className="start-menu" onClick={(e) => e.stopPropagation()}>
          <input className="start-search" placeholder="Pesquisar apps..." />
          <div className="start-grid">
            {AppList.map(app => {
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

      {/* Taskbar */}
      <div className="taskbar" onClick={(e) => e.stopPropagation()}>
        <div className="taskbar-app" onClick={() => setIsPaletteOpen(true)} title="Command Palette (Ctrl+Shift+P)"><Search size={24} /></div>
        {AppList.map(app => (
          <div key={app.id} className={`taskbar-app ${windows.some(w => w.appId === app.id) ? 'active' : ''}`} onClick={() => openApp(app.id)}>
            <app.icon size={22} />
          </div>
        ))}
        <div className="taskbar-tray">
          <div className="taskbar-app" style={{ position: 'relative', display: 'flex', alignItems: 'center' }} onClick={() => { setShowNotifs(!showNotifs); fetchNotifications(); }}>
            <Bell size={16} />
            {notifications && notifications.length > 0 && <span className="notif-badge"></span>}
          </div>
          <Wifi size={16} /><Volume2 size={16} /><Battery size={16} />
          <span>{time.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</span>
        </div>
      </div>

      {/* Notification Center Dropdown */}
      {showNotifs && (
        <div className="notif-center" onClick={(e) => e.stopPropagation()}>
          <h3>Notificações</h3>
          {(!notifications || notifications.length === 0) ? <p style={{ color: '#9ca3af', fontSize: '13px' }}>Sem novidades.</p> : 
            notifications.map(n => (
              <div key={n.id} className={`notif-item ${n.type}`}>
                <div className="notif-title">{n.title}</div>
                <div className="notif-msg">{n.message}</div>
                <div className="notif-time">{new Date(n.created_at).toLocaleTimeString()}</div>
              </div>
            ))
          }
        </div>
      )}

      {/* Context Menu */}
      {contextMenu.visible && (
        <div className="context-menu" style={{ top: contextMenu.y, left: contextMenu.x }} onClick={(e) => e.stopPropagation()}>
          <div className="context-item" onClick={() => { setIsPaletteOpen(true); setContextMenu({...contextMenu, visible: false}); }}><Search size={14} /> Buscar Apps (Ctrl+Shift+P)</div>
          <div className="context-divider"></div>
          <div className="context-item" onClick={() => { lockSystem(); setContextMenu({...contextMenu, visible: false}); }}><Lock size={14} /> Bloquear Tela</div>
          <div className="context-item danger" onClick={handleLogout}><Power size={14} /> Sair / Logout</div>
        </div>
      )}
    </div>
  );
}

export default function App() {
  return (
    <CloudOSProvider>
      <Desktop />
    </CloudOSProvider>
  );
}
