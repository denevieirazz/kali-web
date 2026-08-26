import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useSystem } from '../../stores/systemStore';
import { useWindowManager } from '../../stores/windowManager';
import { useProcessManager } from '../../stores/processManager';
import { useContextMenuStore } from '../../stores/contextMenuStore';
import { useAppRegistry } from '../../core/appRegistry';
import { systemHubClient, type NativeApp } from '../../services/systemHubClient';
import { mergeStartMenuCatalog, searchStartMenuCatalog, type StartMenuApp } from './startMenuCatalog';
import './StartMenu.css';
import './StartMenu.native.css';

type View = 'home' | 'all' | 'running';
type CatalogStatus = 'idle' | 'loading' | 'ready' | 'error';

function StartMenu() {
  const { isStartMenuOpen, closeStartMenu, currentUser } = useSystem();
  const allWindows = useWindowManager((s) => s.windows);
  const windows = useMemo(() => allWindows.filter((w) => !w.isSystem), [allWindows]);
  const openWindow = useWindowManager((s) => s.openWindow);
  const closeWindow = useWindowManager((s) => s.closeWindow);
  const minimizeWindow = useWindowManager((s) => s.minimizeWindow);
  const maximizeWindow = useWindowManager((s) => s.maximizeWindow);
  const restoreWindow = useWindowManager((s) => s.restoreWindow);
  const focusWindow = useWindowManager((s) => s.focusWindow);
  const createProcess = useProcessManager((s) => s.createProcess);
  const openContextMenu = useContextMenuStore((s) => s.openContextMenu);
  const apps = useAppRegistry((s) => s.apps);
  const [view, setView] = useState<View>('home');
  const [query, setQuery] = useState('');
  const [nativeApps, setNativeApps] = useState<NativeApp[]>([]);
  const [catalogStatus, setCatalogStatus] = useState<CatalogStatus>('idle');
  const [catalogError, setCatalogError] = useState('');
  const [launchNotice, setLaunchNotice] = useState('');
  const menuRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const catalogRequestRef = useRef<Promise<void> | null>(null);

  const appList = useMemo(() => mergeStartMenuCatalog(Object.values(apps), nativeApps), [apps, nativeApps]);
  const pinnedApps = useMemo(() => [
    ...appList.filter((app) => app.launcher === 'cloud').slice(0, 8),
    ...appList.filter((app) => app.launcher === 'native').slice(0, 4),
  ], [appList]);
  const filtered = useMemo(() => searchStartMenuCatalog(appList, query), [appList, query]);

  const loadNativeCatalog = useCallback((refresh = false) => {
    if (catalogRequestRef.current) return catalogRequestRef.current;
    setCatalogStatus('loading');
    setCatalogError('');
    const request = systemHubClient.apps(refresh)
      .then(({ apps: discovered }) => {
        setNativeApps(discovered);
        setCatalogStatus('ready');
      })
      .catch((error) => {
        setCatalogStatus('error');
        setCatalogError(error instanceof Error ? error.message : 'O catálogo do computador não pôde ser carregado.');
      })
      .finally(() => { catalogRequestRef.current = null; });
    catalogRequestRef.current = request;
    return request;
  }, []);

  useEffect(() => {
    if (!isStartMenuOpen) {
      setQuery('');
      setView('home');
      return;
    }
    requestAnimationFrame(() => inputRef.current?.focus());
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') closeStartMenu();
    };
    const onPointer = (event: PointerEvent) => {
      const target = event.target as Node;
      if (
        menuRef.current &&
        !menuRef.current.contains(target) &&
        !document.querySelector('.taskbar')?.contains(target)
      ) {
        closeStartMenu();
      }
    };
    document.addEventListener('keydown', onKey);
    document.addEventListener('pointerdown', onPointer);
    return () => {
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('pointerdown', onPointer);
    };
  }, [isStartMenuOpen, closeStartMenu]);

  useEffect(() => {
    if (isStartMenuOpen && catalogStatus === 'idle') void loadNativeCatalog();
  }, [catalogStatus, isStartMenuOpen, loadNativeCatalog]);

  const launch = (app: StartMenuApp) => {
    if (app.launcher === 'native' && app.availability === 'blocked') {
      setLaunchNotice(app.blockedReason || 'Este programa não pode ser contido com segurança dentro do CloudOS.');
      return;
    }
    setLaunchNotice('');
    const isNative = app.launcher === 'native';
    const processName = isNative ? 'native-app-window' : app.id;
    const pid = createProcess(processName, app.name, app.icon);
    openWindow({
      title: app.name,
      icon: app.icon,
      appId: isNative ? 'native-app-window' : app.id,
      width: app.defaultWidth,
      height: app.defaultHeight,
      minWidth: app.minWidth,
      minHeight: app.minHeight,
      isResizable: app.isResizable,
      processId: pid,
      params: isNative
        ? { nativeApp: app }
        : app.binaryPath ? { binaryPath: app.binaryPath } : undefined,
    });
    closeStartMenu();
  };

  const activate = (id: string) => {
    restoreWindow(id);
    focusWindow(id);
    closeStartMenu();
  };

  const toggleMaximize = (window: any) =>
    window.isMaximized ? restoreWindow(window.id) : maximizeWindow(window.id);

  const closeAll = () => [...windows].forEach((window) => closeWindow(window.id));

  const context = (event: React.MouseEvent, app: StartMenuApp) => {
    event.preventDefault();
    openContextMenu(event.clientX, event.clientY, [
      { id: 'open', label: app.launcher === 'native' ? 'Abrir dentro do CloudOS' : 'Abrir', icon: '⚡', onClick: () => launch(app) },
    ]);
  };

  if (!isStartMenuOpen) return null;

  return (
    <div className="start-menu-overlay">
      <div ref={menuRef} className="start-menu acrylic" role="dialog" aria-label="Menu Iniciar">
        <div className="start-search">
          <span className="start-search-icon" aria-hidden="true">
            🔍
          </span>
          <input
            ref={inputRef}
            className="start-search-input"
            placeholder="Pesquisar CloudOS, Windows e Linux..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>

        {!query && (
          <nav className="start-native-tabs" aria-label="Seções">
            <button className={view === 'home' ? 'active' : ''} onClick={() => setView('home')}>
              Início
            </button>
            <button className={view === 'all' ? 'active' : ''} onClick={() => setView('all')}>
              Todos <b>{appList.length}</b>
            </button>
            <button className={view === 'running' ? 'active' : ''} onClick={() => setView('running')}>
              Abertos <b>{windows.length}</b>
            </button>
          </nav>
        )}

        <main className="start-native-content">
          {launchNotice && <div className="start-catalog-status error" role="alert"><span className="status-dot" /><div><strong>Aplicativo protegido pela contenção</strong><small>{launchNotice}</small></div><button onClick={() => setLaunchNotice('')}>Fechar</button></div>}
          {query ? (
            <AppGrid apps={filtered} launch={launch} context={context} />
          ) : view === 'home' ? (
            <>
              <div className="start-section-header">
                <strong>Fixados</strong>
                <button onClick={() => setView('all')}>Todos os apps →</button>
              </div>
              <AppGrid apps={pinnedApps} launch={launch} context={context} />
              <CatalogStatusRow
                status={catalogStatus}
                count={nativeApps.length}
                error={catalogError}
                retry={() => void loadNativeCatalog(true)}
              />
            </>
          ) : view === 'all' ? (
            <>
              <CatalogStatusRow
                status={catalogStatus}
                count={nativeApps.length}
                error={catalogError}
                retry={() => void loadNativeCatalog(true)}
              />
              <AppGrid apps={appList} launch={launch} context={context} />
            </>
          ) : (
            <section className="start-running">
              <header>
                <div>
                  <strong>Aplicativos abertos</strong>
                  <small>
                    {windows.length} janela{windows.length === 1 ? '' : 's'}
                  </small>
                </div>
                <button className="close-all" disabled={!windows.length} onClick={closeAll}>
                  Fechar todas
                </button>
              </header>
              {windows.length ? (
                <div className="running-list">
                  {windows.map((window) => (
                    <article className="running-item" key={window.id}>
                      <button className="running-main" onClick={() => activate(window.id)}>
                        <span className="running-icon">{window.icon || '🗔'}</span>
                        <span>
                          <strong>{window.title || window.appId}</strong>
                          <small>
                            {window.isMinimized
                              ? 'Minimizada'
                              : window.isActive
                              ? 'Ativa'
                              : 'Em execução'}
                          </small>
                        </span>
                      </button>
                      <div className="running-actions">
                        <button onClick={() => minimizeWindow(window.id)} title="Minimizar">
                          −
                        </button>
                        <button onClick={() => toggleMaximize(window)} title="Maximizar ou restaurar">
                          □
                        </button>
                        <button
                          className="danger"
                          onClick={() => closeWindow(window.id)}
                          title="Fechar"
                        >
                          ✕
                        </button>
                      </div>
                    </article>
                  ))}
                </div>
              ) : (
                <div className="start-empty">Nenhum aplicativo aberto.</div>
              )}
            </section>
          )}
        </main>

        <footer className="start-bottom">
          <div className="start-user-btn">
            <div className="start-user-avatar">
              {currentUser?.avatar ? <img src={currentUser.avatar} alt="" /> : '●'}
            </div>
            <span className="start-user-name">
              {currentUser?.displayName || currentUser?.username || 'Usuário'}
            </span>
          </div>
          <button
            className="start-power-btn"
            onClick={() => closeAll()}
            title="Fechar todas as janelas"
          >
            ⏻
          </button>
        </footer>
      </div>
    </div>
  );
}

const AppGrid = memo(function AppGrid({
  apps,
  launch,
  context,
}: {
  apps: StartMenuApp[];
  launch: (app: StartMenuApp) => void;
  context: (event: React.MouseEvent, app: StartMenuApp) => void;
}) {
  return (
    <div className="start-pinned-grid">
      {apps.map((app) => (
        <button
          key={app.id}
          className="start-app-btn"
          aria-disabled={app.launcher === 'native' && app.availability === 'blocked'}
          title={app.launcher === 'native' && app.availability === 'blocked' ? app.blockedReason || 'Indisponível com contenção' : app.name}
          onClick={() => launch(app)}
          onContextMenu={(event) => context(event, app)}
        >
          <span className="start-app-icon-wrap">
            <span className="start-app-icon">{app.icon}</span>
            {app.launcher === 'native' && <span className={`start-app-source ${app.source}`}>{app.source === 'wsl' ? 'L' : 'W'}</span>}
            {app.launcher === 'native' && app.availability === 'blocked' && <span className="start-app-source blocked">🔒</span>}
          </span>
          <span className="start-app-name">{app.name}</span>
        </button>
      ))}
    </div>
  );
});

function CatalogStatusRow({
  status,
  count,
  error,
  retry,
}: {
  status: CatalogStatus;
  count: number;
  error: string;
  retry: () => void;
}) {
  if (status === 'idle') return null;
  return (
    <div className={`start-catalog-status ${status}`}>
      <span className="status-dot" />
      <div>
        <strong>{status === 'loading' ? 'Procurando programas do computador...' : status === 'error' ? 'Catálogo nativo indisponível' : `${count} programa${count === 1 ? '' : 's'} do Windows/Linux`}</strong>
        <small>{status === 'error' ? error : status === 'ready' ? 'Eles podem ser abertos diretamente pelo menu Iniciar.' : 'Lendo o Menu Iniciar do Windows e os arquivos .desktop do WSL.'}</small>
      </div>
      {status === 'error' && <button onClick={retry}>Tentar novamente</button>}
    </div>
  );
}

export default memo(StartMenu);
