import { memo, useEffect, useMemo, useRef, useState, useCallback } from 'react';
import { useSystem } from '../../stores/systemStore';
import { useWindowManager } from '../../stores/windowManager';
import { useProcessManager } from '../../stores/processManager';
import { useContextMenuStore } from '../../stores/contextMenuStore';
import { useAppRegistry } from '../../core/appRegistry';
import { nativeHostBridge } from '../../services/nativeHostBridge';
import { apiClient } from '../../services/apiClient';
import './StartMenu.css';
import './StartMenu.native.css';

type View = 'home' | 'all' | 'linux' | 'running';

type App = {
  id: string;
  name: string;
  genericName?: string;
  comment?: string;
  category?: string;
  categories?: string[];
  icon: string;
  iconUrl?: string | null;
  emojiFallback?: string;
  defaultWidth?: number;
  defaultHeight?: number;
  minWidth?: number;
  minHeight?: number;
  isResizable?: boolean;
  binaryPath?: string;
  isLinux?: boolean;
  linuxAppId?: string;
};

const requiresNativeHost = (app: App) => app.id === 'browser';
const appUnavailable = (app: App) => requiresNativeHost(app) && !nativeHostBridge.available;

const LINUX_CATEGORY_LABELS: Record<string, string> = {
  all: 'Todos',
  internet: 'Internet',
  development: 'Desenvolvimento',
  utilities: 'Utilitários',
  graphics: 'Gráficos',
  multimedia: 'Multimídia',
  office: 'Escritório',
  security: 'Segurança',
};

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
  const apps = useAppRegistry((s: any) => s.apps) as Record<string, App>;
  const [view, setView] = useState<View>('home');
  const [linuxCategoryFilter, setLinuxCategoryFilter] = useState<string>('all');
  const [query, setQuery] = useState('');
  const [capabilityNotice, setCapabilityNotice] = useState('');
  const [linuxApps, setLinuxApps] = useState<App[]>([]);
  const menuRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const fetchLinuxApps = useCallback(async () => {
    try {
      const res = await apiClient<{ packages: Array<any> }>('/api/linux-runtime/packages');
      if (res?.packages) {
        const installed = res.packages
          .filter((pkg: any) => pkg.installed)
          .map((pkg: any) => ({
            id: `linux-app-${pkg.id}`,
            name: `${pkg.name}`,
            genericName: pkg.genericName || '',
            comment: pkg.description || pkg.comment || '',
            category: pkg.category || 'utilities',
            categories: pkg.categories || [],
            icon: pkg.iconUrl || pkg.icon || pkg.emojiFallback || '🐧',
            iconUrl: pkg.iconUrl || null,
            emojiFallback: pkg.emojiFallback || '🐧',
            defaultWidth: 960,
            defaultHeight: 640,
            isLinux: true,
            linuxAppId: pkg.id,
          }));
        setLinuxApps(installed);
      }
    } catch {
      // Graceful fallback if backend runtime is starting up
    }
  }, []);

  useEffect(() => {
    fetchLinuxApps();
    const handleAppsChanged = () => fetchLinuxApps();
    window.addEventListener('cloudos:apps-changed', handleAppsChanged);
    return () => window.removeEventListener('cloudos:apps-changed', handleAppsChanged);
  }, [fetchLinuxApps]);

  const appList = useMemo(() => {
    const base = Object.values(apps);
    return [...base, ...linuxApps];
  }, [apps, linuxApps]);

  const filtered = useMemo(() => {
    const value = query.trim().toLocaleLowerCase('pt-BR');
    if (!value) return appList;
    return appList.filter((app) => 
      app.name.toLocaleLowerCase('pt-BR').includes(value) ||
      (app.genericName && app.genericName.toLocaleLowerCase('pt-BR').includes(value)) ||
      (app.comment && app.comment.toLocaleLowerCase('pt-BR').includes(value)) ||
      (app.category && app.category.toLocaleLowerCase('pt-BR').includes(value)) ||
      (app.linuxAppId && app.linuxAppId.toLocaleLowerCase('pt-BR').includes(value))
    );
  }, [appList, query]);

  const filteredLinuxApps = useMemo(() => {
    if (linuxCategoryFilter === 'all') return linuxApps;
    return linuxApps.filter(app => app.category === linuxCategoryFilter);
  }, [linuxApps, linuxCategoryFilter]);

  const availableLinuxCategories = useMemo(() => {
    const cats = new Set<string>(['all']);
    for (const app of linuxApps) {
      if (app.category) cats.add(app.category);
    }
    return Array.from(cats);
  }, [linuxApps]);

  useEffect(() => {
    if (!isStartMenuOpen) {
      setQuery('');
      setView('home');
      setLinuxCategoryFilter('all');
      setCapabilityNotice('');
      return;
    }
    fetchLinuxApps();
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
  }, [isStartMenuOpen, closeStartMenu, fetchLinuxApps]);

  const launch = (app: App) => {
    if (appUnavailable(app)) {
      setCapabilityNotice(`${app.name} exige o modo Full. Execute “Iniciar CloudOS.cmd Full” para usar o Host nativo.`);
      return;
    }

    if (app.isLinux && app.linuxAppId) {
      const pid = createProcess('linux-app-runner', app.name, app.icon);
      openWindow({
        title: app.name,
        icon: app.icon,
        appId: 'linux-app-runner',
        width: 1020,
        height: 680,
        minWidth: 480,
        minHeight: 320,
        isResizable: true,
        processId: pid,
        params: { appId: app.linuxAppId, app: app.linuxAppId, title: app.name, icon: app.icon },
      });
      closeStartMenu();
      return;
    }

    const pid = createProcess(app.id, app.name, app.icon);
    openWindow({
      title: app.name,
      icon: app.icon,
      appId: app.id,
      width: app.defaultWidth,
      height: app.defaultHeight,
      minWidth: app.minWidth,
      minHeight: app.minHeight,
      isResizable: app.isResizable,
      processId: pid,
      params: app.binaryPath ? { binaryPath: app.binaryPath } : undefined,
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

  const context = (event: React.MouseEvent, app: App) => {
    event.preventDefault();
    if (appUnavailable(app)) {
      setCapabilityNotice(`${app.name} está indisponível nesta sessão porque o Native Host não está ativo.`);
      return;
    }
    openContextMenu(event.clientX, event.clientY, [
      { id: 'open', label: 'Abrir', icon: '⚡', onClick: () => launch(app) },
    ]);
  };

  if (!isStartMenuOpen) return null;

  return (
    <div className="start-menu-overlay">
      <div ref={menuRef} className="start-menu acrylic" role="dialog" aria-label="Menu Iniciar">
        <div className="start-search">
          <span className="start-search-icon" aria-hidden="true">🔍</span>
          <input
            ref={inputRef}
            className="start-search-input"
            placeholder="Pesquisar aplicativos..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>

        {capabilityNotice && (
          <div className="start-capability-notice" role="status" data-native-host-required="true">
            {capabilityNotice}
          </div>
        )}

        {!query && (
          <nav className="start-native-tabs" aria-label="Seções">
            <button className={view === 'home' ? 'active' : ''} onClick={() => setView('home')}>Início</button>
            <button className={view === 'all' ? 'active' : ''} onClick={() => setView('all')}>Todos</button>
            <button className={view === 'linux' ? 'active' : ''} onClick={() => setView('linux')}>
              🐧 Linux <b>{linuxApps.length}</b>
            </button>
            <button className={view === 'running' ? 'active' : ''} onClick={() => setView('running')}>
              Abertos <b>{windows.length}</b>
            </button>
          </nav>
        )}

        <main className="start-native-content">
          {query ? (
            <AppGrid apps={filtered} launch={launch} context={context} />
          ) : view === 'home' ? (
            <>
              <div className="start-section-header">
                <strong>Fixados</strong>
                <button onClick={() => setView('all')}>Todos os apps →</button>
              </div>
              <AppGrid apps={appList.slice(0, 12)} launch={launch} context={context} />
            </>
          ) : view === 'linux' ? (
            <>
              <div className="start-section-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <div>
                  <strong>Aplicativos Linux ({filteredLinuxApps.length})</strong>
                  <small style={{ color: '#94a3b8', display: 'block', fontSize: '11px' }}>Descoberta automática de .desktop no WSL</small>
                </div>
                {availableLinuxCategories.length > 1 && (
                  <div style={{ display: 'flex', gap: '4px', flexWrap: 'wrap' }}>
                    {availableLinuxCategories.map(cat => (
                      <button
                        key={cat}
                        onClick={() => setLinuxCategoryFilter(cat)}
                        style={{
                          background: linuxCategoryFilter === cat ? 'rgba(59, 130, 246, 0.4)' : 'rgba(255, 255, 255, 0.08)',
                          border: linuxCategoryFilter === cat ? '1px solid #3b82f6' : '1px solid rgba(255, 255, 255, 0.1)',
                          color: '#fff',
                          padding: '2px 8px',
                          borderRadius: '12px',
                          fontSize: '11px',
                          cursor: 'pointer'
                        }}
                      >
                        {LINUX_CATEGORY_LABELS[cat] || cat}
                      </button>
                    ))}
                  </div>
                )}
              </div>
              {filteredLinuxApps.length ? (
                <AppGrid apps={filteredLinuxApps} launch={launch} context={context} />
              ) : (
                <div className="start-empty">Nenhum aplicativo Linux encontrado nesta categoria.</div>
              )}
            </>
          ) : view === 'all' ? (
            <AppGrid apps={appList} launch={launch} context={context} />
          ) : (
            <section className="start-running">
              <header>
                <div>
                  <strong>Aplicativos abertos</strong>
                  <small>{windows.length} janela{windows.length === 1 ? '' : 's'}</small>
                </div>
                <button className="close-all" disabled={!windows.length} onClick={closeAll}>Fechar todas</button>
              </header>
              {windows.length ? (
                <div className="running-list">
                  {windows.map((window) => (
                    <article className="running-item" key={window.id}>
                      <button className="running-main" onClick={() => activate(window.id)}>
                        <span className="running-icon">
                          {typeof window.icon === 'string' && (window.icon.startsWith('/') || window.icon.startsWith('http')) ? (
                            <img src={window.icon} alt="" style={{ width: '20px', height: '20px', objectFit: 'contain' }} />
                          ) : (
                            window.icon || '🗔'
                          )}
                        </span>
                        <span>
                          <strong>{window.title || window.appId}</strong>
                          <small>{window.isMinimized ? 'Minimizada' : window.isActive ? 'Ativa' : 'Em execução'}</small>
                        </span>
                      </button>
                      <div className="running-actions">
                        <button onClick={() => minimizeWindow(window.id)} title="Minimizar">−</button>
                        <button onClick={() => toggleMaximize(window)} title="Maximizar ou restaurar">□</button>
                        <button className="danger" onClick={() => closeWindow(window.id)} title="Fechar">✕</button>
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
            <div className="start-user-avatar">{currentUser?.avatar ? <img src={currentUser.avatar} alt="" /> : '●'}</div>
            <span className="start-user-name">{currentUser?.displayName || currentUser?.username || 'Usuário'}</span>
          </div>
          <button className="start-power-btn" onClick={() => closeAll()} title="Fechar todas as janelas">⏻</button>
        </footer>
      </div>
    </div>
  );
}

const AppGrid = memo(function AppGrid({ apps, launch, context }: {
  apps: App[];
  launch: (app: App) => void;
  context: (event: React.MouseEvent, app: App) => void;
}) {
  return (
    <div className="start-pinned-grid">
      {apps.map((app) => {
        const unavailable = appUnavailable(app);
        const isIconUrl = typeof app.icon === 'string' && (app.icon.startsWith('/') || app.icon.startsWith('http'));
        return (
          <button
            key={app.id}
            className="start-app-btn"
            onClick={() => launch(app)}
            onContextMenu={(event) => context(event, app)}
            aria-disabled={unavailable}
            data-app-capability={unavailable ? 'requires-full' : 'available'}
            title={unavailable ? 'Exige o modo Full / Native Host' : (app.comment || app.genericName || app.name)}
          >
            <span className="start-app-icon">
              {isIconUrl ? (
                <img
                  src={app.icon}
                  alt=""
                  style={{ width: '32px', height: '32px', objectFit: 'contain' }}
                  onError={(e) => {
                    (e.target as HTMLElement).style.display = 'none';
                    if ((e.target as HTMLElement).parentElement) {
                      (e.target as HTMLElement).parentElement!.innerText = app.emojiFallback || '🐧';
                    }
                  }}
                />
              ) : (
                app.icon || '📦'
              )}
            </span>
            <span className="start-app-name">{app.name}</span>
            {unavailable && <small>Modo Full</small>}
          </button>
        );
      })}
    </div>
  );
});

export default memo(StartMenu);
