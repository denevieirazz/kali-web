import { useState, useEffect } from 'react';
import { Search, LayoutGrid, Wifi, Volume2, BatteryMedium, Bell, X } from 'lucide-react';
import StartMenu from './StartMenu';

export default function Taskbar({ apps, openWindows, activeWindowId, onTaskbarClick, onCloseWindow }) {
  const [startOpen, setStartOpen] = useState(false);
  const [notifOpen, setNotifOpen] = useState(false);
  const [time, setTime] = useState(new Date());
  
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

  // Notificações Mock
  const notifications = [
    { id: 1, title: 'Nmap Scan Finalizado', desc: 'Host 192.168.0.1 está UP com 3 portas abertas.', time: '2 min atrás' },
    { id: 2, title: 'Escopo Atualizado', desc: 'Projeto Lab Pessoal ativado com sucesso.', time: '10 min atrás' }
  ];

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

      {/* PAINEL DE NOTIFICAÇÕES (Windows 11 Notification Center) */}
      {notifOpen && (
        <div style={styles.notifOverlay} onClick={() => setNotifOpen(false)}>
          <div style={styles.notifPanel} onClick={(e) => e.stopPropagation()}>
            <div style={styles.notifHeader}>
              <h3 style={styles.notifTitle}>Central de Notificações</h3>
              <button onClick={() => setNotifOpen(false)} style={styles.closeBtn}><X size={16} /></button>
            </div>
            <div style={styles.notifBody}>
              {notifications.map(n => (
                <div key={n.id} style={styles.notifCard}>
                  <div style={styles.notifCardTitle}>{n.title}</div>
                  <div style={styles.notifCardDesc}>{n.desc}</div>
                  <div style={styles.notifCardTime}>{n.time}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
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

          {/* Apps Fixados */}
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
          <button style={styles.iconBtn} onClick={() => setNotifOpen(!notifOpen)} title="Notificações">
            <Bell size={16} color="#8b949e" />
          </button>
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
  taskbarRight: { width: '150px', display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: '8px', paddingRight: '8px', color: '#c9d1d9' },
  iconBtn: { position: 'relative', width: '36px', height: '36px', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'transparent', border: 'none', borderRadius: '6px', cursor: 'pointer', transition: 'background 0.2s' },
  taskbarItemWrapper: { position: 'relative', display: 'flex', alignItems: 'center' },
  unpinBtn: { position: 'absolute', top: '2px', right: '2px', width: '12px', height: '12px', borderRadius: '50%', background: '#21262d', color: '#8b949e', border: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', opacity: 0, transition: 'opacity 0.2s' },
  separator: { width: '1px', height: '24px', background: '#30363d', margin: '0 8px' },
  clock: { fontSize: '11px', textAlign: 'right', lineHeight: 1.2, color: '#c9d1d9', marginLeft: '4px' },
  activeDot: (isActive) => ({ position: 'absolute', bottom: '3px', left: '50%', transform: 'translateX(-50%)', width: isActive ? '16px' : '6px', height: '3px', borderRadius: '3px', background: isActive ? '#58a6ff' : '#8b949e', transition: 'all 0.2s' }),
  
  // Notificações
  notifOverlay: { position: 'absolute', inset: 0, background: 'transparent', zIndex: 9998 },
  notifPanel: { position: 'absolute', bottom: '56px', right: '8px', width: '360px', height: '400px', background: 'rgba(22, 27, 34, 0.95)', backdropFilter: 'blur(16px)', border: '1px solid #30363d', borderRadius: '12px', boxShadow: '0 10px 40px rgba(0,0,0,0.5)', display: 'flex', flexDirection: 'column' },
  notifHeader: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 16px', borderBottom: '1px solid #30363d' },
  notifTitle: { margin: 0, fontSize: '14px', color: '#c9d1d9' },
  closeBtn: { background: 'transparent', border: 'none', color: '#8b949e', cursor: 'pointer' },
  notifBody: { flex: 1, overflowY: 'auto', padding: '12px', display: 'flex', flexDirection: 'column', gap: '8px' },
  notifCard: { background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '12px' },
  notifCardTitle: { fontSize: '13px', fontWeight: '600', color: '#c9d1d9', marginBottom: '4px' },
  notifCardDesc: { fontSize: '12px', color: '#8b949e', lineHeight: 1.4 },
  notifCardTime: { fontSize: '10px', color: '#484f58', marginTop: '8px', textAlign: 'right' }
};
