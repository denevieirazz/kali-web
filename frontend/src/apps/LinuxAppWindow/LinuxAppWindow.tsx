import { useCallback, useEffect, useRef, useState } from 'react';
import { apiClient, resolveApiUrl } from '../../services/apiClient';
import './LinuxAppWindow.css';

import { useWindowManager } from '../../stores/windowManager';

interface LinuxAppWindowProps {
  windowId: string;
  appId?: string;
  title?: string;
  icon?: string;
  params?: {
    app?: string;
    appId?: string;
    title?: string;
    icon?: string;
    filePath?: string;
    distribution?: string | null;
  };
}

interface LaunchSession {
  id: string;
  clientUrl?: string | null;
  title: string;
  appId: string;
  mode?: string;
  distribution?: string;
}

export default function LinuxAppWindow({ windowId, params }: LinuxAppWindowProps) {
  const win = useWindowManager(s => s.windows.find(w => w.id === windowId));
  const effectiveParams = params || win?.params as any;
  const targetAppId = effectiveParams?.appId || effectiveParams?.app || '';
  const targetTitle = effectiveParams?.title || win?.title || 'Aplicativo Linux';
  const targetIcon = effectiveParams?.icon || win?.icon || '🐧';
  const targetFilePath = effectiveParams?.filePath || null;
  const targetDistribution = effectiveParams?.distribution || null;

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [session, setSession] = useState<LaunchSession | null>(null);
  const [reconnectAttempt, setReconnectAttempt] = useState(0);
  const [recoveryGeneration, setRecoveryGeneration] = useState(0);
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const focusWindow = useWindowManager(state => state.focusWindow);

  const focusContainedSurface = useCallback(() => {
    const iframe = iframeRef.current;
    iframe?.focus({ preventScroll: true });
    iframe?.contentWindow?.focus();
  }, []);

  const stopSessionBestEffort = useCallback((sessionId: string) => {
    return apiClient(`/api/linux-runtime/poc1/sessions/${encodeURIComponent(sessionId)}/stop`, {
      method: 'POST',
      body: JSON.stringify({ ownerId: windowId }),
      timeoutMs: 4000,
      keepalive: true,
      suppressUnauthorizedHandler: true,
    }).catch(() => undefined);
  }, [windowId]);

  useEffect(() => {
    let cancelled = false;
    let retryTimer: ReturnType<typeof window.setTimeout> | null = null;
    let attempt = 0;

    async function startApp() {
      if (attempt === 0) setLoading(true);
      setError(null);
      if (!/^linux-[a-f0-9]{32}$/.test(targetAppId)) {
        setError('Containment recusado: o aplicativo não veio do registro Linux automático do CloudOS.');
        setLoading(false);
        return;
      }
      try {
        const res = await apiClient<{ session: LaunchSession }>('/api/linux-runtime/launch', {
          method: 'POST',
          body: JSON.stringify({
            appId: targetAppId,
            ownerId: windowId,
            filePath: targetFilePath,
            distribution: targetDistribution,
            reuseExisting: true,
          }),
          timeoutMs: 45_000,
        });

        if (!res?.session?.clientUrl || res.session.mode !== 'xpra') {
          throw new Error('Containment recusado: o runtime não forneceu uma superfície Xpra interna. Nenhuma janela externa foi aceita.');
        }

        if (cancelled) {
          void stopSessionBestEffort(res.session.id);
          return;
        }

        setSession(res.session);
        setReconnectAttempt(0);
      } catch (err) {
        if (cancelled) return;
        const msg = err instanceof Error ? err.message : String(err);
        if (attempt < 30) {
          attempt += 1;
          setReconnectAttempt(attempt);
          setError(`Conexão interrompida. Tentando reconectar automaticamente (${attempt})...`);
          retryTimer = window.setTimeout(() => {
            retryTimer = null;
            if (!cancelled) void startApp();
          }, 2000);
        } else {
          setError(msg);
          setLoading(false);
        }
      }
    }

    void startApp();

    return () => {
      cancelled = true;
      if (retryTimer !== null) window.clearTimeout(retryTimer);
    };
  }, [targetAppId, windowId, targetFilePath, targetDistribution, recoveryGeneration, stopSessionBestEffort]);

  useEffect(() => {
    if (!session?.id) return undefined;
    const sessionId = session.id;
    return () => {
      void stopSessionBestEffort(sessionId);
    };
  }, [session?.id, stopSessionBestEffort]);

  useEffect(() => {
    if (!session?.id) return undefined;
    let disposed = false;
    let failures = 0;
    let timer: ReturnType<typeof window.setTimeout> | null = null;
    const sessionId = session.id;

    const schedule = () => {
      timer = window.setTimeout(() => { void poll(); }, 5000);
    };

    const poll = async () => {
      try {
        const result = await apiClient<{ health?: { healthy?: boolean } }>(
          `/api/linux-runtime/poc1/sessions/${encodeURIComponent(sessionId)}/health`,
          { timeoutMs: 5000, suppressUnauthorizedHandler: true },
        );
        if (disposed) return;
        failures = result?.health?.healthy ? 0 : failures + 1;
      } catch {
        if (disposed) return;
        failures += 1;
      }

      if (failures >= 2) {
        setError('Conexão com o runtime Linux foi perdida. Restaurando a sessão automaticamente...');
        setLoading(true);
        setSession(null);
        setRecoveryGeneration(value => value + 1);
        return;
      }
      schedule();
    };

    schedule();
    return () => {
      disposed = true;
      if (timer !== null) window.clearTimeout(timer);
    };
  }, [session?.id]);

  useEffect(() => {
    const handleMessage = (event: MessageEvent) => {
      const iframe = iframeRef.current;
      if (!iframe || !session?.clientUrl || event.source !== iframe.contentWindow || event.data?.sessionId !== session.id) return;
      let expectedOrigin: string;
      try {
        expectedOrigin = new URL(resolveApiUrl(session.clientUrl), window.location.href).origin;
      } catch {
        return;
      }
      if (event.origin !== expectedOrigin) return;
      if (event.data?.type === 'xpra-focus-request') {
        if (!win?.isMinimized) {
          focusWindow(windowId);
          focusContainedSurface();
        }
        return;
      }
      if (event.data?.type === 'xpra-render-event' && event.data?.name === 'frame-painted') {
        setLoading(false);
      }
    };
    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
  }, [focusContainedSurface, focusWindow, session, win?.isMinimized, windowId]);

  useEffect(() => {
    if (loading || !session?.id || !win?.isActive) return undefined;
    const frame = window.requestAnimationFrame(focusContainedSurface);
    return () => window.cancelAnimationFrame(frame);
  }, [focusContainedSurface, loading, session?.id, win?.isActive]);

  return (
    <div className="linux-app-window">
      {loading && (
        <div className="linux-app-window__loader" role="status">
          <div className="linux-app-window__icon">
            {typeof targetIcon === 'string' && (targetIcon.startsWith('/') || targetIcon.startsWith('http')) ? (
              <img src={targetIcon} alt="" style={{ width: '48px', height: '48px', objectFit: 'contain' }} />
            ) : (
              targetIcon
            )}
          </div>
          <div className="linux-app-window__spinner" />
          <span className="linux-app-window__title">Iniciando {targetTitle}…</span>
          {reconnectAttempt > 0 && <small>Tentativa de reconexão {reconnectAttempt}</small>}
        </div>
      )}

      {error ? (
        <div className="linux-app-window__error">
          <span className="linux-app-window__error-icon">⚠️</span>
          <strong>Erro ao abrir aplicativo Linux</strong>
          <p>{error}</p>
        </div>
      ) : session?.clientUrl ? (
        <iframe
          ref={iframeRef}
          key={session.id}
          title={targetTitle}
          src={resolveApiUrl(session.clientUrl)}
          className={`linux-app-window__frame ${loading ? 'hidden' : 'visible'}`}
          sandbox="allow-scripts allow-forms allow-pointer-lock allow-same-origin"
          allow="clipboard-read; clipboard-write"
          referrerPolicy="no-referrer"
          tabIndex={0}
          onLoad={focusContainedSurface}
        />
      ) : null}
    </div>
  );
}
