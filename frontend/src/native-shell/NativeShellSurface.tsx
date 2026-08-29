import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import {
  FiActivity,
  FiBox,
  FiCode,
  FiColumns,
  FiCpu,
  FiFolder,
  FiGlobe,
  FiGrid,
  FiHardDrive,
  FiMinus,
  FiSearch,
  FiSettings,
  FiSquare,
  FiTerminal,
  FiX,
} from 'react-icons/fi';
import defaultWallpaper from '../assets/wallpapers/default.png';
import {
  requestNativeState,
  sendNativeCommand,
  subscribeNativeShell,
  type NativeShellApp,
  type NativeShellMessage,
  type NativeShellState,
} from './nativeBridge';
import './NativeShellSurface.css';

const PINNED_IDS = ['files', 'projects', 'terminal', 'wsl', 'browser', 'code', 'sysmon', 'settings'];
const DESKTOP_IDS = ['drive', 'files', 'projects', 'terminal', 'wsl', 'browser'];

function AppGlyph({ id }: { id: string }) {
  switch (id) {
    case 'files':
    case 'drive': return <FiFolder />;
    case 'projects': return <FiBox />;
    case 'terminal':
    case 'powershell':
    case 'wsl': return <FiTerminal />;
    case 'browser': return <FiGlobe />;
    case 'code': return <FiCode />;
    case 'sysmon':
    case 'health': return <FiActivity />;
    case 'systemdrive': return <FiHardDrive />;
    case 'settings': return <FiSettings />;
    default: return <FiGrid />;
  }
}

function launch(app: NativeShellApp) {
  sendNativeCommand(`app.launch:${app.id}`);
}

function formatMemory(usedMb: number, totalMb: number) {
  if (totalMb <= 0) return 'Indisponível';
  return `${(usedMb / 1024).toFixed(1)} / ${(totalMb / 1024).toFixed(1)} GB`;
}

export default function NativeShellSurface() {
  const [state, setState] = useState<NativeShellState | null>(null);
  const [launchpadOpen, setLaunchpadOpen] = useState(false);
  const [systemOpen, setSystemOpen] = useState(false);
  const [query, setQuery] = useState('');
  const searchRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const unsubscribe = subscribeNativeShell((message: NativeShellMessage) => {
      if (message.type === 'cloudos.state') {
        setState(message);
      } else if (message.type === 'cloudos.event' && message.event === 'focus-search') {
        setLaunchpadOpen(true);
        window.setTimeout(() => searchRef.current?.focus(), 0);
      }
    });
    sendNativeCommand('ready');
    requestNativeState();
    return unsubscribe;
  }, []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setLaunchpadOpen(false);
        setSystemOpen(false);
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  const apps = state?.apps ?? [];
  const appById = useMemo(() => new Map(apps.map((app) => [app.id, app])), [apps]);
  const pinned = PINNED_IDS.map((id) => appById.get(id)).filter(Boolean) as NativeShellApp[];
  const desktopApps = DESKTOP_IDS.map((id) => appById.get(id)).filter(Boolean) as NativeShellApp[];
  const filteredApps = useMemo(() => {
    const needle = query.trim().toLocaleLowerCase('pt-BR');
    if (!needle) return apps;
    return apps.filter((app) =>
      `${app.name} ${app.description} ${app.id}`.toLocaleLowerCase('pt-BR').includes(needle),
    );
  }, [apps, query]);
  const activeWindow = state?.windows.find((item) => item.active) ?? null;
  const surfaceStyle = { '--cloudos-wallpaper': `url(${defaultWallpaper})` } as CSSProperties;

  return (
    <main className="native-shell-surface" style={surfaceStyle}>
      <div className="native-shell-wallpaper" aria-hidden="true" />
      <div className="native-shell-aurora native-shell-aurora-a" aria-hidden="true" />
      <div className="native-shell-aurora native-shell-aurora-b" aria-hidden="true" />

      <header className="native-menubar glass">
        <button
          className="native-brand-button"
          onClick={() => {
            setLaunchpadOpen((value) => !value);
            setSystemOpen(false);
          }}
        >
          <span className="native-brand-mark">C</span>
          <strong>CloudOS</strong>
        </button>

        <div className="native-menubar-center">
          {activeWindow ? (
            <button
              className="native-active-title"
              title={activeWindow.title}
              onClick={() => sendNativeCommand(`window.focus:${activeWindow.hwnd}`)}
            >
              {activeWindow.title}
            </button>
          ) : (
            <span className="native-active-title native-active-title-idle">Área de Trabalho</span>
          )}
        </div>

        <div className="native-menubar-actions">
          <button
            className={`native-tiling-chip ${state?.tiling ? 'is-active' : ''}`}
            onClick={() => sendNativeCommand('tiling.toggle')}
            title="Alternar tiling nativo"
          >
            <FiColumns /> {state?.tiling ? 'Tiling' : 'Floating'}
          </button>
          <button
            className="native-system-chip"
            onClick={() => {
              setSystemOpen((value) => !value);
              setLaunchpadOpen(false);
            }}
          >
            <FiCpu />
            <span>{state?.stats.cpuAvailable ? `${state.stats.cpuPercent}%` : 'CPU'}</span>
          </button>
        </div>
      </header>

      <section className="native-desktop-icons" aria-label="Atalhos da área de trabalho">
        {desktopApps.map((app) => (
          <button
            className="native-desktop-icon"
            key={app.id}
            title={`Abrir ${app.name}`}
            onDoubleClick={() => launch(app)}
            onKeyDown={(event) => {
              if (event.key === 'Enter') launch(app);
            }}
          >
            <span className={`native-app-icon app-${app.id}`}><AppGlyph id={app.id} /></span>
            <span>{app.name}</span>
          </button>
        ))}
      </section>

      <aside className="native-status-stack">
        <article className="native-status-card glass">
          <div className="native-status-card-heading">
            <span><FiActivity /> Sistema</span>
            <span className="native-live-dot" />
          </div>
          <div className="native-metric-row"><span>CPU</span><strong>{state?.stats.cpuAvailable ? `${state.stats.cpuPercent}%` : '—'}</strong></div>
          <div className="native-meter"><i style={{ width: `${state?.stats.cpuAvailable ? state.stats.cpuPercent : 0}%` }} /></div>
          <div className="native-metric-row"><span>Memória</span><strong>{state?.stats.ramAvailable ? `${state.stats.ramPercent}%` : '—'}</strong></div>
          <div className="native-meter"><i style={{ width: `${state?.stats.ramAvailable ? state.stats.ramPercent : 0}%` }} /></div>
          <small>{state?.stats.ramAvailable ? formatMemory(state.stats.ramUsedMb, state.stats.ramTotalMb) : 'Telemetria aguardando'}</small>
        </article>

        <article className="native-status-card glass native-window-card">
          <div className="native-status-card-heading">
            <span><FiSquare /> Janelas</span>
            <strong>{state?.managedWindowCount ?? 0}</strong>
          </div>
          <p>Workspace {state?.workspace ?? 1} · HWNDs reais</p>
          {state?.stats.uptime && <small>Uptime {state.stats.uptime}</small>}
        </article>
      </aside>

      {launchpadOpen && (
        <section className="native-launchpad glass" role="dialog" aria-label="Aplicativos CloudOS">
          <div className="native-launchpad-head">
            <div><span className="native-eyebrow">CLOUDOS</span><h1>Aplicativos</h1></div>
            <button className="native-round-button" onClick={() => setLaunchpadOpen(false)}><FiX /></button>
          </div>
          <label className="native-search-box">
            <FiSearch />
            <input
              ref={searchRef}
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Pesquisar aplicativos..."
              autoComplete="off"
            />
          </label>
          <div className="native-launchpad-grid">
            {filteredApps.map((app) => (
              <button key={app.id} className="native-launchpad-app" onClick={() => { launch(app); setLaunchpadOpen(false); }}>
                <span className={`native-app-icon native-app-icon-large app-${app.id}`}><AppGlyph id={app.id} /></span>
                <span className="native-launchpad-copy"><strong>{app.name}</strong><small>{app.description}</small></span>
              </button>
            ))}
          </div>
        </section>
      )}

      {systemOpen && state && (
        <section className="native-control-center glass" role="dialog" aria-label="Central de Controle">
          <div className="native-control-head">
            <div><span className="native-eyebrow">CENTRAL DE CONTROLE</span><h2>CloudOS Native</h2></div>
            <button className="native-round-button" onClick={() => setSystemOpen(false)}><FiX /></button>
          </div>
          <div className="native-control-grid">
            <button className={`native-control-tile ${state.tiling ? 'is-active' : ''}`} onClick={() => sendNativeCommand('tiling.toggle')}>
              <FiColumns /><span><strong>Tiling</strong><small>{state.tiling ? 'Ativado' : 'Desativado'}</small></span>
            </button>
            <button className="native-control-tile" onClick={() => { const app = appById.get('settings'); if (app) launch(app); }}>
              <FiSettings /><span><strong>Configurações</strong><small>Nativas</small></span>
            </button>
          </div>
          <div className="native-control-metrics">
            <div><span>CPU</span><strong>{state.stats.cpuAvailable ? `${state.stats.cpuPercent}%` : '—'}</strong></div>
            <div><span>RAM</span><strong>{state.stats.ramAvailable ? `${state.stats.ramPercent}%` : '—'}</strong></div>
            <div><span>Disco livre</span><strong>{state.stats.diskAvailable ? `${state.stats.diskFreeGb} GB` : '—'}</strong></div>
          </div>
        </section>
      )}

      <footer className="native-dock-region">
        <div className="native-dock glass">
          <button className="native-dock-launchpad" onClick={() => { setLaunchpadOpen((value) => !value); setSystemOpen(false); }} title="Launchpad"><FiGrid /></button>
          <span className="native-dock-separator" />
          {pinned.map((app) => (
            <button key={app.id} className="native-dock-app" title={app.name} onClick={() => launch(app)}>
              <span className={`native-app-icon app-${app.id}`}><AppGlyph id={app.id} /></span>
              <span className="native-dock-label">{app.name}</span>
            </button>
          ))}

          {state && state.windows.length > 0 && <span className="native-dock-separator" />}
          <div className="native-running-tasks">
            {state?.windows.slice(0, 6).map((item) => (
              <button
                key={item.hwnd}
                className={`native-task-pill ${item.active ? 'is-active' : ''}`}
                title={item.title}
                onClick={() => sendNativeCommand(`window.focus:${item.hwnd}`)}
              >
                <span>{item.title.slice(0, 22)}</span>
              </button>
            ))}
          </div>

          <span className="native-dock-separator" />
          <div className="native-workspaces" aria-label="Workspaces">
            {[1, 2, 3, 4].map((workspace) => (
              <button
                key={workspace}
                className={state?.workspace === workspace ? 'is-active' : ''}
                onClick={() => sendNativeCommand(`workspace.switch:${workspace}`)}
              >{workspace}</button>
            ))}
          </div>
        </div>
      </footer>

      {activeWindow && (
        <div className="native-window-controls glass" aria-label="Controles da janela ativa">
          <button title="Snap esquerda" onClick={() => sendNativeCommand('window.snap:left')}><FiColumns /></button>
          <button title="Minimizar" onClick={() => sendNativeCommand('window.minimize')}><FiMinus /></button>
          <button title="Maximizar" onClick={() => sendNativeCommand('window.maximize')}><FiSquare /></button>
          <button className="is-danger" title="Fechar" onClick={() => sendNativeCommand('window.close')}><FiX /></button>
        </div>
      )}

      {!state && (
        <div className="native-bridge-status glass"><span className="native-live-dot is-loading" />Conectando à autoridade nativa do CloudOS…</div>
      )}
    </main>
  );
}
