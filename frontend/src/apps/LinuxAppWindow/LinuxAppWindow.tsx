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
  };
}

interface LaunchSession {
  id: string;
  clientUrl: string;
  title: string;
  appId: string;
}

export default function LinuxAppWindow({ windowId, params }: LinuxAppWindowProps) {
  const win = useWindowManager(s => s.windows.find(w => w.id === windowId));
  const effectiveParams = params || win?.params as any;
  const targetAppId = effectiveParams?.appId || effectiveParams?.app || 'firefox';
  const targetTitle = effectiveParams?.title || win?.title || 'Aplicativo Linux';
  const targetIcon = effectiveParams?.icon || win?.icon || '🐧';
  const targetFilePath = effectiveParams?.filePath || null;

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [session, setSession] = useState<LaunchSession | null>(null);
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const focusWindow = useWindowManager(state => state.focusWindow);

  const focusContainedSurface = useCallback(() => {
    const iframe = iframeRef.current;
    iframe?.focus({ preventScroll: true });
    iframe?.contentWindow?.focus();
  }, []);

  useEffect(() => {
    let cancelled = false;

    async function startApp() {
      setLoading(true);
      setError(null);
      try {
        const res = await apiClient<{ session: LaunchSession }>('/api/linux-runtime/launch', {
          method: 'POST',
          body: JSON.stringify({
            appId: targetAppId,
            ownerId: windowId,
            filePath: targetFilePath
          }),
          timeoutMs: 45_000,
        });

        if (cancelled) return;
        if (res?.session?.clientUrl) {
          setSession(res.session);
        } else {
          setError('Não foi possível inicializar a superfície do aplicativo.');
          setLoading(false);
        }
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : String(err));
          setLoading(false);
        }
      }
    }

    void startApp();

    return () => {
      cancelled = true;
    };
  }, [targetAppId, windowId]);

  useEffect(() => {
    const handleMessage = (event: MessageEvent) => {
      const iframe = iframeRef.current;
      if (!iframe || !session || event.source !== iframe.contentWindow || event.data?.sessionId !== session.id) return;
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
