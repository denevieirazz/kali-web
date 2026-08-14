import { memo, useEffect, useMemo, useRef, useState } from 'react';
import { useSystem } from '../../stores/systemStore';
import { useWindowManager } from '../../stores/windowManager';
import { useProcessManager } from '../../stores/processManager';
import { useContextMenuStore } from '../../stores/contextMenuStore';
import { useAppRegistry } from '../../core/appRegistry';
import './StartMenu.css';

type View = 'home' | 'all' | 'running';
type App = { id:string; name:string; icon:string; defaultWidth?:number; defaultHeight?:number; minWidth?:number; minHeight?:number; isResizable?:boolean; binaryPath?:string };

function StartMenu() {
  const { isStartMenuOpen, closeStartMenu, currentUser } = useSystem();
  const windows = useWindowManager(s => s.windows.filter(w => !w.isSystem));
  const openWindow = useWindowManager(s => s.openWindow);
  const closeWindow = useWindowManager(s => s.closeWindow);
  const minimizeWindow = useWindowManager(s => s.minimizeWindow);
  const maximizeWindow = useWindowManager(s => s.maximizeWindow);
  const restoreWindow = useWindowManager(s => s.restoreWindow);
  const focusWindow = useWindowManager(s => s.focusWindow);
  const createProcess = useProcessManager(s => s.createProcess);
  const openContextMenu = useContextMenuStore(s => s.openContextMenu);
  const apps = useAppRegistry((s: any) => s.apps) as Record<string, App>;
  const [view, setView] = useState<View>('home');
  const [query, setQuery] = useState('');
  const menuRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const appList = useMemo(() => Object.values(apps), [apps]);
  const filtered = useMemo(() => {
    const value = query.trim().toLocaleLowerCase('pt-BR');
    return value ? appList.filter(app => app.name.toLocaleLowerCase('pt-BR').includes(value)) : appList;
  }, [appList, query]);

  useEffect(() => {
    if (!isStartMenuOpen) { setQuery(''); setView('home'); return; }
    requestAnimationFrame(() => inputRef.current?.focus());
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') closeStartMenu(); };
    const onPointer = (event: PointerEvent) => {
      const target = event.target as Node;
      if (menuRef.current && !menuRef.current.contains(target) && !document.querySelector('.taskbar')?.contains(target)) closeStartMenu();
    };
    document.addEventListener('keydown', onKey);
    document.addEventListener('pointerdown', onPointer);
    return () => { document.removeEventListener('keydown', onKey); document.removeEventListener('pointerdown', onPointer); };
  }, [isStartMenuOpen, closeStartMenu]);

  const launch = (app: App) => {
    const pid = createProcess(app.id, app.name, app.icon);
    openWindow({ title:app.name, icon:app.icon, appId:app.id, width:app.defaultWidth, height:app.defaultHeight, minWidth:app.minWidth, minHeight:app.minHeight, isResizable:app.isResizable, processId:pid, params:app.binaryPath ? { binaryPath:app.binaryPath } : undefined });
    closeStartMenu();
  };

  const activate = (id:string) => { restoreWindow(id); focusWindow(id); closeStartMenu(); };
  const toggleMaximize = (window:any) => window.isMaximized ? restoreWindow(window.id) : maximizeWindow(window.id);
  const closeAll = () => [...windows].forEach(window => closeWindow(window.id));
  const context = (event:React.MouseEvent, app:App) => {
    event.preventDefault();
    openContextMenu(event.clientX, event.clientY, [{ id:'open', label:'Abrir', icon:'⚡', onClick:() => launch(app) }]);
  };

  if (!isStartMenuOpen) return null;
  return <div className="start-menu-overlay">
    <div ref={menuRef} className="start-menu acrylic" role="dialog" aria-label="Menu Iniciar">
      <div className="start-search"><span className="start-search-icon">⌕</span><input ref={inputRef} className="start-search-input" placeholder="Pesquisar aplicativos..." value={query} onChange={e => setQuery(e.target.value)} /></div>
      {!query && <nav className="start-native-tabs" aria-label="Seções"><button className={view==='home'?'active':''} onClick={() => setView('home')}>Início</button><button className={view==='all'?'active':''} onClick={() => setView('all')}>Todos</button><button className={view==='running'?'active':''} onClick={() => setView('running')}>Abertos <b>{windows.length}</b></button></nav>}
      <main className="start-native-content">
        {query ? <AppGrid apps={filtered} launch={launch} context={context}/> : view==='home' ? <><div className="start-section-header"><strong>Fixados</strong><button onClick={() => setView('all')}>Todos os apps →</button></div><AppGrid apps={appList.slice(0, 12)} launch={launch} context={context}/></> : view==='all' ? <AppGrid apps={appList} launch={launch} context={context}/> : <section className="start-running"><header><div><strong>Aplicativos abertos</strong><small>{windows.length} janela{windows.length===1?'':'s'}</small></div><button className="close-all" disabled={!windows.length} onClick={closeAll}>Fechar todas</button></header>{windows.length ? <div className="running-list">{windows.map(window => <article className="running-item" key={window.id}><button className="running-main" onClick={() => activate(window.id)}><span className="running-icon">{window.icon || '▣'}</span><span><strong>{window.title || window.appId}</strong><small>{window.isMinimized?'Minimizada':window.isActive?'Ativa':'Em execução'}</small></span></button><div className="running-actions"><button onClick={() => minimizeWindow(window.id)} title="Minimizar">−</button><button onClick={() => toggleMaximize(window)} title="Maximizar ou restaurar">□</button><button className="danger" onClick={() => closeWindow(window.id)} title="Fechar">×</button></div></article>)}</div> : <div className="start-empty">Nenhum aplicativo aberto.</div>}</section>}
      </main>
      <footer className="start-bottom"><div className="start-user-btn"><div className="start-user-avatar">{currentUser?.avatar ? <img src={currentUser.avatar} alt=""/> : '●'}</div><span className="start-user-name">{currentUser?.displayName || currentUser?.username || 'Usuário'}</span></div><button className="start-power-btn" onClick={() => window.location.reload()} title="Reiniciar interface">⏻</button></footer>
    </div>
  </div>;
}

const AppGrid = memo(function AppGrid({apps,launch,context}:{apps:App[];launch:(app:App)=>void;context:(event:React.MouseEvent,app:App)=>void}) {
  return <div className="start-pinned-grid">{apps.map(app => <button key={app.id} className="start-app-btn" onClick={() => launch(app)} onContextMenu={event => context(event,app)}><span className="start-app-icon">{app.icon}</span><span className="start-app-name">{app.name}</span></button>)}</div>;
});
export default memo(StartMenu);
