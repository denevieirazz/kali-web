import { useState, useEffect } from 'react';
import { Cpu, Activity, Bug, Briefcase, X, LayoutGrid } from 'lucide-react';

export default function Desktop({ apps, openWindows, onOpenApp }) {
  const [shortcuts, setShortcuts] = useState(() => {
    // Carrega atalhos salvos localmente
    const saved = localStorage.getItem('cloudos_desktop_shortcuts');
    return saved ? JSON.parse(saved) : ['command-center', 'kali-hub', 'file-manager', 'kalihub', 'files', 'terminal'];
  });

  const [time, setTime] = useState(new Date());
  const [sysInfo, setSysInfo] = useState({ cpu: 0, mem: 0 });

  // Atualiza relógio
  useEffect(() => {
    const t = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(t);
  }, []);

  // Simulação de monitor do sistema
  useEffect(() => {
    const t = setInterval(() => {
      setSysInfo({
        cpu: Math.floor(Math.random() * 30) + 10,
        mem: Math.floor(Math.random() * 40) + 20
      });
    }, 2000);
    return () => clearInterval(t);
  }, []);

  const handleDrop = (e) => {
    e.preventDefault();
    const appId = e.dataTransfer.getData('appId');
    if (appId && !shortcuts.includes(appId)) {
      const newShortcuts = [...shortcuts, appId];
      setShortcuts(newShortcuts);
      localStorage.setItem('cloudos_desktop_shortcuts', JSON.stringify(newShortcuts));
    }
  };

  const removeShortcut = (appId) => {
    const newShortcuts = shortcuts.filter(id => id !== appId);
    setShortcuts(newShortcuts);
    localStorage.setItem('cloudos_desktop_shortcuts', JSON.stringify(newShortcuts));
  };

  return (
    <div 
      style={styles.desktopBg}
      onDragOver={(e) => e.preventDefault()}
      onDrop={handleDrop}
    >
      {/* WIDGETS ESTILO MAC (Lado Superior Direito) */}
      <div style={styles.widgetsContainer}>
        {/* Widget Relógio */}
        <div style={styles.widget}>
          <div style={styles.clockTime}>{time.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</div>
          <div style={styles.clockDate}>{time.toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'short' })}</div>
        </div>

        {/* Widget Sistema */}
        <div style={styles.widget}>
          <div style={styles.widgetHeader}><Cpu size={12} color="#58a6ff" /> System Monitor</div>
          <div style={styles.metricRow}>
            <span style={styles.metricLabel}>CPU</span>
            <div style={styles.barBg}><div style={{...styles.barFill, width: `${sysInfo.cpu}%`, background: '#3fb950'}}></div></div>
            <span style={styles.metricVal}>{sysInfo.cpu}%</span>
          </div>
          <div style={styles.metricRow}>
            <span style={styles.metricLabel}>RAM</span>
            <div style={styles.barBg}><div style={{...styles.barFill, width: `${sysInfo.mem}%`, background: '#58a6ff'}}></div></div>
            <span style={styles.metricVal}>{sysInfo.mem}%</span>
          </div>
        </div>
      </div>

      {/* ATALHOS DA ÁREA DE TRABALHO (Lado Superior Esquerdo) */}
      <div style={styles.shortcutsContainer}>
        {shortcuts.map(id => {
          const app = (apps || []).find(a => a.id === id);
          if (!app) return null;
          const Icon = app.icon || LayoutGrid;
          const appName = app.name || app.title || app.id;
          return (
            <div key={id} style={styles.shortcutWrapper} onDoubleClick={() => onOpenApp && onOpenApp(id)}>
              <button style={styles.shortcutBtn} className="desktop-icon">
                <Icon size={28} color="#c9d1d9" />
              </button>
              <div style={styles.shortcutName}>
                {appName}
                <X size={10} style={styles.removeIcon} onClick={(e) => { e.stopPropagation(); removeShortcut(id); }} />
              </div>
            </div>
          );
        })}
        {shortcuts.length === 0 && (
          <div style={styles.emptyDesktop}>
            Arraste ícones do Menu Iniciar para cá
          </div>
        )}
      </div>

      <style>{`
        .desktop-icon:hover { background: rgba(88, 166, 255, 0.2); }
      `}</style>
    </div>
  );
}

const styles = {
  desktopBg: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: '48px',
    background: 'linear-gradient(135deg, #0d1117 0%, #010409 100%)',
    overflow: 'hidden',
    zIndex: 0,
  },
  widgetsContainer: {
    position: 'absolute',
    top: '16px',
    right: '16px',
    display: 'flex',
    flexDirection: 'column',
    gap: '12px',
    width: '220px',
    zIndex: 1,
  },
  widget: {
    background: 'rgba(22, 27, 34, 0.7)',
    backdropFilter: 'blur(12px)',
    WebkitBackdropFilter: 'blur(12px)',
    border: '1px solid #30363d',
    borderRadius: '12px',
    padding: '12px 16px',
    color: '#c9d1d9',
    boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
  },
  clockTime: { fontSize: '32px', fontWeight: 700, textAlign: 'center', color: '#fff' },
  clockDate: { fontSize: '12px', textAlign: 'center', color: '#8b949e', textTransform: 'capitalize' },
  widgetHeader: { fontSize: '11px', color: '#8b949e', marginBottom: '8px', display: 'flex', alignItems: 'center', gap: '6px' },
  metricRow: { display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '6px' },
  metricLabel: { fontSize: '10px', width: '25px', color: '#8b949e' },
  barBg: { flex: 1, height: '6px', background: '#0d1117', borderRadius: '3px', overflow: 'hidden' },
  barFill: { height: '100%', transition: 'width 0.5s ease' },
  metricVal: { fontSize: '10px', width: '30px', textAlign: 'right', color: '#c9d1d9' },

  shortcutsContainer: {
    position: 'absolute',
    top: '16px',
    left: '16px',
    display: 'flex',
    flexDirection: 'column',
    gap: '16px',
    zIndex: 1,
  },
  shortcutWrapper: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    width: '80px',
    position: 'relative',
  },
  shortcutBtn: {
    width: '48px',
    height: '48px',
    background: 'rgba(22, 27, 34, 0.6)',
    border: '1px solid #30363d',
    borderRadius: '10px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    cursor: 'pointer',
    transition: 'background 0.2s',
  },
  shortcutName: {
    fontSize: '11px',
    color: '#c9d1d9',
    marginTop: '4px',
    textAlign: 'center',
    textShadow: '0 1px 2px rgba(0,0,0,0.8)',
    display: 'flex',
    alignItems: 'center',
    gap: '4px',
  },
  removeIcon: {
    cursor: 'pointer',
    color: '#f85149',
    background: 'rgba(0,0,0,0.5)',
    borderRadius: '50%',
    padding: '1px',
  },
  emptyDesktop: {
    color: '#8b949e',
    fontSize: '12px',
    fontStyle: 'italic',
    marginTop: '20px',
  }
};
