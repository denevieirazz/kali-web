import { useState, useEffect } from 'react';
import { Search, Wifi, Volume2, Battery, Bell, Power, Lock, LayoutGrid } from 'lucide-react';
import Window from './Window';
import { AppList, AppRegistry } from './registry';
import BootScreen from './BootScreen';
import LoginScreen from './LoginScreen';
import { CommandPalette } from './components/CommandPalette';
import SpotlightSearch from './components/SpotlightSearch';
import Taskbar from './components/Taskbar';
import DesktopArea from './components/Desktop';
import { CloudOSProvider, useCloudOS } from './store/CloudOSContext';
import { useWindowPersistence } from './hooks/useWindowPersistence';
import { initNotifications } from './services/notificationService';

function Desktop() {
  const { settings, setBg, isLocked, lockSystem, notifications, fetchNotifications, pinnedApps } = useCloudOS();
  const [booting, setBooting] = useState(true);
  const [isAuthenticated, setIsAuthenticated] = useState(() => !!localStorage.getItem('cloudos_token'));
  const [windows, setWindows] = useState([]);
  const [zIndex, setZIndex] = useState(100);

  // Ativa a persistência de janelas salvas
  useWindowPersistence(windows, setWindows);

  // Inicializa serviço de notificações HTML5 do navegador
  useEffect(() => {
    initNotifications();
  }, []);
  const [startOpen, setStartOpen] = useState(false);
  const [time, setTime] = useState(new Date());
  const [contextMenu, setContextMenu] = useState({ visible: false, x: 0, y: 0 });
  const [isPaletteOpen, setIsPaletteOpen] = useState(false);
  const [showNotifs, setShowNotifs] = useState(false);
  const [isMobile, setIsMobile] = useState(() => window.innerWidth < 768);
  const [activeWindowId, setActiveWindowId] = useState(null);

  useEffect(() => {
    const handleResize = () => setIsMobile(window.innerWidth < 768);
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  useEffect(() => {
    const timer = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  useEffect(() => {
    const handleKey = (e) => {
      if ((e.ctrlKey || e.metaKey) && (e.key === 'k' || e.key === 'K')) {
        e.preventDefault();
        setIsPaletteOpen(prev => !prev);
      }
      if (e.ctrlKey && e.code === 'Space') {
        e.preventDefault();
        setIsPaletteOpen(prev => !prev);
      }
      if (e.key === 'Escape') {
        setIsPaletteOpen(false);
        setStartOpen(false);
      }
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, []);

  const openApp = (appId, payload = null) => {
    const existing = windows.find(w => w.appId === appId);
    if (existing) return focusWindow(existing.id);
    const w = isMobile ? window.innerWidth : Math.min(800, window.innerWidth - 100);
    const h = isMobile ? window.innerHeight - 50 : Math.min(550, window.innerHeight - 100);
    const newId = Date.now();
    setWindows(prev => [...prev, { id: newId, appId, x: isMobile ? 0 : 50 + Math.random()*50, y: isMobile ? 0 : 50, w, h, z: zIndex + 1, payload }]);
    setActiveWindowId(newId);
    setZIndex(prev => prev + 1);
    setStartOpen(false);
  };

  const closeApp = (id) => {
    setWindows(prev => prev.filter(w => w.id !== id));
    if (activeWindowId === id) setActiveWindowId(null);
  };

  const focusWindow = (id) => {
    setWindows(prev => prev.map(w => w.id === id ? { ...w, z: zIndex + 1 } : w));
    setActiveWindowId(id);
    setZIndex(prev => prev + 1);
  };

  const handleTaskbarClick = (target) => {
    if (typeof target === 'number') {
      focusWindow(target);
    } else if (typeof target === 'string') {
      openApp(target);
    }
  };

  const handleLogout = () => {
    localStorage.removeItem('cloudos_token');
    window.location.reload();
  };

  const wallpaperUrl = settings?.wallpaper || 'linear-gradient(135deg, #0f0c29, #302b63, #24243e)';

  if (booting) return <BootScreen onBootComplete={() => setBooting(false)} />;
  if (!isAuthenticated) return <LoginScreen onLogin={() => setIsAuthenticated(true)} />;
  if (isLocked) return <LoginScreen onLogin={() => window.location.reload()} isLockScreen={true} />;

  return (
    <div 
      className="desktop" 
      style={{ width: '100vw', height: '100vh', overflow: 'hidden', position: 'relative', background: wallpaperUrl.startsWith('http') ? `url(${wallpaperUrl}) center/cover no-repeat` : wallpaperUrl }} 
      onClick={() => { setShowNotifs(false); setStartOpen(false); }}
    >
      {/* 1. Área de Trabalho com Widgets e Atalhos Arrastáveis */}
      <DesktopArea apps={AppList} openWindows={windows} onOpenApp={openApp} />

      <CommandPalette 
        isOpen={isPaletteOpen} 
        onClose={() => setIsPaletteOpen(false)} 
        openApp={openApp}
        actions={{ togglePalette: () => setIsPaletteOpen(!isPaletteOpen), lock: lockSystem }}
      />

      <SpotlightSearch
        isOpen={isPaletteOpen}
        onClose={() => setIsPaletteOpen(false)}
        onLaunchApp={openApp}
      />

      {/* Windows */}
      {windows.map(win => {
        const appConfig = AppRegistry[win.appId];
        if (!appConfig) return null;
        const AppComp = appConfig.Component;
        return (
          <Window 
            key={win.id} 
            win={{ ...win, title: appConfig.title, icon: appConfig.icon }} 
            isMobile={isMobile} 
            onClose={() => closeApp(win.id)} 
            onFocus={() => focusWindow(win.id)}
            onPositionChange={(pos) => {
              setWindows(prev => prev.map(w => w.id === win.id ? { ...w, ...pos } : w));
            }}
          >
            <AppComp 
              payload={win.payload} 
              setPayload={(newPayload) => setWindows(prev => prev.map(w => w.id === win.id ? { ...w, payload: newPayload } : w))} 
              openApp={openApp} 
              setBg={setBg} 
            />
          </Window>
        );
      })}

      {/* Taskbar Windows 11 */}
      <Taskbar 
        apps={AppList} 
        openWindows={windows} 
        activeWindowId={activeWindowId}
        onTaskbarClick={handleTaskbarClick}
        onCloseWindow={closeApp}
      />
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
