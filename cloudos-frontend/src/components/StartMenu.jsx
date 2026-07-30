import { useState, useEffect, useRef } from 'react';
import { Search, Power, X, ChevronLeft, FolderClosed, LayoutGrid } from 'lucide-react';

// Configuração das pastas do Windows (Mapeie os IDs conforme seu registry.jsx)
const FOLDERS = {
  'Segurança & Red Team': ['kali-hub', 'toolrunner', 'pipeline', 'findings', 'evidence', 'opsec', 'repeater', 'kalihub', 'visualpipeline'],
  'Sistema & Lab': ['terminal', 'file-manager', 'doctor', 'command-center', 'files', 'editor', 'monitor', 'events', 'appstore', 'settings'],
  'Gestão & Projetos': ['projects', 'report-builder', 'snapshot-manager', 'report', 'snapshots']
};

export default function StartMenu({ apps, onOpenApp, onClose }) {
  const [search, setSearch] = useState('');
  const [activeFolder, setActiveFolder] = useState(null);
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

  const handleOpen = (appId) => {
    onOpenApp(appId);
    onClose();
  };

  // Apps que não estão em nenhuma pasta
  const folderAppIds = Object.values(FOLDERS).flat();
  const looseApps = (apps || []).filter(app => !folderAppIds.includes(app.id));

  return (
    <div style={styles.overlay} onClick={onClose}>
      <div ref={menuRef} style={styles.menuContainer} onClick={(e) => e.stopPropagation()}>
        
        <div style={styles.header}>
          {activeFolder ? (
            <button style={styles.backBtn} onClick={() => setActiveFolder(null)}>
              <ChevronLeft size={16} color="#8b949e" />
            </button>
          ) : (
            <Search size={16} color="#8b949e" style={{ marginLeft: '4px' }} />
          )}
          <input
            type="text"
            placeholder={activeFolder ? activeFolder : "Pesquisar aplicativos..."}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={styles.searchInput}
            autoFocus
            onFocus={() => setActiveFolder(null)} // Limpa pasta ao buscar
          />
          <button onClick={onClose} style={styles.closeBtn}><X size={16} /></button>
        </div>

        <div style={styles.body}>
          {/* MODO BUSCA */}
          {search ? (
            <div style={styles.grid}>
              {filteredApps.length > 0 ? (
                filteredApps.map(app => (
                  <AppTile key={app.id} app={app} onOpen={handleOpen} />
                ))
              ) : (
                <div style={styles.empty}>Nenhum app encontrado.</div>
              )}
            </div>
          ) : 
          /* MODO DENTRO DA PASTA */
          activeFolder ? (
            <div style={styles.grid}>
              {(apps || []).filter(a => FOLDERS[activeFolder]?.includes(a.id)).map(app => (
                <AppTile key={app.id} app={app} onOpen={handleOpen} />
              ))}
            </div>
          ) : 
          /* MODO PADRÃO (PASTAS E APPS SOLTOS) */
          (
            <div style={styles.grid}>
              {/* Renderiza Pastas */}
              {Object.keys(FOLDERS).map(folderName => {
                const folderApps = (apps || []).filter(a => FOLDERS[folderName].includes(a.id));
                if (folderApps.length === 0) return null;
                return (
                  <button key={folderName} style={styles.folderBtn} onClick={() => setActiveFolder(folderName)}>
                    <div style={styles.folderIconWrapper}>
                      {folderApps.slice(0, 4).map((app, i) => {
                        const Icon = app.icon || LayoutGrid;
                        return (
                          <div key={i} style={styles.miniIcon}>
                            <Icon size={12} color="#58a6ff" />
                          </div>
                        );
                      })}
                    </div>
                    <span style={styles.appName}>{folderName}</span>
                  </button>
                );
              })}

              {/* Renderiza Apps sem pasta */}
              {looseApps.map(app => (
                <AppTile key={app.id} app={app} onOpen={handleOpen} />
              ))}
            </div>
          )}
        </div>

        <div style={styles.footer}>
          <div style={styles.userProfile}>
            <div style={styles.avatar}>A</div>
            <span style={{ fontSize: 12, color: '#c9d1d9' }}>Admin (CloudOS)</span>
          </div>
          <button style={styles.powerBtn} onClick={() => { localStorage.clear(); window.location.reload(); }} title="Desligar / Sair">
            <Power size={14} color="#f85149" />
          </button>
        </div>
      </div>
    </div>
  );
}

// Componente auxiliar para renderizar um App
function AppTile({ app, onOpen }) {
  const Icon = app.icon || LayoutGrid;
  const appName = app.name || app.title || app.id;
  return (
    <button 
      style={styles.appBtn} 
      onClick={() => onOpen(app.id)}
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
    padding: '12px 16px',
    borderBottom: '1px solid #21262d',
  },
  backBtn: {
    background: 'transparent',
    border: 'none',
    cursor: 'pointer',
    padding: '4px',
    display: 'flex',
    alignItems: 'center',
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
  // Estilos de Pasta
  folderBtn: {
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
  folderIconWrapper: {
    width: '32px',
    height: '32px',
    background: 'rgba(88, 166, 255, 0.1)',
    border: '1px solid #1f6feb',
    borderRadius: '6px',
    display: 'flex',
    flexWrap: 'wrap',
    alignContent: 'center',
    justifyContent: 'center',
    gap: '2px',
    padding: '4px',
  },
  miniIcon: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
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
  empty: {
    padding: 20,
    color: '#8b949e',
    textAlign: 'center',
    gridColumn: '1/-1',
  }
};
