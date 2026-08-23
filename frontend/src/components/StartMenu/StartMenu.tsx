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
  isUserApp?: boolean;
  isTechnical?: boolean;
};

const requiresNativeHost = (app: App) => app.id === 'browser';
const appUnavailable = (app: App) => requiresNativeHost(app) && !nativeHostBridge.available;

const FAVORITES_STORAGE_KEY = 'cloudos_startmenu_favorites_v1';
const RECENT_STORAGE_KEY = 'cloudos_startmenu_recent_v1';

const DEFAULT_FAVORITE_IDS = [
  'linux-app-firefox-esr',
  'linux-app-firefox',
  'file-explorer',
  'cloudos-terminal',
  'terminal',
  'linux-app-code',
  'linux-app-geany',
  'linux-app-mousepad',
  'linux-app-obsidian',
  'settings'
];

const LINUX_CATEGORIES: Array<{ id: string; label: string; icon: string }> = [
  { id: 'user_apps', label: 'Aplicativos', icon: '🌟' },
  { id: 'favorites', label: 'Favoritos', icon: '⭐' },
  { id: 'internet', label: 'Internet', icon: '🌐' },
  { id: 'development', label: 'Desenvolvimento', icon: '💻' },
  { id: 'office', label: 'Escritório', icon: '📄' },
  { id: 'multimedia', label: 'Multimídia', icon: '🎬' },
  { id: 'graphics', label: 'Gráficos', icon: '🎨' },
  { id: 'security', label: 'Segurança', icon: '🛡️' },
  { id: 'system', label: 'Sistema', icon: '⚙️' },
  { id: 'all', label: 'Todos', icon: '📦' },
];

function getStoredFavorites(): string[] {
  try {
    const raw = localStorage.getItem(FAVORITES_STORAGE_KEY);
    if (raw) return JSON.parse(raw);
  } catch {}
  return DEFAULT_FAVORITE_IDS;
}

function getStoredRecent(): string[] {
  try {
    const raw = localStorage.getItem(RECENT_STORAGE_KEY);
    if (raw) return JSON.parse(raw);
  } catch {}
  return [];
}

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
  const [linuxCategoryFilter, setLinuxCategoryFilter] = useState<string>('user_apps');
  const [query, setQuery] = useState('');
  const [capabilityNotice, setCapabilityNotice] = useState('');
  const [linuxApps, setLinuxApps] = useState<App[]>([]);
  const [favorites, setFavorites] = useState<string[]>(getStoredFavorites);
  const [recentAppIds, setRecentAppIds] = useState<string[]>(getStoredRecent);
  const menuRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const toggleFavorite = useCallback((appId: string, linuxAppId?: string) => {
    setFavorites(prev => {
      const matchId = linuxAppId || appId;
      const next = prev.includes(matchId) || prev.includes(appId)
        ? prev.filter(id => id !== matchId && id !== appId)
        : [...prev, matchId];
      try {
        localStorage.setItem(FAVORITES_STORAGE_KEY, JSON.stringify(next));
      } catch {}
      return next;
    });
  }, []);

  const addRecentApp = useCallback((appId: string) => {
    setRecentAppIds(prev => {
      const next = [appId, ...prev.filter(id => id !== appId)].slice(0, 8);
      try {
        localStorage.setItem(RECENT_STORAGE_KEY, JSON.stringify(next));
      } catch {}
      return next;
    });
  }, []);

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
            isUserApp: pkg.isUserApp !== false,
            isTechnical: pkg.isTechnical === true,
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

  const isAppFavorite = useCallback((app: App) => {
    return favorites.includes(app.id) || (app.linuxAppId ? favorites.includes(app.linuxAppId) : false);
  }, [favorites]);

  const appList = useMemo(() => {
    const base = Object.values(apps);
    const all = [...base, ...linuxApps];
    return all.sort((a, b) => {
      const aFav = isAppFavorite(a) ? 1 : 0;
      const bFav = isAppFavorite(b) ? 1 : 0;
      if (aFav !== bFav) return bFav - aFav;
      const aUser = a.isUserApp !== false ? 1 : 0;
      const bUser = b.isUserApp !== false ? 1 : 0;
      if (aUser !== bUser) return bUser - aUser;
      return a.name.localeCompare(b.name, 'pt-BR');
    });
  }, [apps, linuxApps, isAppFavorite]);

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

  const favoriteApps = useMemo(() => {
    return appList.filter(app => isAppFavorite(app));
  }, [appList, isAppFavorite]);

  const recentApps = useMemo(() => {
    return recentAppIds
      .map(id => appList.find(app => app.id === id || app.linuxAppId === id))
      .filter(Boolean) as App[];
  }, [appList, recentAppIds]);

  const userLinuxApps = useMemo(() => {
    return linuxApps.filter(app => app.isUserApp !== false);
  }, [linuxApps]);

  const filteredLinuxApps = useMemo(() => {
    if (linuxCategoryFilter === 'user_apps') return userLinuxApps;
    if (linuxCategoryFilter === 'favorites') return linuxApps.filter(app => isAppFavorite(app));
    if (linuxCategoryFilter === 'all') return linuxApps;
    return linuxApps.filter(app => app.category === linuxCategoryFilter);
  }, [linuxApps, userLinuxApps, linuxCategoryFilter, isAppFavorite]);

  const categoryCounts = useMemo(() => {
    const counts: Record<string, number> = {
      user_apps: userLinuxApps.length,
      favorites: linuxApps.filter(app => isAppFavorite(app)).length,
      all: linuxApps.length,
    };
    for (const app of linuxApps) {
      if (app.category) {
        counts[app.category] = (counts[app.category] || 0) + 1;
      }
    }
    return counts;
  }, [linuxApps, userLinuxApps, isAppFavorite]);

  const activeCategories = useMemo(() => {
    return LINUX_CATEGORIES.filter(cat => {
      if (cat.id === 'user_apps' || cat.id === 'all') return true;
      if (cat.id === 'favorites') return (categoryCounts.favorites || 0) > 0;
      return (categoryCounts[cat.id] || 0) > 0;
    });
  }, [categoryCounts]);

  useEffect(() => {
    if (!isStartMenuOpen) {
      setQuery('');
      setView('home');
      setLinuxCategoryFilter('user_apps');
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

    addRecentApp(app.id);

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

    const existingNativeWin = allWindows.find(w => w.appId === app.id);
    if (existingNativeWin && ['settings', 'task-manager', 'system-monitor', 'regedit', 'obsidian-store'].includes(app.id)) {
      if (existingNativeWin.isMinimized) restoreWindow(existingNativeWin.id);
      focusWindow(existingNativeWin.id);
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
    const isFav = isAppFavorite(app);
    openContextMenu(event.clientX, event.clientY, [
      { id: 'open', label: 'Abrir', icon: '⚡', onClick: () => launch(app) },
      {
        id: 'toggle-fav',
        label: isFav ? 'Remover dos Favoritos' : 'Fixar nos Favoritos',
        icon: isFav ? '⭐' : '☆',
        onClick: () => toggleFavorite(app.id, app.linuxAppId)
      },
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
            placeholder="Pesquisar aplicativos (Linux, Web e Sistema)..."
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
            <button className={view === 'home' ? 'active' : ''} onClick={() => setView('home')}>
              Início
            </button>
            <button className={view === 'linux' ? 'active' : ''} onClick={() => setView('linux')}>
              🐧 Linux <b>{userLinuxApps.length}</b>
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
          {query ? (
            <>
              <div className="start-section-header">
                <strong>Resultados da Busca ({filtered.length})</strong>
              </div>
              {filtered.length ? (
                <AppGrid apps={filtered} launch={launch} context={context} isAppFavorite={isAppFavorite} />
              ) : (
                <div className="start-empty">Nenhum aplicativo encontrado para “{query}”.</div>
              )}
            </>
          ) : view === 'home' ? (
            <>
              <div className="start-section-header">
                <strong>⭐ Favoritos</strong>
                <button onClick={() => setView('linux')}>Aplicativos Linux →</button>
              </div>
              <AppGrid apps={favoriteApps.length ? favoriteApps : appList.slice(0, 12)} launch={launch} context={context} isAppFavorite={isAppFavorite} />

              {recentApps.length > 0 && (
                <>
                  <div className="start-section-header" style={{ marginTop: '16px' }}>
                    <strong>🕒 Usados Recentemente</strong>
                  </div>
                  <AppGrid apps={recentApps} launch={launch} context={context} isAppFavorite={isAppFavorite} />
                </>
              )}
            </>
          ) : view === 'linux' ? (
            <>
              <div className="start-section-header" style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <div>
                    <strong>
                      {LINUX_CATEGORIES.find(c => c.id === linuxCategoryFilter)?.icon}{' '}
                      {LINUX_CATEGORIES.find(c => c.id === linuxCategoryFilter)?.label || 'Aplicativos'} ({filteredLinuxApps.length})
                    </strong>
                    <small style={{ color: '#94a3b8', display: 'block', fontSize: '11px' }}>
                      {linuxCategoryFilter === 'user_apps'
                        ? 'Aplicativos do usuário instalados via apt e .desktop'
                        : linuxCategoryFilter === 'favorites'
                          ? 'Aplicativos Linux fixados nos favoritos'
                          : `Categoria ${LINUX_CATEGORIES.find(c => c.id === linuxCategoryFilter)?.label || linuxCategoryFilter}`}
                    </small>
                  </div>
                  <span style={{ fontSize: '11px', color: '#94a3b8' }}>
                    Total: {linuxApps.length} no sistema
                  </span>
                </div>

                <div style={{ display: 'flex', gap: '5px', flexWrap: 'wrap', paddingTop: '4px' }}>
                  {activeCategories.map(cat => {
                    const isActive = linuxCategoryFilter === cat.id;
                    const count = categoryCounts[cat.id] || 0;
                    return (
                      <button
                        key={cat.id}
                        onClick={() => setLinuxCategoryFilter(cat.id)}
                        style={{
                          background: isActive ? 'rgba(99, 102, 241, 0.45)' : 'rgba(255, 255, 255, 0.06)',
                          border: isActive ? '1px solid #818cf8' : '1px solid rgba(255, 255, 255, 0.1)',
                          color: isActive ? '#ffffff' : '#cbd5e1',
                          padding: '4px 10px',
                          borderRadius: '14px',
                          fontSize: '11.5px',
                          fontWeight: isActive ? 600 : 400,
                          cursor: 'pointer',
                          display: 'flex',
                          alignItems: 'center',
                          gap: '4px',
                          transition: 'all 0.15s ease'
                        }}
                      >
                        <span>{cat.icon}</span>
                        <span>{cat.label}</span>
                        <span style={{
                          background: isActive ? 'rgba(255, 255, 255, 0.25)' : 'rgba(0, 0, 0, 0.25)',
                          borderRadius: '10px',
                          padding: '1px 5px',
                          fontSize: '10px'
                        }}>
                          {count}
                        </span>
                      </button>
                    );
                  })}
                </div>
              </div>

              {filteredLinuxApps.length ? (
                <AppGrid apps={filteredLinuxApps} launch={launch} context={context} isAppFavorite={isAppFavorite} />
              ) : (
                <div className="start-empty">Nenhum aplicativo encontrado nesta categoria.</div>
              )}
            </>
          ) : view === 'all' ? (
            <>
              <div className="start-section-header">
                <strong>Todos os Aplicativos ({appList.length})</strong>
              </div>
              <AppGrid apps={appList} launch={launch} context={context} isAppFavorite={isAppFavorite} />
            </>
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

const AppGrid = memo(function AppGrid({ apps, launch, context, isAppFavorite }: {
  apps: App[];
  launch: (app: App) => void;
  context: (event: React.MouseEvent, app: App) => void;
  isAppFavorite: (app: App) => boolean;
}) {
  return (
    <div className="start-pinned-grid">
      {apps.map((app) => {
        const unavailable = appUnavailable(app);
        const isIconUrl = typeof app.icon === 'string' && (app.icon.startsWith('/') || app.icon.startsWith('http'));
        const fav = isAppFavorite(app);
        return (
          <button
            key={app.id}
            className="start-app-btn"
            onClick={() => launch(app)}
            onContextMenu={(event) => context(event, app)}
            aria-disabled={unavailable}
            data-app-capability={unavailable ? 'requires-full' : 'available'}
            title={`${app.name}${app.genericName ? ` — ${app.genericName}` : ''}${app.comment ? `\n${app.comment}` : ''}\n(Clique direito para opções)`}
            style={{ position: 'relative' }}
          >
            {fav && (
              <span
                style={{
                  position: 'absolute',
                  top: '4px',
                  right: '8px',
                  fontSize: '10px',
                  color: '#fbbf24'
                }}
                title="Favorito"
              >
                ★
              </span>
            )}
            <span className="start-app-icon">
              {isIconUrl ? (
                <img
                  src={app.icon}
                  alt=""
                  style={{ width: '34px', height: '34px', objectFit: 'contain' }}
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
            <span className="start-app-name" style={{ fontWeight: fav ? 600 : 400 }}>
              {app.name}
            </span>
            {unavailable && <small>Modo Full</small>}
          </button>
        );
      })}
    </div>
  );
});

export default memo(StartMenu);
