import { useState, useEffect, useRef } from 'react';
import { Search, Power, X, Pin, FileText, Clock, Lock, Settings as SettingsIcon, ChevronRight, LayoutGrid } from 'lucide-react';

export default function StartMenu({ apps, onOpenApp, onClose }) {
  const [search, setSearch] = useState('');
  const [contextMenu, setContextMenu] = useState(null); // {x, y, app}
  const [focusedIdx, setFocusedIdx] = useState(0);
  const menuRef = useRef(null);
  const inputRef = useRef(null);

  // Dados mockados para "Arquivos Recentes" (pode ligar ao seu DB depois)
  const recentFiles = [
    { name: 'Relatório Pentest - Cliente A.md', icon: FileText },
    { name: 'Scan_Nmap_192.168.0.1.xml', icon: FileText },
    { name: 'Hashes_Capturados.txt', icon: FileText }
  ];

  // Fixados padrão (igual Windows)
  const pinnedIds = ['command-center', 'kali-hub', 'toolrunner', 'file-manager', 'terminal', 'pipeline', 'findings', 'report-builder', 'kalihub', 'files', 'editor', 'projects'];
  const pinnedApps = (apps || []).filter(a => pinnedIds.includes(a.id));
  const allApps = (apps || []).filter(a => !pinnedIds.includes(a.id)).sort((a, b) => {
    const nameA = a.name || a.title || a.id || '';
    const nameB = b.name || b.title || b.id || '';
    return nameA.localeCompare(nameB);
  });

  // Lógica de Filtro da Busca Universal
  const filteredApps = search 
    ? (apps || []).filter(app => {
        const name = app.name || app.title || app.id || '';
        return name.toLowerCase().includes(search.toLowerCase());
      })
    : [];
  
  // Lista linear para navegação por teclado
  const flatAppList = search ? filteredApps : [...pinnedApps, ...allApps];

  // Fechar ao clicar fora
  useEffect(() => {
    const handleClickOutside = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) onClose();
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [onClose]);

  // Navegação por Teclado
  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.key === 'Escape') onClose();
      else if (e.key === 'ArrowDown') {
        e.preventDefault();
        setFocusedIdx(prev => Math.min(prev + 1, flatAppList.length - 1));
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        setFocusedIdx(prev => Math.max(prev - 1, 0));
      } else if (e.key === 'Enter' && flatAppList[focusedIdx]) {
        handleOpen(flatAppList[focusedIdx].id);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [flatAppList, focusedIdx]);

  // Foco automático no input
  useEffect(() => {
    inputRef.current?.focus();
    setFocusedIdx(0);
  }, [search]);

  const handleOpen = (id) => {
    onOpenApp(id);
    onClose();
  };

  // Arrastar Ícone (Drag & Drop)
  const handleDragStart = (e, appId) => {
    e.dataTransfer.setData('appId', appId);
    e.dataTransfer.effectAllowed = 'move';
  };

  // Menu de Contexto (Botão Direito)
  const handleContextMenu = (e, app) => {
    e.preventDefault();
    setContextMenu({ x: e.clientX, y: e.clientY, app });
  };

  useEffect(() => {
    const closeCtx = () => setContextMenu(null);
    window.addEventListener('click', closeCtx);
    return () => window.removeEventListener('click', closeCtx);
  }, []);

  return (
    <div style={styles.overlay} onClick={onClose}>
      <div 
        ref={menuRef} 
        style={styles.menuContainer} 
        onClick={(e) => e.stopPropagation()}
        className="start-menu-enter"
      >
        
        {/* HEADER - BUSCA UNIVERSAL */}
        <div style={styles.header}>
          <Search size={16} color="#8b949e" />
          <input
            ref={inputRef}
            type="text"
            placeholder="Busca Universal (Apps, Arquivos, Ferramentas...)"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={styles.searchInput}
          />
          <button onClick={onClose} style={styles.closeBtn}><X size={16} /></button>
        </div>

        {/* CORPO - ROLÁVEL */}
        <div style={styles.body}>
          
          {search ? (
            // MODO BUSCA
            <div style={styles.sectionWrapper}>
              <div style={styles.sectionTitle}>Resultados da Busca</div>
              <div style={styles.grid}>
                {filteredApps.length > 0 ? filteredApps.map(app => (
                  <AppTile 
                    key={app.id} 
                    app={app} 
                    onOpen={handleOpen}
                    onDragStart={handleDragStart}
                    onContextMenu={handleContextMenu}
                    isFocused={flatAppList[focusedIdx]?.id === app.id}
                  />
                )) : <div style={styles.emptyState}>Nenhum resultado encontrado.</div>}
              </div>
            </div>
          ) : (
            // MODO PADRÃO WINDOWS
            <>
              {/* SEÇÃO 1: FIXADOS */}
              <div style={styles.sectionWrapper}>
                <div style={styles.sectionHeader}>
                  <span style={styles.sectionTitle}><Pin size={12} /> Fixados</span>
                </div>
                <div style={styles.grid}>
                  {pinnedApps.map(app => (
                    <AppTile 
                      key={app.id} 
                      app={app} 
                      onOpen={handleOpen}
                      onDragStart={handleDragStart}
                      onContextMenu={handleContextMenu}
                      isFocused={flatAppList[focusedIdx]?.id === app.id}
                    />
                  ))}
                </div>
              </div>

              {/* SEÇÃO 2: RECOMENDADOS / ARQUIVOS RECENTES */}
              <div style={styles.sectionWrapper}>
                <div style={styles.sectionHeader}>
                  <span style={styles.sectionTitle}><Clock size={12} /> Recomendados</span>
                </div>
                <div style={styles.recentList}>
                  {recentFiles.map((file, i) => (
                    <button key={i} style={styles.recentItem} onClick={() => alert('Abrir arquivo: ' + file.name)}>
                      <file.icon size={18} color="#58a6ff" />
                      <div style={{ textAlign: 'left' }}>
                        <div style={styles.recentName}>{file.name}</div>
                        <div style={styles.recentMeta}>Editado há 2 horas</div>
                      </div>
                    </button>
                  ))}
                </div>
              </div>

              {/* SEÇÃO 3: TODOS OS APLICATIVOS */}
              <div style={styles.sectionWrapper}>
                <div style={styles.sectionHeader}>
                  <span style={styles.sectionTitle}>Todos os Aplicativos</span>
                </div>
                <div style={styles.grid}>
                  {allApps.map(app => (
                    <AppTile 
                      key={app.id} 
                      app={app} 
                      onOpen={handleOpen}
                      onDragStart={handleDragStart}
                      onContextMenu={handleContextMenu}
                      isFocused={flatAppList[focusedIdx]?.id === app.id}
                    />
                  ))}
                </div>
              </div>
            </>
          )}
        </div>

        {/* RODAPÉ - SYSTEM BAR */}
        <div style={styles.footer}>
          <div style={styles.userProfile}>
            <div style={styles.avatar}>A</div>
            <div>
              <div style={styles.userName}>Admin CloudOS</div>
              <div style={styles.userRole}>Enterprise Lab</div>
            </div>
          </div>
          <div style={styles.footerActions}>
            <button style={styles.footerBtn} title="Configurações" onClick={() => handleOpen('doctor')}><SettingsIcon size={16} /></button>
            <button style={styles.footerBtn} title="Bloquear" onClick={() => alert('Bloquear tela (em breve)')}><Lock size={16} /></button>
            <button style={styles.footerBtn} title="Desligar / Logout" onClick={() => { localStorage.clear(); window.location.reload(); }}><Power size={16} color="#f85149" /></button>
          </div>
        </div>
      </div>

      {/* MENU DE CONTEXTO FLUTUANTE */}
      {contextMenu && (
        <div style={{ ...styles.contextMenu, top: contextMenu.y, left: contextMenu.x }} onClick={(e) => e.stopPropagation()}>
          <button style={styles.ctxItem} onClick={() => { handleOpen(contextMenu.app.id); }}>
            <ChevronRight size={14} /> Abrir
          </button>
          <button style={styles.ctxItem} onClick={() => { alert('Fixado na Taskbar! (Simulação)'); setContextMenu(null); }}>
            <Pin size={14} /> Fixar na Barra de Tarefas
          </button>
          <button style={styles.ctxItem} onClick={() => { alert('Atalho criado na Área de Trabalho! (Simulação)'); setContextMenu(null); }}>
            <FileText size={14} /> Criar Atalho no Desktop
          </button>
          <div style={styles.ctxDivider}></div>
          <button style={styles.ctxItem} onClick={() => { alert('Abrindo como Admin...'); handleOpen(contextMenu.app.id); }}>
            <SettingsIcon size={14} /> Executar como Administrador
          </button>
        </div>
      )}

      {/* ANIMAÇÕES CSS */}
      <style>{`
        @keyframes slideUpFade {
          from { opacity: 0; transform: translateY(20px) scale(0.98); }
          to { opacity: 1; transform: translateY(0) scale(1); }
        }
        .start-menu-enter { animation: slideUpFade 0.2s cubic-bezier(0.16, 1, 0.3, 1); }
      `}</style>
    </div>
  );
}

// Componente auxiliar para os Ícones dos Apps
function AppTile({ app, onOpen, onDragStart, onContextMenu, isFocused }) {
  const Icon = app.icon || LayoutGrid;
  const appName = app.name || app.title || app.id;
  return (
    <button
      style={{
        ...styles.appBtn,
        background: isFocused ? 'rgba(88, 166, 255, 0.15)' : 'transparent',
        border: isFocused ? '1px solid #58a6ff' : '1px solid transparent',
      }}
      onClick={() => onOpen(app.id)}
      draggable
      onDragStart={(e) => onDragStart(e, app.id)}
      onContextMenu={(e) => onContextMenu(e, app)}
    >
      <div style={styles.appIconWrapper}>
        <Icon size={22} color="#58a6ff" />
      </div>
      <span style={styles.appName}>{appName}</span>
    </button>
  );
}

const styles = {
  overlay: { position: 'absolute', bottom: '48px', left: 0, width: '100%', height: 'calc(100% - 48px)', display: 'flex', justifyContent: 'center', alignItems: 'flex-end', zIndex: 9998, background: 'transparent', pointerEvents: 'auto' },
  menuContainer: { width: '640px', height: '85%', maxHeight: '680px', background: 'rgba(22, 27, 34, 0.85)', backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)', border: '1px solid #30363d', borderRadius: '12px', boxShadow: '0 10px 40px rgba(0,0,0,0.5)', display: 'flex', flexDirection: 'column', marginBottom: '8px', overflow: 'hidden' },
  
  header: { display: 'flex', alignItems: 'center', gap: '10px', padding: '16px 20px', borderBottom: '1px solid #21262d', background: 'rgba(13, 17, 23, 0.5)' },
  searchInput: { flex: 1, background: 'transparent', border: 'none', outline: 'none', color: '#c9d1d9', fontSize: '14px', fontFamily: 'Inter, sans-serif' },
  closeBtn: { background: 'transparent', border: 'none', color: '#8b949e', cursor: 'pointer', padding: '4px', borderRadius: '4px', display: 'flex', alignItems: 'center' },
  
  body: { flex: 1, overflowY: 'auto', padding: '20px' },
  bodyScrollbar: { scrollbarWidth: 'thin', scrollbarColor: '#30363d transparent' },
  
  sectionWrapper: { marginBottom: '24px' },
  sectionHeader: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px' },
  sectionTitle: { fontSize: '13px', fontWeight: '600', color: '#c9d1d9', display: 'flex', alignItems: 'center', gap: '6px' },
  
  grid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(100px, 1fr))', gap: '12px' },
  appBtn: { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px', padding: '12px 8px', borderRadius: '8px', cursor: 'pointer', transition: 'background 0.15s, border 0.15s' },
  appIconWrapper: { width: '32px', height: '32px', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#0d1117', borderRadius: '6px', border: '1px solid #30363d' },
  appName: { color: '#c9d1d9', fontSize: '12px', textAlign: 'center', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', width: '100%' },
  
  recentList: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' },
  recentItem: { display: 'flex', alignItems: 'center', gap: '12px', padding: '10px', background: 'rgba(13, 17, 23, 0.5)', border: '1px solid #21262d', borderRadius: '6px', cursor: 'pointer', transition: 'background 0.15s' },
  recentName: { fontSize: '12px', color: '#c9d1d9', fontWeight: '500' },
  recentMeta: { fontSize: '10px', color: '#8b949e', marginTop: '2px' },
  
  footer: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 20px', borderTop: '1px solid #21262d', background: 'rgba(13, 17, 23, 0.7)' },
  userProfile: { display: 'flex', alignItems: 'center', gap: '10px' },
  avatar: { width: '32px', height: '32px', borderRadius: '50%', background: '#1f6feb', color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '14px', fontWeight: 'bold' },
  userName: { fontSize: '13px', color: '#c9d1d9', fontWeight: '600' },
  userRole: { fontSize: '11px', color: '#8b949e' },
  footerActions: { display: 'flex', gap: '4px' },
  footerBtn: { background: 'transparent', border: 'none', cursor: 'pointer', padding: '8px', borderRadius: '6px', color: '#c9d1d9', display: 'flex', alignItems: 'center', transition: 'background 0.15s' },
  
  // Menu Contexto
  contextMenu: { position: 'fixed', background: 'rgba(22, 27, 34, 0.95)', backdropFilter: 'blur(16px)', border: '1px solid #30363d', borderRadius: '8px', padding: '4px', boxShadow: '0 4px 12px rgba(0,0,0,0.5)', zIndex: 10000, minWidth: '220px' },
  ctxItem: { display: 'flex', alignItems: 'center', gap: '8px', width: '100%', padding: '8px 12px', background: 'transparent', border: 'none', color: '#c9d1d9', fontSize: '13px', cursor: 'pointer', borderRadius: '4px', textAlign: 'left' },
  ctxDivider: { height: '1px', background: '#30363d', margin: '4px 0' },
  
  emptyState: { padding: 20, color: '#8b949e', textAlign: 'center', gridColumn: '1/-1' }
};
