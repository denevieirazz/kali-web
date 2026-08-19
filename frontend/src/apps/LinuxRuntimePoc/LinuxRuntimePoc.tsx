import { useEffect, useMemo, useRef, useState } from 'react';
import { apiClient } from '../../services/apiClient';
import './LinuxRuntimePoc.css';

type PocApp = { id: string; command: string; title: string };
type PocMetrics = {
  preflightMs: number | null;
  wslServerReadyMs: number | null;
  windowsTransportReadyMs: number | null;
  bootMs: number | null;
  websocketHandshakeMs: number | null;
  lastHealthMs: number | null;
  iframeLoadMs: number | null;
  firstRemoteWindowMs: number | null;
  reconnectCount: number;
  restartCount: number;
  healthFailures: number;
  proxyHttpRequests: number;
  proxyWebSocketConnections: number;
};
type PocHealth = {
  healthy: boolean;
  checkedAt: string;
  classification?: string | null;
  linux?: { ok: boolean; durationMs?: number; error?: string };
  windowsTcp?: { ok: boolean; durationMs?: number; error?: string };
  http?: { ok: boolean; durationMs?: number; error?: string };
  websocket?: { ok: boolean; durationMs?: number; error?: string };
};
type PocSession = {
  id: string;
  ownerId: string;
  app: string;
  title: string;
  distribution: string;
  port: number;
  display: number;
  state: 'starting' | 'ready' | 'degraded' | 'failed' | 'stopping' | 'stopped';
  startedAt: string;
  clientUrl: string | null;
  xpraVersion: string;
  error?: string | null;
  errorCode?: string | null;
  health?: PocHealth | null;
  metrics: PocMetrics;
};
type PocStatus = {
  mode: string;
  transport: string;
  externalWindowsExpected: number;
  maxAppsPerWindow: number;
  apps: PocApp[];
  sessions: PocSession[];
};
type ReadinessCheck = { ok: boolean | null; [key: string]: unknown };
type PocReadiness = {
  ready: boolean;
  app?: string;
  distribution?: string;
  error?: string;
  errorCode?: string;
  durationMs: number;
  checks: Record<string, ReadinessCheck>;
};

type Props = { windowId: string };

const pendingOwnerCleanup = new Map<string, number>();

function formatMs(value: number | null | undefined) {
  return value === null || value === undefined ? '—' : `${Math.round(value)} ms`;
}

function checkLabel(check: ReadinessCheck | undefined) {
  if (!check || check.ok === null) return 'PENDENTE';
  return check.ok ? 'OK' : 'FALHA';
}

export default function LinuxRuntimePoc({ windowId }: Props) {
  const [status, setStatus] = useState<PocStatus | null>(null);
  const [readiness, setReadiness] = useState<PocReadiness | null>(null);
  const [selectedApp, setSelectedApp] = useState('xclock');
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const observerRef = useRef<MutationObserver | null>(null);
  const actionStartedAt = useRef(new Map<string, number>());
  const frameRequestedAt = useRef(new Map<string, number>());
  const reconnectCounts = useRef(new Map<string, number>());
  const lastHealth = useRef(new Map<string, boolean>());

  const sessions = status?.sessions ?? [];
  const activeSession = sessions.find(session => session.id === activeSessionId) ?? sessions[0] ?? null;
  const readyUrl = activeSession && ['ready', 'degraded'].includes(activeSession.state) ? activeSession.clientUrl : null;
  const selectedTitle = useMemo(
    () => status?.apps.find(app => app.id === selectedApp)?.title ?? selectedApp,
    [selectedApp, status?.apps],
  );
  const appAlreadyRunning = sessions.some(session => session.app === selectedApp && ['starting', 'ready', 'degraded'].includes(session.state));

  async function refresh() {
    const next = await apiClient<PocStatus>(`/api/linux-runtime/poc1?ownerId=${encodeURIComponent(windowId)}`);
    setStatus(next);
    setActiveSessionId(current => current && next.sessions.some(session => session.id === current)
      ? current
      : next.sessions[0]?.id ?? null);
  }

  async function refreshReadiness(app = selectedApp) {
    const next = await apiClient<PocReadiness>(`/api/linux-runtime/poc1/readiness?app=${encodeURIComponent(app)}`);
    setReadiness(next);
    return next;
  }

  useEffect(() => {
    const pending = pendingOwnerCleanup.get(windowId);
    if (pending !== undefined) {
      window.clearTimeout(pending);
      pendingOwnerCleanup.delete(windowId);
    }
    void Promise.all([refresh(), refreshReadiness('xclock')]).catch(cause => {
      setError(cause instanceof Error ? cause.message : String(cause));
    });
    return () => {
      observerRef.current?.disconnect();
      const timer = window.setTimeout(() => {
        pendingOwnerCleanup.delete(windowId);
        void apiClient('/api/linux-runtime/poc1/cleanup', {
          method: 'POST',
          body: JSON.stringify({ ownerId: windowId }),
          timeoutMs: 4000,
          keepalive: true,
          suppressUnauthorizedHandler: true,
        }).catch(() => undefined);
      }, 1000);
      pendingOwnerCleanup.set(windowId, timer);
    };
    // windowId identifica o owner do lifecycle; refresh é intencionalmente executado uma vez por mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [windowId]);

  useEffect(() => {
    void refreshReadiness(selectedApp).catch(cause => setError(cause instanceof Error ? cause.message : String(cause)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedApp]);

  const sessionIds = sessions.map(session => session.id).sort().join(',');
  useEffect(() => {
    if (!sessionIds) return undefined;
    let disposed = false;
    const poll = async () => {
      const ids = sessionIds.split(',').filter(Boolean);
      for (const id of ids) {
        try {
          const result = await apiClient<{ session: PocSession; health: PocHealth }>(`/api/linux-runtime/poc1/sessions/${encodeURIComponent(id)}/health`, { timeoutMs: 7000 });
          if (disposed) return;
          const previous = lastHealth.current.get(id);
          lastHealth.current.set(id, result.health.healthy);
          if (previous === false && result.health.healthy) {
            reconnectCounts.current.set(id, (reconnectCounts.current.get(id) ?? 0) + 1);
          }
          setStatus(current => current ? {
            ...current,
            sessions: current.sessions.map(item => item.id === id ? result.session : item),
          } : current);
        } catch (cause) {
          if (!disposed) setError(cause instanceof Error ? cause.message : String(cause));
        }
      }
    };
    const interval = window.setInterval(() => { void poll(); }, 10_000);
    void poll();
    return () => {
      disposed = true;
      window.clearInterval(interval);
    };
  }, [sessionIds]);

  useEffect(() => {
    if (activeSession?.id && readyUrl) frameRequestedAt.current.set(activeSession.id, performance.now());
  }, [activeSession?.id, readyUrl]);

  async function start() {
    setBusy(true);
    setError(null);
    const started = performance.now();
    try {
      const preflight = await refreshReadiness(selectedApp);
      if (!preflight.ready) {
        setError(`${preflight.errorCode ?? 'POC1_NOT_READY'}: ${preflight.error ?? 'Pré-requisitos incompletos.'}`);
        return;
      }
      const result = await apiClient<{ session: PocSession }>('/api/linux-runtime/poc1/start', {
        method: 'POST',
        body: JSON.stringify({ app: selectedApp, ownerId: windowId }),
        timeoutMs: 40_000,
      });
      actionStartedAt.current.set(result.session.id, started);
      frameRequestedAt.current.set(result.session.id, performance.now());
      setStatus(current => current ? {
        ...current,
        sessions: [...current.sessions.filter(item => item.id !== result.session.id), result.session],
      } : current);
      setActiveSessionId(result.session.id);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
      await refresh().catch(() => undefined);
    } finally {
      setBusy(false);
    }
  }

  async function stop(session: PocSession) {
    setBusy(true);
    setError(null);
    try {
      await apiClient(`/api/linux-runtime/poc1/sessions/${encodeURIComponent(session.id)}/stop`, {
        method: 'POST',
        body: JSON.stringify({ ownerId: windowId }),
        timeoutMs: 10_000,
      });
      await refresh();
      await refreshReadiness(selectedApp);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }

  async function restart(session: PocSession) {
    setBusy(true);
    setError(null);
    const started = performance.now();
    try {
      const result = await apiClient<{ session: PocSession }>(`/api/linux-runtime/poc1/sessions/${encodeURIComponent(session.id)}/restart`, {
        method: 'POST',
        body: JSON.stringify({ ownerId: windowId }),
        timeoutMs: 45_000,
      });
      actionStartedAt.current.set(result.session.id, started);
      frameRequestedAt.current.set(result.session.id, performance.now());
      await refresh();
      setActiveSessionId(result.session.id);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }

  async function cleanupOrphans() {
    setBusy(true);
    setError(null);
    try {
      await apiClient('/api/linux-runtime/poc1/cleanup', {
        method: 'POST',
        body: JSON.stringify({ ownerId: windowId, orphansOnly: true }),
        timeoutMs: 12_000,
      });
      await Promise.all([refresh(), refreshReadiness(selectedApp)]);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }

  async function reportClientMetrics(session: PocSession, values: { iframeLoadMs?: number; firstRemoteWindowMs?: number }) {
    const reconnectCount = reconnectCounts.current.get(session.id) ?? 0;
    try {
      const result = await apiClient<{ session: PocSession }>(`/api/linux-runtime/poc1/sessions/${encodeURIComponent(session.id)}/client-metrics`, {
        method: 'POST',
        body: JSON.stringify({ ownerId: windowId, reconnectCount, ...values }),
        timeoutMs: 3000,
      });
      setStatus(current => current ? {
        ...current,
        sessions: current.sessions.map(item => item.id === result.session.id ? result.session : item),
      } : current);
    } catch {
      // Telemetria nunca deve derrubar a superfície da POC.
    }
  }

  function onFrameLoad() {
    const session = activeSession;
    const frame = iframeRef.current;
    if (!session || !frame) return;
    const requested = frameRequestedAt.current.get(session.id) ?? performance.now();
    void reportClientMetrics(session, { iframeLoadMs: performance.now() - requested });

    observerRef.current?.disconnect();
    try {
      const document = frame.contentDocument;
      if (!document) return;
      const measureFirstWindow = () => {
        const xpraWindow = document.querySelector('#screen .window');
        if (!xpraWindow) return false;
        const actionStart = actionStartedAt.current.get(session.id) ?? requested;
        void reportClientMetrics(session, { firstRemoteWindowMs: performance.now() - actionStart });
        observerRef.current?.disconnect();
        return true;
      };
      if (measureFirstWindow()) return;
      const screen = document.querySelector('#screen') ?? document.body;
      const observer = new MutationObserver(() => { measureFirstWindow(); });
      observer.observe(screen, { childList: true, subtree: true });
      observerRef.current = observer;
    } catch (cause) {
      setError(`POC1_RENDER_TELEMETRY_UNAVAILABLE: ${cause instanceof Error ? cause.message : String(cause)}`);
    }
  }

  const activeHealth = activeSession?.health;
  const readinessOrder = ['wsl', 'distribution', 'xpra', 'app', 'port', 'windowsLoopback', 'websocket', 'orphans'];

  return (
    <div className="linux-runtime-poc" data-poc="cloudos-linux-runtime-xpra">
      <header className="linux-runtime-poc__bar">
        <div>
          <strong>Linux Runtime POC 1</strong>
          <span>{activeSession ? `${activeSession.distribution} · DISPLAY :${activeSession.display}` : 'Xpra HTML5 · CloudOS origin proxy'}</span>
        </div>
        <div className="linux-runtime-poc__controls">
          <select
            aria-label="Aplicativo Linux da POC"
            value={selectedApp}
            disabled={busy}
            onChange={event => setSelectedApp(event.target.value)}
          >
            {(status?.apps ?? [{ id: 'xclock', command: 'xclock', title: 'XClock' }]).map(app => (
              <option key={app.id} value={app.id}>{app.title}</option>
            ))}
          </select>
          <button type="button" onClick={start} disabled={busy || appAlreadyRunning || sessions.length >= (status?.maxAppsPerWindow ?? 4)}>
            {busy ? 'Processando…' : appAlreadyRunning ? `${selectedTitle} ativo` : `Abrir ${selectedTitle}`}
          </button>
          {readiness?.errorCode === 'LINUX_POC_ORPHANED_SESSION' && (
            <button type="button" onClick={cleanupOrphans} disabled={busy}>Limpar órfãos</button>
          )}
        </div>
      </header>

      <section className="linux-runtime-poc__readiness" aria-label="Readiness POC 1">
        <strong>{readiness?.ready ? 'READINESS OK' : `READINESS ${readiness?.errorCode ?? 'VERIFICANDO'}`}</strong>
        <div>
          {readinessOrder.map(name => (
            <span key={name} data-ok={String(readiness?.checks?.[name]?.ok ?? 'pending')}>
              {name}: {checkLabel(readiness?.checks?.[name])}
            </span>
          ))}
        </div>
        {!readiness?.ready && readiness?.error && <small>{readiness.error}</small>}
      </section>

      {sessions.length > 0 && (
        <nav className="linux-runtime-poc__sessions" aria-label="Sessões Linux ativas">
          {sessions.map(session => (
            <button
              type="button"
              key={session.id}
              className={session.id === activeSession?.id ? 'active' : ''}
              onClick={() => setActiveSessionId(session.id)}
            >
              {session.title} <small>{session.state}</small>
            </button>
          ))}
        </nav>
      )}

      <section className="linux-runtime-poc__surface" data-contained-surface={readyUrl ? 'ready' : 'idle'}>
        {readyUrl && activeSession ? (
          <iframe
            ref={iframeRef}
            key={activeSession.id}
            title={`${activeSession.title} — Xpra HTML5`}
            src={readyUrl}
            className="linux-runtime-poc__frame"
            sandbox="allow-scripts allow-same-origin allow-forms allow-pointer-lock"
            allow="clipboard-read; clipboard-write"
            referrerPolicy="no-referrer"
            onLoad={onFrameLoad}
          />
        ) : (
          <div className="linux-runtime-poc__state" role="status">
            <strong>{activeSession?.state === 'failed' ? 'POC bloqueada' : 'Nenhuma superfície Linux ativa'}</strong>
            <p>
              {activeSession?.state === 'failed'
                ? `${activeSession.errorCode ?? 'XPRA_START_FAILED'}: ${activeSession.error ?? 'Xpra não iniciou.'}`
                : readiness?.ready
                  ? 'Pré-requisitos presentes. Inicie xclock, xeyes, xterm ou gedit; nenhuma instalação será feita.'
                  : readiness?.error ?? 'Validando WSL, distro, Xpra, app e portas.'}
            </p>
            {error && <pre>{error}</pre>}
          </div>
        )}
      </section>

      <aside className="linux-runtime-poc__telemetry" aria-label="Telemetria da POC 1">
        {activeSession ? (
          <>
            <div><strong>Runtime</strong><span>boot {formatMs(activeSession.metrics.bootMs)}</span><span>WS {formatMs(activeSession.metrics.websocketHandshakeMs)}</span><span>health {formatMs(activeSession.metrics.lastHealthMs)}</span></div>
            <div><strong>Render</strong><span>iframe {formatMs(activeSession.metrics.iframeLoadMs)}</span><span>1ª janela {formatMs(activeSession.metrics.firstRemoteWindowMs)}</span></div>
            <div><strong>Lifecycle</strong><span>restart {activeSession.metrics.restartCount}</span><span>reconnect {activeSession.metrics.reconnectCount}</span><span>falhas {activeSession.metrics.healthFailures}</span></div>
            <div><strong>Health</strong><span>{activeHealth?.healthy ? 'saudável' : activeHealth?.classification ?? activeSession.state}</span><span>TCP {activeHealth?.windowsTcp?.ok === false ? 'falha' : 'ok'}</span><span>WS {activeHealth?.websocket?.ok === false ? 'falha' : 'ok'}</span></div>
            <div className="linux-runtime-poc__session-actions">
              <button type="button" onClick={() => restart(activeSession)} disabled={busy}>Restart</button>
              <button type="button" onClick={() => stop(activeSession)} disabled={busy}>Stop</button>
            </div>
          </>
        ) : (
          <span>Telemetria aguardando sessão real.</span>
        )}
      </aside>

      <footer className="linux-runtime-poc__evidence">
        <span>Transport: Xpra HTML5/WebSocket via CloudOS proxy</span>
        <span>Windows externos esperados: {status?.externalWindowsExpected ?? 0}</span>
        <span>Sessões: {sessions.length}/{status?.maxAppsPerWindow ?? 4}</span>
        <span>Owner: {windowId}</span>
      </footer>
    </div>
  );
}
