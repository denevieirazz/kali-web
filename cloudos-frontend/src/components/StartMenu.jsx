import { useState, useEffect, useRef } from 'react';
import { Search, Power, X, Pin, LayoutGrid } from 'lucide-react';

export default function StartMenu({ apps, onOpenApp, onClose }) {
  const [search, setSearch] = useState('');
  const menuRef = useRef(null);

  useEffect(() => {
    const handleClickOutside = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) onClose();
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [onClose]);

  const filteredApps = (apps || []).filter(app => {
    const name = app.name || app.title || app.id || '';
    return name.toLowerCase().includes(search.toLowerCase());
  });
  
  // Apps fixados no topo (igual windows)
  const pinnedIds = ['command-center', 'kali-hub', 'toolrunner', 'file-manager', 'terminal', 'report-builder', 'pipeline', 'findings', 'kalihub', 'files', 'editor', 'projects'];
  const pinnedApps = (apps || []).filter(a => pinnedIds.includes(a.id));
  const allApps = (apps || []).filter(a => !pinnedIds.includes(a.id));

  const handleOpen = (id) => { onOpenApp(id); onClose(); };

  return (
    <div style={styles.overlay} onClick={onClose}>
      <div ref={menuRef} style={styles.menuContainer} onClick={(e) => e.stopPropagation()}>
        
        {/* Barra de Pesquisa Windows Style */}
        <div style={styles.header}>
          <Search size={16} color="#8b949e" />
          <input
            type="text"
            placeholder="Pesquisar aplicativos, ferramentas e projetos..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={styles.searchInput}
            autoFocus
          />
          <button onClick={onClose} style={styles.closeBtn}><X size={16} /></button>
        </div>

        <div style={styles.body}>
          {search ? (
            // MODO BUSCA
            <div style={styles.grid}>
              {filteredApps.length > 0 ? filteredApps.map(app => (
                <AppTile key={app.id} app={app} onOpen={handleOpen} />
              )) : <div style={styles.empty}>Nenhum app encontrado para "{search}".</div>}
            </div>
          ) : (
            // MODO PADRÃO WINDOWS
            <>
              <div style={styles.sectionHeader}>
                <span style={styles.sectionTitle}><Pin size={12} /> Fixados</span>
              </div>
              <div style={styles.grid}>
                {pinnedApps.map(app => <AppTile key={app.id} app={app} onOpen={handleOpen} />)}
              </div>

              <div style={styles.sectionHeader}>
                <span style={styles.sectionTitle}>Todos os aplicativos</span>
              </div>
              <div style={styles.grid}>
                {allApps.map(app => <AppTile key={app.id} app={app} onOpen={handleOpen} />)}
              </div>
            </>
          )}
        </div>

        <div style={styles.footer}>
          <div style={styles.userProfile}>
            <div style={styles.avatar}>A</div>
            <span style={{ fontSize: 13, color: '#c9d1d9' }}>Admin (CloudOS)</span>
          </div>
          <button style={styles.powerBtn} onClick={() => { localStorage.clear(); window.location.reload(); }} title="Desligar">
            <Power size={16} color="#f85149" />
          </button>
        </div>
      </div>
    </div>
  );
}

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
        <Icon size={22} color="#58a6ff" />
      </div>
      <span style={styles.appName}>{appName}</span>
    </button>
  );
}

const styles = {
  overlay: { position: 'absolute', bottom: '48px', left: 0, width: '100%', height: 'calc(100% - 48px)', display: 'flex', justifyContent: 'center', alignItems: 'flex-end', zIndex: 9998, background: 'transparent' },
  menuContainer: { width: '640px', height: '85%', maxHeight: '680px', background: 'rgba(22, 27, 34, 0.95)', backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)', border: '1px solid #30363d', borderRadius: '12px', boxShadow: '0 10px 40px rgba(0,0,0,0.5)', display: 'flex', flexDirection: 'column', marginBottom: '8px', overflow: 'hidden' },
  header: { display: 'flex', alignItems: 'center', gap: '10px', padding: '16px 20px', borderBottom: '1px solid #21262d' },
  searchInput: { flex: 1, background: 'transparent', border: 'none', outline: 'none', color: '#c9d1d9', fontSize: '14px' },
  closeBtn: { background: 'transparent', border: 'none', color: '#8b949e', cursor: 'pointer' },
  body: { flex: 1, padding: '20px', overflowY: 'auto' },
  sectionHeader: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px', marginTop: '8px' },
  sectionTitle: { fontSize: '13px', fontWeight: '600', color: '#c9d1d9', display: 'flex', alignItems: 'center', gap: '6px' },
  grid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(100px, 1fr))', gap: '12px', marginBottom: '24px' },
  appBtn: { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px', padding: '12px 8px', background: 'transparent', border: '1px solid transparent', borderRadius: '8px', cursor: 'pointer', transition: 'background 0.2s' },
  appIconWrapper: { width: '32px', height: '32px', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#0d1117', borderRadius: '6px', border: '1px solid #30363d' },
  appName: { color: '#c9d1d9', fontSize: '12px', textAlign: 'center', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', width: '100%' },
  footer: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 20px', borderTop: '1px solid #21262d', background: '#0d1117' },
  userProfile: { display: 'flex', alignItems: 'center', gap: '10px' },
  avatar: { width: '32px', height: '32px', borderRadius: '50%', background: '#1f6feb', color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '14px', fontWeight: 'bold' },
  powerBtn: { background: 'transparent', border: 'none', cursor: 'pointer', padding: '8px', borderRadius: '6px', display: 'flex', alignItems: 'center' },
  empty: { padding: 20, color: '#8b949e', textAlign: 'center', gridColumn: '1/-1' }
};
