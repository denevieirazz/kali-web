import { useState, useEffect } from 'react';
import { Search, LayoutGrid, Wifi, Volume2, BatteryMedium, X } from 'lucide-react';
import StartMenu from './StartMenu';

export default function Taskbar({ apps, openWindows, activeWindowId, onTaskbarClick, onCloseWindow }) {
  const [startOpen, setStartOpen] = useState(false);
  const [time, setTime] = useState(new Date());
  
  // Estado dinâmico de apps fixados
  const [pinnedAppIds, setPinnedAppIds] = useState(() => {
    const saved = localStorage.getItem('cloudos_taskbar_pinned');
    return saved ? JSON.parse(saved) : ['command-center', 'kali-hub', 'toolrunner', 'file-manager', 'terminal', 'report-builder', 'kalihub', 'files', 'editor', 'projects'];
  });

  useEffect(() => {
    const timer = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  const pinnedApps = (apps || []).filter(app => pinnedAppIds.includes(app.id));
  const openApps = (apps || []).filter(app => 
    (openWindows || []).some(w => w.appId === app.id) && !pinnedAppIds.includes(app.id)
  );

  const handleClick = (app) => {
    if (!app) return;
    const win = (openWindows || []).find(w => w.appId === app.id);
    if (win) onTaskbarClick(win.id);
    else onTaskbarClick(app.id);
  };

  // Lógica de Drop na Taskbar
  const handleDrop = (e) => {
    e.preventDefault();
    const appId = e.dataTransfer.getData('appId');
    if (appId && !pinnedAppIds.includes(appId)) {
      const newPinned = [...pinnedAppIds, appId];
      setPinnedAppIds(newPinned);
      localStorage.setItem('cloudos_taskbar_pinned', JSON.stringify(newPinned));
    }
  };

  const unpinApp = (appId) => {
    const newPinned = pinnedAppIds.filter(id => id !== appId);
    setPinnedAppIds(newPinned);
    localStorage.setItem('cloudos_taskbar_pinned', JSON.stringify(newPinned));
  };

  return (
    <>
      {startOpen && (
        <StartMenu 
          apps={apps || []} 
          onOpenApp={(id) => { 
            const app = (apps || []).find(a => a.id === id);
            if (app) handleClick(app); 
            setStartOpen(false); 
          }} 
          onClose={() => setStartOpen(false)} 
        />
      )}

      <div 
        style={styles.taskbar}
        onDragOver={(e) => e.preventDefault()}
        onDrop={handleDrop}
      >
        <div style={styles.taskbarSide}></div>

        <div style={styles.taskbarCenter}>
          <button style={styles.iconBtn} onClick={() => setStartOpen(!startOpen)} className={startOpen ? 'active' : ''} title="Menu Iniciar">
            <LayoutGrid size={20} color="#c9d1d9" />
          </button>

          <button style={styles.iconBtn} onClick={() => alert('Busca Universal (Ctrl+K)')} title="Buscar">
            <Search size={18} color="#8b949e" />
          </button>

          {/* Apps Fixados (com opção de desfixar) */}
          {pinnedApps.map(app => {
            const Icon = app.icon || LayoutGrid;
            const appName = app.name || app.title || app.id;
            const isOpen = (openWindows || []).some(w => w.appId === app.id);
            const isActive = (openWindows || []).find(w => w.appId === app.id)?.id === activeWindowId;
            return (
              <div key={app.id} style={styles.taskbarItemWrapper} className="taskbar-item-hover">
                <button style={styles.iconBtn} onClick={() => handleClick(app)} title={appName}>
                  <Icon size={20} color={isOpen ? '#58a6ff' : '#c9d1d9'} />
                  {isOpen && <span style={styles.activeDot(isActive)}></span>}
                </button>
                <button style={styles.unpinBtn} className="unpin-btn" onClick={() => unpinApp(app.id)} title="Desafixar">
                  <X size={8} />
                </button>
              </div>
            );
          })}

          {openApps.length > 0 && <div style={styles.separator}></div>}

          {/* Apps Abertos não fixados */}
          {openApps.map(app => {
            const Icon = app.icon || LayoutGrid;
            const appName = app.name || app.title || app.id;
            const win = (openWindows || []).find(w => w.appId === app.id);
            const isActive = win?.id === activeWindowId;
            return (
              <button key={app.id} style={styles.iconBtn} onClick={() => onTaskbarClick(win.id)} title={appName}>
                <Icon size={20} color="#58a6ff" />
                {isActive && <span style={styles.activeDot(true)}></span>}
              </button>
            );
          })}
        </div>

        <div style={styles.taskbarRight}>
          <Wifi size={14} color="#8b949e" />
          <Volume2 size={14} color="#8b949e" />
          <BatteryMedium size={16} color="#8b949e" />
          <div style={styles.clock}>
            <div>{time.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</div>
            <div style={{ fontSize: 10 }}>{time.toLocaleDateString()}</div>
          </div>
        </div>
      </div>

      <style>{`
        .taskbar-item-hover:hover .unpin-btn { opacity: 1 !important; }
      `}</style>
    </>
  );
}

const styles = {
  taskbar: { position: 'absolute', bottom: 0, left: 0, right: 0, height: '48px', background: 'rgba(13, 17, 23, 0.85)', backdropFilter: 'blur(12px)', WebkitBackdropFilter: 'blur(12px)', borderTop: '1px solid #30363d', display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 8px', zIndex: 9999, boxShadow: '0 -4px 12px rgba(0,0,0,0.3)' },
  taskbarSide: { width: '150px' },
  taskbarCenter: { display: 'flex', alignItems: 'center', gap: '4px' },
  taskbarRight: { width: '150px', display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: '12px', paddingRight: '8px', color: '#c9d1d9' },
  iconBtn: { position: 'relative', width: '40px', height: '40px', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'transparent', border: 'none', borderRadius: '6px', cursor: 'pointer', transition: 'background 0.2s' },
  taskbarItemWrapper: { position: 'relative', display: 'flex', alignItems: 'center' },
  unpinBtn: { position: 'absolute', top: '2px', right: '2px', width: '12px', height: '12px', borderRadius: '50%', background: '#21262d', color: '#8b949e', border: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', opacity: 0, transition: 'opacity 0.2s' },
  separator: { width: '1px', height: '24px', background: '#30363d', margin: '0 8px' },
  clock: { fontSize: '11px', textAlign: 'right', lineHeight: 1.2, color: '#c9d1d9', marginLeft: '4px' },
  activeDot: (isActive) => ({ position: 'absolute', bottom: '3px', left: '50%', transform: 'translateX(-50%)', width: isActive ? '16px' : '6px', height: '3px', borderRadius: '3px', background: isActive ? '#58a6ff' : '#8b949e', transition: 'all 0.2s' }),
};
