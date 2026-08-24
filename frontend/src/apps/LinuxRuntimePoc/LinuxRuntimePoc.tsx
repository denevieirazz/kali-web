import { useEffect, useMemo, useRef, useState } from 'react';
import { useWindowManager } from '../../stores/windowManager';
import { apiClient, resolveApiUrl } from '../../services/apiClient';
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
  firstFramePaintedMs: number | null;
  canvasWidth: number | null;
  canvasHeight: number | null;
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

type PreflightStatus = 'PASS' | 'WARN' | 'FAIL';
type PreflightCheck = {
  id: string;
  layer: string;
  status: PreflightStatus;
  code: string;
  component: string;
  cause: string;
  evidence: string;
  durationMs: number | null;
};
type PreflightBoundary = {
  status: PreflightStatus;
  code: string;
  component: string;
  cause: string;
  evidence: string;
};
type PhysicalPreflight = {
  runId: string;
  ownerId: string;
  phase: 'static' | 'awaiting_iframe' | 'complete';
  decision: 'GO' | 'NO_GO';
  readyToClickXclock: boolean;
  distribution: string | null;
  display: number | null;
  port: number | null;
  clientUrl: string | null;
  boundaries: Record<string, PreflightBoundary>;
  checks: PreflightCheck[];
  metrics: Record<string, number>;
  artifacts: {
    root: string;
    report: string;
    windowBaseline: string;
    screenshots: string;
    logs: string;
    telemetry: string;
    runLog: string | null;
    runTelemetry: string | null;
  };
};
type PendingPreflightIframe = {
  runId: string;
  clientUrl: string;
  requestedAt: number;
};

type Props = { windowId: string };

const pendingOwnerCleanup = new Map<string, number>();
const PREFLIGHT_BOUNDARIES = ['WSL', 'DISTRO', 'XPRA', 'TRANSPORTE', 'PROXY', 'IFRAME'];

function formatMs(value: number | null | undefined) {
  return value === null || value === undefined ? '—' : `${Math.round(value)} ms`;
}

export function getReconciledReadinessItem(
  name: string,
  readinessCheck: ReadinessCheck | undefined,
  physicalPreflight: PhysicalPreflight | null,
  preflightBusy: boolean,
): { label: 'PASS' | 'FAIL' | 'TESTANDO' | 'NÃO TESTADO'; dataOk: 'true' | 'false' | 'testing' | 'untested' } {
  if (preflightBusy && ['windowsLoopback', 'websocket'].includes(name)) {
    return { label: 'TESTANDO', dataOk: 'testing' };
  }

  if (physicalPreflight) {
    if (name === 'windowsLoopback') {
      const check = physicalPreflight.checks.find(c => c.id === 'loopback-tcp');
      if (check?.status === 'PASS') return { label: 'PASS', dataOk: 'true' };
      if (check?.status === 'FAIL') return { label: 'FAIL', dataOk: 'false' };
      if (physicalPreflight.decision === 'NO_GO' && !check) return { label: 'NÃO TESTADO', dataOk: 'untested' };
    }
    if (name === 'websocket') {
      const check = physicalPreflight.checks.find(c => c.id === 'direct-websocket');
      if (check?.status === 'PASS') return { label: 'PASS', dataOk: 'true' };
      if (check?.status === 'FAIL') return { label: 'FAIL', dataOk: 'false' };
      if (physicalPreflight.decision === 'NO_GO' && !check) return { label: 'NÃO TESTADO', dataOk: 'untested' };
    }
  }

  if (!readinessCheck || readinessCheck.ok === null) {
    return { label: 'NÃO TESTADO', dataOk: 'untested' };
  }
  if (readinessCheck.ok === true) {
    return { label: 'PASS', dataOk: 'true' };
  }
  return { label: 'FAIL', dataOk: 'false' };
}

function preflightDataOk(status: PreflightStatus | undefined) {
  if (status === 'PASS') return 'true';
  if (status === 'FAIL') return 'false';
  return 'pending';
}

export default function LinuxRuntimePoc({ windowId }: Props) {
  const [status, setStatus] = useState<PocStatus | null>(null);
  const [readiness, setReadiness] = useState<PocReadiness | null>(null);
  const [physicalPreflight, setPhysicalPreflight] = useState<PhysicalPreflight | null>(null);
  const [pendingPreflightIframe, setPendingPreflightIframe] = useState<PendingPreflightIframe | null>(null);
  const [selectedApp, setSelectedApp] = useState<string>(() => {
    const win = useWindowManager.getState().getWindow(windowId);
    return typeof win?.params?.app === 'string' ? win.params.app : '';
  });
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [preflightBusy, setPreflightBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const preflightIframeRef = useRef<HTMLIFrameElement | null>(null);
  const observerRef = useRef<MutationObserver | null>(null);
  const preflightFinalizeRef = useRef(false);
  const preflightConnectionTimerRef = useRef<number | null>(null);
  const actionStartedAt = useRef(new Map<string, number>());
  const frameRequestedAt = useRef(new Map<string, number>());
  const reconnectCounts = useRef(new Map<string, number>());
  const lastHealth = useRef(new Map<string, boolean>());

  const sessions = status?.sessions ?? [];
  const activeSession = sessions.find(session => session.id === activeSessionId) ?? sessions[0] ?? null;
  const readyUrl = activeSession && ['ready', 'degraded'].includes(activeSession.state) && activeSession.clientUrl
    ? resolveApiUrl(activeSession.clientUrl)
    : null;
  const selectedTitle = useMemo(
    () => status?.apps.find(app => app.id === selectedApp)?.title ?? selectedApp,
    [selectedApp, status?.apps],
  );
  const appAlreadyRunning = sessions.some(session => session.app === selectedApp && ['starting', 'ready', 'degraded'].includes(session.state));
  const controlsBusy = busy || preflightBusy;
  const preflightProblem = physicalPreflight?.checks.find(check => check.status === 'FAIL')
    ?? physicalPreflight?.checks.find(check => check.status === 'WARN')
    ?? null;

  async function refresh() {
    const next = await apiClient<PocStatus>(`/api/linux-runtime/poc1?ownerId=${encodeURIComponent(windowId)}`);
    setStatus(next);
    setSelectedApp(current => next.apps.some(app => app.id === current) ? current : next.apps[0]?.id ?? '');
    setActiveSessionId(current => current && next.sessions.some(session => session.id === current)
      ? current
      : next.sessions[0]?.id ?? null);
    return next;
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
    void refresh().catch(cause => {
      setError(cause instanceof Error ? cause.message : String(cause));
    });
    return () => {
      observerRef.current?.disconnect();
      if (preflightConnectionTimerRef.current !== null) {
        window.clearTimeout(preflightConnectionTimerRef.current);
        preflightConnectionTimerRef.current = null;
      }
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
    if (!selectedApp) {
      setReadiness(null);
      return;
    }
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

  async function runPhysicalPreflight() {
    setPreflightBusy(true);
    setError(null);
    setPhysicalPreflight(null);
    setPendingPreflightIframe(null);
    preflightFinalizeRef.current = false;
    if (preflightConnectionTimerRef.current !== null) {
      window.clearTimeout(preflightConnectionTimerRef.current);
      preflightConnectionTimerRef.current = null;
    }
    try {
      const result = await apiClient<PhysicalPreflight>('/api/linux-runtime/poc1/preflight', {
        method: 'POST',
        body: JSON.stringify({ ownerId: windowId }),
        timeoutMs: 90_000,
      });
      setPhysicalPreflight(result);
      if (result.phase === 'awaiting_iframe' && result.clientUrl) {
        setPendingPreflightIframe({
          runId: result.runId,
          clientUrl: result.clientUrl,
          requestedAt: performance.now(),
        });
        return;
      }
      setPreflightBusy(false);
    } catch (cause) {
      setError(`POC1_PREFLIGHT_API_FAILED: ${cause instanceof Error ? cause.message : String(cause)}`);
      setPreflightBusy(false);
    }
  }

  async function finalizePreflightIframe(
    pending: PendingPreflightIframe,
    evidence: {
      frameAttached?: boolean;
      frameLoaded?: boolean;
      loadMs?: number;
      signals?: string[];
      errorCode?: string;
      errorMessage?: string;
      taxonomy?: string;
    },
  ) {
    if (preflightFinalizeRef.current) return;
    preflightFinalizeRef.current = true;
    if (preflightConnectionTimerRef.current !== null) {
      window.clearTimeout(preflightConnectionTimerRef.current);
      preflightConnectionTimerRef.current = null;
    }
    try {
      const result = await apiClient<PhysicalPreflight>(`/api/linux-runtime/poc1/preflight/${encodeURIComponent(pending.runId)}/finalize`, {
        method: 'POST',
        body: JSON.stringify({ ownerId: windowId, evidence }),
        timeoutMs: 25_000,
      });
      setPhysicalPreflight(result);
      setPendingPreflightIframe(null);
      await Promise.all([refresh(), refreshReadiness(selectedApp)]).catch(() => undefined);
    } catch (cause) {
      setError(`POC1_PREFLIGHT_FINALIZE_FAILED: ${cause instanceof Error ? cause.message : String(cause)}`);
      setPendingPreflightIframe(null);
    } finally {
      setPreflightBusy(false);
    }
  }

  function onPreflightFrameLoad() {
    const pending = pendingPreflightIframe;
    if (!pending || preflightFinalizeRef.current) return;
    const loadedAt = performance.now();
    const loadMs = loadedAt - pending.requestedAt;

    // Aguarda o script HTML5 do iframe iniciar a conexão WebSocket antes de finalizar a correlação
    window.setTimeout(() => {
      void finalizePreflightIframe(pending, {
        frameAttached: true,
        frameLoaded: true,
        loadMs,
        signals: ['FRAME_ATTACH', 'NAVIGATION'],
      });
    }, 1200);
  }

  async function start() {
    if (!selectedApp) return;
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

  async function reportClientMetrics(session: PocSession, values: { iframeLoadMs?: number; firstRemoteWindowMs?: number; firstFramePaintedMs?: number; canvasWidth?: number; canvasHeight?: number }) {
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

  useEffect(() => {
    const handleMessage = (event: MessageEvent) => {
      if (event.data?.type !== 'xpra-render-event') return;
      const session = activeSession;
      if (!session || event.data.sessionId !== session.id) return;
      if (iframeRef.current && event.source !== iframeRef.current.contentWindow) return;
      const actionStart = actionStartedAt.current.get(session.id) ?? performance.now();
      const width = Number(event.data.width);
      const height = Number(event.data.height);
      const validWidth = Number.isFinite(width) && width > 0 ? width : undefined;
      const validHeight = Number.isFinite(height) && height > 0 ? height : undefined;
      if (event.data.name === 'window-created') {
        void reportClientMetrics(session, {
          firstRemoteWindowMs: performance.now() - actionStart,
          canvasWidth: validWidth,
          canvasHeight: validHeight,
        });
      } else if (event.data.name === 'frame-painted') {
        void reportClientMetrics(session, {
          firstFramePaintedMs: performance.now() - actionStart,
          canvasWidth: validWidth,
          canvasHeight: validHeight,
        });
      }
    };
    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
  }, [activeSession, windowId]);

  function onFrameLoad() {
    const session = activeSession;
    if (!session) return;
    const requested = frameRequestedAt.current.get(session.id) ?? performance.now();
    void reportClientMetrics(session, { iframeLoadMs: performance.now() - requested });
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
          <button type="button" onClick={runPhysicalPreflight} disabled={controlsBusy || sessions.length > 0}>
            {preflightBusy ? 'Preflight em execução…' : 'Linux Runtime Preflight'}
          </button>
          <select
            aria-label="Aplicativo Linux da POC"
            value={selectedApp}
            disabled={controlsBusy}
            onChange={event => setSelectedApp(event.target.value)}
          >
            {(status?.apps ?? []).map(app => (
              <option key={app.id} value={app.id}>{app.title}</option>
            ))}
          </select>
          <button type="button" onClick={start} disabled={!selectedApp || controlsBusy || appAlreadyRunning || sessions.length >= (status?.maxAppsPerWindow ?? 4)}>
            {busy ? 'Processando…' : appAlreadyRunning ? `${selectedTitle} ativo` : `Abrir ${selectedTitle}`}
          </button>
          {readiness?.errorCode === 'LINUX_POC_ORPHANED_SESSION' && (
            <button type="button" onClick={cleanupOrphans} disabled={controlsBusy}>Limpar órfãos</button>
          )}
        </div>
      </header>

      <section className="linux-runtime-poc__readiness" aria-label="Physical Preflight POC 1">
        <strong>
          {!physicalPreflight
            ? 'PHYSICAL PREFLIGHT NÃO EXECUTADO'
            : physicalPreflight.phase === 'awaiting_iframe'
              ? 'PHYSICAL PREFLIGHT VALIDANDO IFRAME'
              : `PHYSICAL PREFLIGHT ${physicalPreflight.decision === 'GO' ? 'GO' : 'NO GO'}`}
        </strong>
        <div>
          {PREFLIGHT_BOUNDARIES.map(name => (
            <span key={name} data-ok={preflightDataOk(physicalPreflight?.boundaries?.[name]?.status)}>
              {name}: {physicalPreflight?.boundaries?.[name]?.status ?? 'PENDENTE'}
            </span>
          ))}
        </div>
        {physicalPreflight && (
          <small>
            {physicalPreflight.readyToClickXclock
              ? `PRONTO PARA ABRIR XCLOCK · report=${physicalPreflight.artifacts.report}`
              : preflightProblem
                ? `${preflightProblem.code} · ${preflightProblem.component} · ${preflightProblem.cause} · ${preflightProblem.evidence}`
                : `run=${physicalPreflight.runId} · phase=${physicalPreflight.phase}`}
          </small>
        )}
      </section>

      <section className="linux-runtime-poc__readiness" aria-label="Readiness POC 1">
        <strong>
          {physicalPreflight?.decision === 'GO'
            ? 'READINESS OK · PREFLIGHT GO'
            : readiness?.ready
              ? 'READINESS OK'
              : `READINESS ${readiness?.errorCode ?? 'VERIFICANDO'}`}
        </strong>
        <div>
          {readinessOrder.map(name => {
            const item = getReconciledReadinessItem(name, readiness?.checks?.[name], physicalPreflight, preflightBusy);
            return (
              <span key={name} data-ok={item.dataOk}>
                {name}: {item.label}
              </span>
            );
          })}
        </div>
        {!readiness?.ready && readiness?.error && <small>{readiness.error}</small>}
      </section>

      {pendingPreflightIframe && (
        <iframe
          ref={preflightIframeRef}
          key={pendingPreflightIframe.runId}
          title="CloudOS Linux Runtime Preflight — Xpra HTML5"
          src={pendingPreflightIframe.clientUrl}
          sandbox="allow-scripts allow-forms allow-pointer-lock"
          referrerPolicy="no-referrer"
          onLoad={onPreflightFrameLoad}
          aria-hidden="true"
          tabIndex={-1}
          style={{ position: 'fixed', left: '-10000px', top: 0, width: 640, height: 480, opacity: 0, pointerEvents: 'none' }}
        />
      )}

      {sessions.length > 0 && (
        <nav className="linux-runtime-poc__sessions" aria-label="Sessões Linux ativas">
          {sessions.map(session => (
            <button
              type="button"
              key={session.id}
              className={session.id === activeSession?.id ? 'active' : ''}
              onClick={() => setActiveSessionId(session.id)}
            >
              {session.title} <small>{session.metrics.firstFramePaintedMs ? 'renderizado' : session.metrics.firstRemoteWindowMs ? 'desenhando' : 'iniciando'}</small>
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
            sandbox="allow-scripts allow-forms allow-pointer-lock allow-same-origin"
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
                  ? 'Pré-requisitos presentes. Execute Linux Runtime Preflight antes da primeira prova física; nenhum aplicativo é iniciado pelo preflight.'
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
            <div><strong>Render</strong><span>iframe {formatMs(activeSession.metrics.iframeLoadMs)}</span><span>1ª janela {formatMs(activeSession.metrics.firstRemoteWindowMs)}</span><span>pintado {formatMs(activeSession.metrics.firstFramePaintedMs)}</span><span>canvas {activeSession.metrics.canvasWidth ? `${activeSession.metrics.canvasWidth}x${activeSession.metrics.canvasHeight}` : '—'}</span></div>
            <div><strong>Lifecycle</strong><span>restart {activeSession.metrics.restartCount}</span><span>reconnect {activeSession.metrics.reconnectCount}</span><span>falhas {activeSession.metrics.healthFailures}</span></div>
            <div><strong>Health</strong><span>{activeHealth?.healthy ? 'saudável' : activeHealth?.classification ?? activeSession.state}</span><span>TCP {activeHealth?.windowsTcp?.ok === false ? 'falha' : 'ok'}</span><span>WS {activeHealth?.websocket?.ok === false ? 'falha' : 'ok'}</span></div>
            <div className="linux-runtime-poc__session-actions">
              <button type="button" onClick={() => restart(activeSession)} disabled={controlsBusy}>Restart</button>
              <button type="button" onClick={() => stop(activeSession)} disabled={controlsBusy}>Stop</button>
            </div>
          </>
        ) : physicalPreflight ? (
          <>
            <div><strong>Preflight</strong><span>{physicalPreflight.decision}</span><span>fase {physicalPreflight.phase}</span><span>nenhum app executado</span></div>
            <div><strong>Dry Run</strong><span>DISPLAY {physicalPreflight.display === null ? '—' : `:${physicalPreflight.display}`}</span><span>porta {physicalPreflight.port ?? '—'}</span><span>iframe {formatMs(physicalPreflight.metrics.iframeConnectionMs)}</span></div>
            <div><strong>Forensics</strong><span>baseline {physicalPreflight.artifacts.windowBaseline}</span><span>logs {physicalPreflight.artifacts.logs}</span></div>
          </>
        ) : (
          <span>Telemetria aguardando preflight ou sessão real.</span>
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
