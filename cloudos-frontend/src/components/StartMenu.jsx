import { useState, useEffect, useRef } from 'react';
import { Search, Power, Lock, X } from 'lucide-react';

export default function StartMenu({ apps = [], onOpenApp, onClose, onLogout, onLock }) {
  const [search, setSearch] = useState('');
  const menuRef = useRef(null);

  // Fecha o menu ao clicar fora (no desktop)
  useEffect(() => {
    const handleClickOutside = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) {
        onClose();
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [onClose]);

  const filteredApps = apps.filter(app => {
    const name = app.title || app.name || '';
    return name.toLowerCase().includes(search.toLowerCase());
  });

  const handleOpen = (appId) => {
    onOpenApp(appId);
    onClose();
  };

  return (
    <div style={styles.overlay} className="startmenu-overlay" onClick={(e) => e.stopPropagation()}>
      <div ref={menuRef} style={styles.menuContainer} className="startmenu-container">
        
        {/* Mobile Header */}
        <div className="startmenu-mobile-header">
          <span style={{ fontWeight: 600, fontSize: 16 }}>CloudOS</span>
          <button onClick={onClose} style={styles.closeBtn}><X size={20} /></button>
        </div>

        {/* Search Bar */}
        <div style={styles.searchContainer}>
          <Search size={16} color="#8b949e" />
          <input
            type="text"
            placeholder="Buscar apps..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={styles.searchInput}
            autoFocus
          />
        </div>

        {/* Apps Grid */}
        <div style={styles.appsGrid}>
          {filteredApps.length > 0 ? (
            filteredApps.map(app => {
              const Icon = app.icon;
              return (
                <button 
                  key={app.id} 
                  style={styles.appBtn} 
                  onClick={() => handleOpen(app.id)}
                  className="app-btn-hover"
                >
                  <Icon size={28} color="#58a6ff" />
                  <span style={styles.appName}>{app.title || app.name}</span>
                </button>
              );
            })
          ) : (
            <div style={{ padding: 20, color: '#8b949e', gridColumn: '1 / -1', textAlign: 'center' }}>
              Nenhum app encontrado.
            </div>
          )}
        </div>

        {/* Footer / Power Options */}
        <div style={styles.footer}>
          <div style={styles.userProfile}>
            <div style={styles.avatar}>C</div>
            <span style={{ fontSize: 13, fontWeight: 500 }}>CloudOS User</span>
          </div>
          <div style={styles.powerBtns}>
            <button style={styles.iconBtn} title="Bloquear Tela" onClick={onLock}>
              <Lock size={16} />
            </button>
            <button style={styles.iconBtn} title="Desligar / Logout" onClick={onLogout}>
              <Power size={16} color="#f85149" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

const styles = {
  overlay: {
    position: 'absolute',
    bottom: '60px',
    left: 0,
    width: '100%',
    height: 'calc(100% - 60px)',
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'flex-end',
    zIndex: 9998,
    pointerEvents: 'none',
  },
  menuContainer: {
    width: '100%',
    maxWidth: '640px',
    height: '100%',
    maxHeight: '580px',
    background: 'rgba(13, 17, 23, 0.88)',
    backdropFilter: 'blur(16px)',
    WebkitBackdropFilter: 'blur(16px)',
    border: '1px solid #30363d',
    borderRadius: '12px',
    boxShadow: '0 10px 40px rgba(0,0,0,0.5)',
    display: 'flex',
    flexDirection: 'column',
    padding: '24px',
    marginBottom: '8px',
    pointerEvents: 'auto',
    overflow: 'hidden',
  },
  searchContainer: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    background: '#0d1117',
    border: '1px solid #30363d',
    borderRadius: '8px',
    padding: '10px 12px',
    marginBottom: '20px',
  },
  searchInput: {
    flex: 1,
    background: 'transparent',
    border: 'none',
    outline: 'none',
    color: '#c9d1d9',
    fontSize: '14px',
    fontFamily: 'inherit',
  },
  appsGrid: {
    flex: 1,
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fill, minmax(90px, 1fr))',
    gap: '12px',
    overflowY: 'auto',
    alignContent: 'start',
  },
  appBtn: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '8px',
    padding: '16px 8px',
    background: 'transparent',
    border: '1px solid transparent',
    borderRadius: '8px',
    cursor: 'pointer',
    transition: 'all 0.2s',
  },
  appName: {
    color: '#c9d1d9',
    fontSize: '12px',
    textAlign: 'center',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    width: '100%',
  },
  footer: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingTop: '16px',
    marginTop: '16px',
    borderTop: '1px solid #30363d',
  },
  userProfile: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
    color: '#c9d1d9',
  },
  avatar: {
    width: '32px',
    height: '32px',
    borderRadius: '50%',
    background: '#58a6ff',
    color: '#0d1117',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontWeight: 'bold',
    fontSize: '14px',
  },
  powerBtns: {
    display: 'flex',
    gap: '8px',
  },
  iconBtn: {
    background: '#21262d',
    border: 'none',
    color: '#c9d1d9',
    width: '36px',
    height: '36px',
    borderRadius: '6px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    cursor: 'pointer',
  },
  closeBtn: {
    background: 'transparent',
    border: 'none',
    color: '#c9d1d9',
    cursor: 'pointer',
    padding: '4px',
  }
};
