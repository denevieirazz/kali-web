import { useEffect, useRef, useState } from 'react';
import { apiClient } from '../../services/apiClient';
import './LinuxAppWindow.css';

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
  };
}

interface LaunchSession {
  id: string;
  clientUrl: string;
  title: string;
  appId: string;
}

export default function LinuxAppWindow({ windowId, params }: LinuxAppWindowProps) {
  const targetAppId = params?.appId || params?.app || 'firefox';
  const targetTitle = params?.title || 'Aplicativo Linux';
  const targetIcon = params?.icon || '🐧';

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [session, setSession] = useState<LaunchSession | null>(null);
  const iframeRef = useRef<HTMLIFrameElement>(null);

  useEffect(() => {
    let cancelled = false;

    async function startApp() {
      setLoading(true);
      setError(null);
      try {
        const res = await apiClient<{ session: LaunchSession }>('/api/linux-runtime/launch', {
          method: 'POST',
          body: JSON.stringify({ appId: targetAppId, ownerId: windowId }),
          timeoutMs: 15_000,
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
      if (event.data?.type === 'xpra-render-event' && event.data?.name === 'frame-painted') {
        setLoading(false);
      }
    };
    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
  }, []);

  const handleFrameLoad = () => {
    // If frame-painted doesn't fire, auto-reveal after iframe load + short buffer
    setTimeout(() => {
      setLoading(false);
    }, 1500);
  };

  return (
    <div className="linux-app-window">
      {loading && (
        <div className="linux-app-window__loader" role="status">
          <div className="linux-app-window__icon">{targetIcon}</div>
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
          src={session.clientUrl}
          className={`linux-app-window__frame ${loading ? 'hidden' : 'visible'}`}
          sandbox="allow-scripts allow-forms allow-pointer-lock allow-same-origin"
          allow="clipboard-read; clipboard-write"
          referrerPolicy="no-referrer"
          onLoad={handleFrameLoad}
        />
      ) : null}
    </div>
  );
}
