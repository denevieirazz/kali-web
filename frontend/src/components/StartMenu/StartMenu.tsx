import { memo, useEffect, useMemo, useRef, useState, useCallback } from 'react';
import { useSystem } from '../../stores/systemStore';
import { useWindowManager } from '../../stores/windowManager';
import { useContextMenuStore } from '../../stores/contextMenuStore';
import { useAppRegistry } from '../../core/appRegistry';
import { useUserStore } from '../../stores/userStore';
import { refreshUnifiedAppRegistry } from '../../services/systemHubClient';
import { appLaunchUnavailableReason, launchWorkflowApp } from '../../services/workflowLaunch';
import type { AppDefinition } from '../../types';
import kernel from '../../core/kernel';
import './StartMenu.css';
import './StartMenu.native.css';

type View = 'home' | 'all' | 'linux' | 'windows' | 'running';
type App = AppDefinition;

const appUnavailable = (app: App) => Boolean(appLaunchUnavailableReason(app));

const FAVORITES_STORAGE_KEY = 'cloudos_startmenu_favorites_v1';
const RECENT_STORAGE_KEY = 'cloudos_startmenu_recent_v1';

const DEFAULT_FAVORITE_IDS = [
  'notepad',
  'calculator',
  'terminal',
  'cloudos-terminal',
  'system-monitor',
  'install-linux',
  'env-doctor',
  'file-explorer',
  'settings',
  'task-manager',
  'browser'
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
  { id: 'utilities', label: 'Utilitários', icon: '🧰' },
  { id: 'education', label: 'Educação', icon: '🎓' },
  { id: 'science', label: 'Ciência', icon: '🔬' },
  { id: 'entertainment', label: 'Jogos', icon: '🎮' },
  { id: 'other', label: 'Outros', icon: '🧩' },
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
  const closeWindow = useWindowManager((s) => s.closeWindow);
  const minimizeWindow = useWindowManager((s) => s.minimizeWindow);
  const maximizeWindow = useWindowManager((s) => s.maximizeWindow);
  const restoreWindow = useWindowManager((s) => s.restoreWindow);
  const focusWindow = useWindowManager((s) => s.focusWindow);
  const openContextMenu = useContextMenuStore((s) => s.openContextMenu);
  const apps = useAppRegistry((s) => s.apps);
  const [view, setView] = useState<View>('home');
  const [linuxCategoryFilter, setLinuxCategoryFilter] = useState<string>('user_apps');
  const [query, setQuery] = useState('');
  const [capabilityNotice, setCapabilityNotice] = useState('');
  const [favorites, setFavorites] = useState<string[]>(getStoredFavorites);
  const [recentAppIds, setRecentAppIds] = useState<string[]>(getStoredRecent);
  const [showPowerMenu, setShowPowerMenu] = useState(false);
  const [showUserMenu, setShowUserMenu] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const catalogRefreshRef = useRef<Promise<void> | null>(null);

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

  const refreshCatalog = useCallback((force = false) => {
    if (catalogRefreshRef.current) return catalogRefreshRef.current;
    const refresh = refreshUnifiedAppRegistry(force)
      .then(() => undefined)
      .finally(() => {
        if (catalogRefreshRef.current === refresh) catalogRefreshRef.current = null;
      });
    catalogRefreshRef.current = refresh;
    return refresh;
  }, []);

  useEffect(() => {
    void refreshCatalog(false).catch(() => undefined);
    const handleAppsChanged = () => { void refreshCatalog(true).catch(() => undefined); };
    window.addEventListener('cloudos:apps-changed', handleAppsChanged);
    return () => {
      window.removeEventListener('cloudos:apps-changed', handleAppsChanged);
    };
  }, [refreshCatalog]);

  useEffect(() => {
    if (!isStartMenuOpen) return;
    void refreshCatalog(true).catch(() => undefined);
    const timer = window.setInterval(() => {
      void refreshCatalog(true).catch(() => undefined);
    }, 8_000);
    return () => window.clearInterval(timer);
  }, [isStartMenuOpen, refreshCatalog]);

  const isAppFavorite = useCallback((app: App) => {
    return favorites.includes(app.id) || (app.linuxAppId ? favorites.includes(app.linuxAppId) : false);
  }, [favorites]);

  const appList = useMemo(() => {
    return Object.values(apps).sort((a, b) => {
      const aFav = isAppFavorite(a) ? 1 : 0;
      const bFav = isAppFavorite(b) ? 1 : 0;
      if (aFav !== bFav) return bFav - aFav;
      const aUser = a.isUserApp !== false ? 1 : 0;
      const bUser = b.isUserApp !== false ? 1 : 0;
      if (aUser !== bUser) return bUser - aUser;
      return a.name.localeCompare(b.name, 'pt-BR');
    });
  }, [apps, isAppFavorite]);

  const filtered = useMemo(() => {
    const value = query.trim().toLocaleLowerCase('pt-BR');
    if (!value) return appList;
    return appList.filter((app) => [
      app.name,
      app.genericName,
      app.comment,
      app.category,
      ...(app.keywords || []),
      ...(app.categories || []),
      ...(app.mimeTypes || []),
      app.distribution,
      app.catalogSource,
    ].filter(Boolean).join(' ').toLocaleLowerCase('pt-BR').includes(value));
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
    return appList.filter(app => app.catalogSource === 'linux' && app.isUserApp !== false);
  }, [appList]);

  const linuxApps = useMemo(() => appList.filter(app => app.catalogSource === 'linux'), [appList]);
  const windowsApps = useMemo(() => appList.filter(app => app.catalogSource === 'windows'), [appList]);

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
  }, [isStartMenuOpen, closeStartMenu, refreshCatalog]);

  const launch = (app: App) => {
    const unavailableReason = appLaunchUnavailableReason(app);
    if (unavailableReason) {
      setCapabilityNotice(unavailableReason);
      return;
    }

    try {
      launchWorkflowApp(app.id, app.binaryPath ? { binaryPath: app.binaryPath } : undefined);
      addRecentApp(app.id);
      closeStartMenu();
    } catch (error) {
      setCapabilityNotice(error instanceof Error ? error.message : 'O aplicativo não pôde ser aberto de forma contida.');
    }
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
      setCapabilityNotice(appLaunchUnavailableReason(app) || `${app.name} está indisponível nesta sessão.`);
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
            placeholder="Pesquisar aplicativos Windows, Linux e CloudOS..."
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
            <button className={view === 'windows' ? 'active' : ''} onClick={() => setView('windows')}>
              ▦ Windows <b>{windowsApps.length}</b>
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
          ) : view === 'windows' ? (
            <>
              <div className="start-section-header">
                <div>
                  <strong>▦ Aplicativos Windows ({windowsApps.length})</strong>
                  <small style={{ color: '#94a3b8', display: 'block', fontSize: '11px' }}>
                    Somente aplicativos que podem ser encaixados pelo Host nativo do CloudOS
                  </small>
                </div>
              </div>
              {windowsApps.length ? (
                <AppGrid apps={windowsApps} launch={launch} context={context} isAppFavorite={isAppFavorite} />
              ) : (
                <div className="start-empty">Nenhum aplicativo Windows contido disponível nesta sessão.</div>
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

        <footer className="start-bottom" style={{ position: 'relative' }}>
          {showUserMenu && (
            <div style={{
              position: 'absolute',
              bottom: '100%',
              left: 16,
              marginBottom: 8,
              background: 'rgba(24, 24, 27, 0.95)',
              border: '1px solid rgba(255, 255, 255, 0.15)',
              borderRadius: 8,
              padding: 6,
              display: 'flex',
              flexDirection: 'column',
              gap: 4,
              boxShadow: '0 10px 25px rgba(0,0,0,0.5)',
              zIndex: 100,
              minWidth: 160
            }}>
              <button
                style={{ background: 'transparent', border: 'none', color: '#fff', padding: '8px 12px', textAlign: 'left', borderRadius: 4, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8 }}
                onClick={() => { setShowUserMenu(false); closeStartMenu(); kernel.sysLock(); }}
              >
                🔒 Bloquear Sessão
              </button>
              <button
                style={{ background: 'transparent', border: 'none', color: '#fff', padding: '8px 12px', textAlign: 'left', borderRadius: 4, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8 }}
                onClick={() => { setShowUserMenu(false); closeStartMenu(); void useUserStore.getState().logout(); }}
              >
                🚪 Sair da Conta (Logout)
              </button>
            </div>
          )}

          {showPowerMenu && (
            <div style={{
              position: 'absolute',
              bottom: '100%',
              right: 16,
              marginBottom: 8,
              background: 'rgba(24, 24, 27, 0.95)',
              border: '1px solid rgba(255, 255, 255, 0.15)',
              borderRadius: 8,
              padding: 6,
              display: 'flex',
              flexDirection: 'column',
              gap: 4,
              boxShadow: '0 10px 25px rgba(0,0,0,0.5)',
              zIndex: 100,
              minWidth: 160
            }}>
              <button
                style={{ background: 'transparent', border: 'none', color: '#fff', padding: '8px 12px', textAlign: 'left', borderRadius: 4, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8 }}
                onClick={() => { setShowPowerMenu(false); closeStartMenu(); void useUserStore.getState().logout(); }}
              >
                🚪 Sair da Conta (Logout)
              </button>
              <button
                style={{ background: 'transparent', border: 'none', color: '#fff', padding: '8px 12px', textAlign: 'left', borderRadius: 4, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8 }}
                onClick={() => { setShowPowerMenu(false); closeStartMenu(); kernel.sysLock(); }}
              >
                🔒 Bloquear
              </button>
              <button
                style={{ background: 'transparent', border: 'none', color: '#fff', padding: '8px 12px', textAlign: 'left', borderRadius: 4, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8 }}
                onClick={() => { setShowPowerMenu(false); closeStartMenu(); closeAll(); }}
              >
                🗔 Fechar todas as janelas
              </button>
            </div>
          )}

          <div className="start-user-btn" onClick={() => { setShowUserMenu(v => !v); setShowPowerMenu(false); }} style={{ cursor: 'pointer' }}>
            <div className="start-user-avatar">{currentUser?.avatar ? <img src={currentUser.avatar} alt="" /> : '●'}</div>
            <span className="start-user-name">{currentUser?.displayName || currentUser?.username || 'Usuário'}</span>
          </div>
          <button className="start-power-btn" onClick={() => { setShowPowerMenu(v => !v); setShowUserMenu(false); }} title="Opções de Energia e Sessão">⏻</button>
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
        const visibleIcon = app.iconUrl || app.icon;
        const isIconUrl = typeof visibleIcon === 'string' && (visibleIcon.startsWith('/') || visibleIcon.startsWith('http'));
        const fav = isAppFavorite(app);
        const originLabel = app.catalogSource === 'linux'
          ? 'Linux · Xpra'
          : app.catalogSource === 'windows'
            ? 'Windows · CloudOS'
            : '';
        const categoryLabel = app.categories?.[0] || app.category;
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
                  src={visibleIcon}
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
            {(originLabel || categoryLabel) && (
              <small>{[originLabel, categoryLabel].filter(Boolean).join(' · ')}</small>
            )}
            {unavailable && <small>Indisponível sem containment</small>}
          </button>
        );
      })}
    </div>
  );
});

export default memo(StartMenu);
