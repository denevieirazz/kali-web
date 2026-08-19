import { useEffect, useMemo, useState } from 'react';
import { apiClient } from '../../services/apiClient';
import './LinuxRuntimePoc.css';

type PocApp = { id: string; command: string; title: string };
type PocSession = {
  id: string;
  app: string;
  title: string;
  distribution: string;
  port: number;
  display: number;
  state: 'starting' | 'ready' | 'failed' | 'stopping' | 'stopped';
  startedAt: string;
  clientUrl: string | null;
  xpraVersion: string;
  error?: string | null;
  errorCode?: string | null;
};
type PocStatus = {
  mode: string;
  externalWindowsExpected: number;
  apps: PocApp[];
  session: PocSession | null;
};

export default function LinuxRuntimePoc() {
  const [status, setStatus] = useState<PocStatus | null>(null);
  const [selectedApp, setSelectedApp] = useState('xclock');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const session = status?.session ?? null;
  const readyUrl = session?.state === 'ready' ? session.clientUrl : null;
  const selectedTitle = useMemo(
    () => status?.apps.find(app => app.id === selectedApp)?.title ?? selectedApp,
    [selectedApp, status?.apps],
  );

  async function refresh() {
    const next = await apiClient<PocStatus>('/api/linux-runtime/poc1');
    setStatus(next);
    if (next.session?.app) setSelectedApp(next.session.app);
  }

  useEffect(() => {
    void refresh().catch(cause => setError(cause instanceof Error ? cause.message : String(cause)));
  }, []);

  async function start() {
    setBusy(true);
    setError(null);
    try {
      const result = await apiClient<{ session: PocSession }>('/api/linux-runtime/poc1/start', {
        method: 'POST',
        body: JSON.stringify({ app: selectedApp }),
        timeoutMs: 35_000,
      });
      setStatus(current => current ? { ...current, session: result.session } : null);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
      await refresh().catch(() => undefined);
    } finally {
      setBusy(false);
    }
  }

  async function stop() {
    setBusy(true);
    setError(null);
    try {
      await apiClient('/api/linux-runtime/poc1/stop', { method: 'POST', timeoutMs: 10_000 });
      await refresh();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="linux-runtime-poc" data-poc="cloudos-linux-runtime-xpra">
      <header className="linux-runtime-poc__bar">
        <div>
          <strong>Linux Runtime POC 1</strong>
          <span>{session ? `${session.distribution} · DISPLAY :${session.display}` : 'Xpra HTML5 contido'}</span>
        </div>
        <div className="linux-runtime-poc__controls">
          <select
            aria-label="Aplicativo Linux da POC"
            value={selectedApp}
            disabled={busy || session?.state === 'ready' || session?.state === 'starting'}
            onChange={event => setSelectedApp(event.target.value)}
          >
            {(status?.apps ?? [{ id: 'xclock', command: 'xclock', title: 'XClock' }]).map(app => (
              <option key={app.id} value={app.id}>{app.title}</option>
            ))}
          </select>
          {!readyUrl ? (
            <button type="button" onClick={start} disabled={busy}>{busy ? 'Iniciando…' : `Abrir ${selectedTitle}`}</button>
          ) : (
            <button type="button" onClick={stop} disabled={busy}>Encerrar sessão</button>
          )}
        </div>
      </header>

      <section className="linux-runtime-poc__surface" data-contained-surface={readyUrl ? 'ready' : 'idle'}>
        {readyUrl ? (
          <iframe
            title={`${session?.title ?? 'Aplicativo Linux'} — Xpra HTML5`}
            src={readyUrl}
            className="linux-runtime-poc__frame"
            sandbox="allow-scripts allow-same-origin allow-forms allow-pointer-lock allow-downloads"
            allow="clipboard-read; clipboard-write"
            referrerPolicy="no-referrer"
          />
        ) : (
          <div className="linux-runtime-poc__state" role="status">
            <strong>{session?.state === 'failed' ? 'POC bloqueada' : 'Nenhuma superfície Linux ativa'}</strong>
            <p>
              {session?.state === 'failed'
                ? `${session.errorCode ?? 'XPRA_START_FAILED'}: ${session.error ?? 'Xpra não iniciou.'}`
                : 'A aplicação será iniciada no WSL por Xpra e renderizada somente nesta CloudOS Window.'}
            </p>
            {error && <pre>{error}</pre>}
          </div>
        )}
      </section>

      <footer className="linux-runtime-poc__evidence">
        <span>Transport: Xpra HTML5/WebSocket</span>
        <span>Windows externos esperados: {status?.externalWindowsExpected ?? 0}</span>
        <span>Estado: {session?.state ?? 'idle'}</span>
      </footer>
    </div>
  );
}
