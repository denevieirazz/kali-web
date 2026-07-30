import { useState, useEffect, useRef } from 'react';
import { Search, Power, X, LayoutGrid } from 'lucide-react';

export default function StartMenu({ apps, onOpenApp, onClose }) {
  const [search, setSearch] = useState('');
  const menuRef = useRef(null);

  useEffect(() => {
    const handleClickOutside = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) {
        onClose();
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [onClose]);

  const filteredApps = (apps || []).filter(app => {
    const name = app.name || app.title || app.id || '';
    return name.toLowerCase().includes(search.toLowerCase());
  });

  return (
    <div style={styles.overlay} onClick={onClose}>
      <div ref={menuRef} style={styles.menuContainer} onClick={(e) => e.stopPropagation()}>
        
        <div style={styles.header}>
          <Search size={16} color="#8b949e" />
          <input
            type="text"
            placeholder="Pesquisar aplicativos..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={styles.searchInput}
            autoFocus
          />
          <button onClick={onClose} style={styles.closeBtn}><X size={16} /></button>
        </div>

        <div style={styles.body}>
          <h3 style={styles.sectionTitle}>Todos os Aplicativos</h3>
          <div style={styles.grid}>
            {filteredApps.length > 0 ? (
              filteredApps.map(app => {
                const Icon = app.icon || LayoutGrid;
                const appName = app.name || app.title || app.id;
                return (
                  <button 
                    key={app.id} 
                    style={styles.appBtn} 
                    onClick={() => onOpenApp(app.id)}
                    draggable
                    onDragStart={(e) => {
                      e.dataTransfer.setData('appId', app.id);
                      e.dataTransfer.effectAllowed = 'move';
                    }}
                  >
                    <div style={styles.appIconWrapper}>
                      <Icon size={20} color="#58a6ff" />
                    </div>
                    <span style={styles.appName}>{appName}</span>
                  </button>
                );
              })
            ) : (
              <div style={{ padding: 20, color: '#8b949e', textAlign: 'center', gridColumn: '1/-1' }}>
                Nenhum app encontrado.
              </div>
            )}
          </div>
        </div>

        <div style={styles.footer}>
          <div style={styles.userProfile}>
            <div style={styles.avatar}>A</div>
            <span style={{ fontSize: 12, color: '#c9d1d9' }}>Admin (CloudOS)</span>
          </div>
          <button style={styles.powerBtn} onClick={() => { localStorage.clear(); window.location.reload(); }} title="Sair / Shutdown">
            <Power size={14} color="#f85149" />
          </button>
        </div>
      </div>
    </div>
  );
}

const styles = {
  overlay: {
    position: 'absolute',
    bottom: '48px',
    left: 0,
    width: '100%',
    height: 'calc(100% - 48px)',
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'flex-end',
    zIndex: 9998,
    background: 'transparent',
  },
  menuContainer: {
    width: '600px',
    height: '80%',
    maxHeight: '600px',
    background: 'rgba(22, 27, 34, 0.95)',
    backdropFilter: 'blur(16px)',
    WebkitBackdropFilter: 'blur(16px)',
    border: '1px solid #30363d',
    borderRadius: '12px',
    boxShadow: '0 10px 40px rgba(0,0,0,0.5)',
    display: 'flex',
    flexDirection: 'column',
    marginBottom: '8px',
    overflow: 'hidden',
  },
  header: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
    padding: '16px 20px',
    borderBottom: '1px solid #21262d',
  },
  searchInput: {
    flex: 1,
    background: 'transparent',
    border: 'none',
    outline: 'none',
    color: '#c9d1d9',
    fontSize: '14px',
  },
  closeBtn: {
    background: 'transparent',
    border: 'none',
    color: '#8b949e',
    cursor: 'pointer',
  },
  body: {
    flex: 1,
    padding: '20px',
    overflowY: 'auto',
  },
  sectionTitle: {
    fontSize: '12px',
    color: '#8b949e',
    margin: '0 0 16px 8px',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
  },
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fill, minmax(100px, 1fr))',
    gap: '12px',
  },
  appBtn: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: '8px',
    padding: '12px 8px',
    background: 'transparent',
    border: '1px solid transparent',
    borderRadius: '8px',
    cursor: 'pointer',
    transition: 'all 0.2s',
  },
  appIconWrapper: {
    width: '32px',
    height: '32px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    background: '#0d1117',
    borderRadius: '6px',
    border: '1px solid #30363d',
  },
  appName: {
    color: '#c9d1d9',
    fontSize: '11px',
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
    padding: '12px 20px',
    borderTop: '1px solid #21262d',
    background: '#0d1117',
  },
  userProfile: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
  },
  avatar: {
    width: '28px',
    height: '28px',
    borderRadius: '50%',
    background: '#1f6feb',
    color: '#fff',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: '12px',
    fontWeight: 'bold',
  },
  powerBtn: {
    background: 'transparent',
    border: 'none',
    cursor: 'pointer',
    padding: '8px',
    borderRadius: '6px',
  },
};
