import { useCallback, useEffect, useRef, useState } from 'react';
import { nativeHostBridge, NativeHostError, type NativeSession, type NativeViewportBounds } from '../../services/nativeHostBridge';
import { nativeSessionForLaunch, nativeSurfaceLayoutChanged, nativeViewportBounds } from '../../services/nativeWindowContract.js';
import { useSystem } from '../../stores/systemStore';
import { useWindowManager } from '../../stores/windowManager';
import './NativeAppWindow.css';

type NativeSurfaceStatus = 'launching' | 'waiting' | 'attaching' | 'contained' | 'error';
type NativeLaunch = Awaited<ReturnType<typeof nativeHostBridge.launchApp>>;
type NativeLayoutState = { bounds: NativeViewportBounds; visible: boolean };

const SESSION_ATTEMPTS = 32;
const SESSION_RETRY_MS = 125;

function sleep(ms: number) {
  return new Promise<void>((resolve) => window.setTimeout(resolve, ms));
}

async function resolveSessionId(launch: NativeLaunch, cancelled: () => boolean): Promise<string | null> {
  // Current Hosts create the opaque session before replying to native.launchApp.
  // Trust that exact capability instead of paying an extra listSessions IPC on every launch.
  if (typeof launch.sessionId === 'string' && launch.sessionId) return launch.sessionId;

  // Compatibility fallback for older Hosts that only returned the launch PID.
  for (let attempt = 0; attempt < SESSION_ATTEMPTS && !cancelled(); attempt += 1) {
    const result = await nativeHostBridge.listSessions();
    const session: NativeSession | null = nativeSessionForLaunch(result.sessions, launch);
    if (session) return session.sessionId;
    await sleep(SESSION_RETRY_MS);
  }
  return null;
}

function errorMessage(error: unknown) {
  if (error instanceof NativeHostError) return error.message;
  if (error instanceof Error) return error.message;
  return 'O aplicativo do Windows não pôde ser contido pelo CloudOS.';
}

export default function NativeAppWindow({ windowId }: { windowId: string; params?: any }) {
  const win = useWindowManager((state) => state.windows.find((item) => item.id === windowId));
  const closeWindow = useWindowManager((state) => state.closeWindow);
  const updateWindowTitle = useWindowManager((state) => state.updateWindowTitle);
  const isStartMenuOpen = useSystem((state) => state.isStartMenuOpen);
  const surfaceRef = useRef<HTMLDivElement>(null);
  const sessionIdRef = useRef<string | null>(null);
  const attachedRef = useRef(false);
  const lastBoundsRef = useRef<NativeViewportBounds | null>(null);
  const lastLayoutRef = useRef<NativeLayoutState | null>(null);
  const disposedRef = useRef(false);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [status, setStatus] = useState<NativeSurfaceStatus>('launching');
  const [error, setError] = useState('');

  const appId = win?.appId || '';
  const visible = Boolean(win && !win.isMinimized && win.isActive && !isStartMenuOpen && document.visibilityState === 'visible');

  const syncSurface = useCallback(async (attach = false) => {
    const currentSessionId = sessionIdRef.current;
    if (!currentSessionId || disposedRef.current) return;

    const rect = surfaceRef.current?.getBoundingClientRect();
    const measured = rect
      ? nativeViewportBounds(rect, { width: window.innerWidth, height: window.innerHeight })
      : null;
    if (measured) lastBoundsRef.current = measured;
    const bounds = measured || lastBoundsRef.current;
    if (!bounds) return;

    if (attach && !attachedRef.current) {
      setStatus('attaching');
      await nativeHostBridge.attachSession(currentSessionId, bounds, visible);
      if (disposedRef.current) return;
      attachedRef.current = true;
      lastLayoutRef.current = { bounds, visible };
      setStatus('contained');
      return;
    }

    if (!attachedRef.current || !nativeSurfaceLayoutChanged(lastLayoutRef.current, bounds, visible)) return;

    const previous = lastLayoutRef.current;
    const requested = { bounds, visible };
    // Mark the request before awaiting the bridge so ResizeObserver/window events
    // in the same frame cannot enqueue identical native layout IPC.
    lastLayoutRef.current = requested;
    try {
      await nativeHostBridge.layoutSession(currentSessionId, bounds, visible);
    } catch (layoutError) {
      if (lastLayoutRef.current === requested) lastLayoutRef.current = previous;
      throw layoutError;
    }
  }, [visible]);

  useEffect(() => {
    if (!appId.startsWith('native-')) {
      setStatus('error');
      setError('Identificador nativo inválido.');
      return undefined;
    }

    let cancelled = false;
    disposedRef.current = false;
    attachedRef.current = false;
    lastBoundsRef.current = null;
    lastLayoutRef.current = null;
    sessionIdRef.current = null;
    setSessionId(null);

    void (async () => {
      try {
        setStatus('launching');
        setError('');
        await nativeHostBridge.connect();
        if (cancelled) return;

        const launch = await nativeHostBridge.launchApp(appId);
        if (cancelled) return;
        if (launch.name) updateWindowTitle(windowId, launch.name);
        if (!launch.managed) {
          throw new NativeHostError(
            'WINDOW_NOT_MANAGED',
            launch.managementReason || 'O Windows entregou este aplicativo a um broker que não pode ser contido com segurança.'
          );
        }

        const exactSessionId = typeof launch.sessionId === 'string' && launch.sessionId ? launch.sessionId : null;
        if (!exactSessionId) setStatus('waiting');
        const resolvedSessionId = await resolveSessionId(launch, () => cancelled);
        if (cancelled) return;
        if (!resolvedSessionId) {
          throw new NativeHostError('NATIVE_WINDOW_NOT_FOUND', 'A janela do aplicativo não apareceu a tempo para ser encaixada no CloudOS.');
        }

        sessionIdRef.current = resolvedSessionId;
        setSessionId(resolvedSessionId);
      } catch (launchError) {
        if (cancelled) return;
        setStatus('error');
        setError(errorMessage(launchError));
      }
    })();

    return () => {
      cancelled = true;
      disposedRef.current = true;
      const currentSessionId = sessionIdRef.current;
      const bounds = lastBoundsRef.current;
      const wasAttached = attachedRef.current;
      sessionIdRef.current = null;
      attachedRef.current = false;
      lastLayoutRef.current = null;
      if (!currentSessionId) return;
      void (async () => {
        if (wasAttached && bounds) {
          try {
            await nativeHostBridge.layoutSession(currentSessionId, bounds, false);
          } catch {}
        }
        try {
          await nativeHostBridge.operate('close', currentSessionId);
        } catch {}
      })();
    };
  }, [appId, updateWindowTitle, windowId]);

  useEffect(() => {
    if (!sessionId) return undefined;
    let frame = 0;
    const scheduleSync = () => {
      window.cancelAnimationFrame(frame);
      frame = window.requestAnimationFrame(() => {
        void syncSurface(!attachedRef.current).catch((layoutError) => {
          if (disposedRef.current) return;
          setStatus('error');
          setError(errorMessage(layoutError));
        });
      });
    };

    scheduleSync();
    const observer = new ResizeObserver(scheduleSync);
    if (surfaceRef.current) observer.observe(surfaceRef.current);
    window.addEventListener('resize', scheduleSync);
    window.addEventListener('scroll', scheduleSync, true);
    document.addEventListener('visibilitychange', scheduleSync);

    return () => {
      window.cancelAnimationFrame(frame);
      observer.disconnect();
      window.removeEventListener('resize', scheduleSync);
      window.removeEventListener('scroll', scheduleSync, true);
      document.removeEventListener('visibilitychange', scheduleSync);
    };
  }, [sessionId, syncSurface]);

  // Position changes can move the surface without triggering ResizeObserver.
  // Relayout on geometry changes, but do not refocus the native HWND on every
  // drag/resize frame.
  useEffect(() => {
    if (!sessionId || status !== 'contained') return undefined;
    const frame = window.requestAnimationFrame(() => {
      void syncSurface(false).catch(() => undefined);
    });
    return () => window.cancelAnimationFrame(frame);
  }, [sessionId, status, syncSurface, win?.x, win?.y, win?.width, win?.height, win?.isMaximized, win?.isMinimized]);

  // Focus only when containment becomes ready or the CloudOS window becomes
  // active again. Geometry changes must not generate foreground-activation IPC.
  useEffect(() => {
    if (!sessionId || status !== 'contained' || !visible) return undefined;
    const frame = window.requestAnimationFrame(() => {
      void nativeHostBridge.operate('focus', sessionId).catch(() => undefined);
    });
    return () => window.cancelAnimationFrame(frame);
  }, [sessionId, status, visible]);

  useEffect(() => {
    if (!sessionId) return undefined;
    const unsubscribe = nativeHostBridge.onSessionsChanged((sessions) => {
      if (disposedRef.current) return;
      const current = sessions.find((session) => session.sessionId === sessionId);
      if (!current) {
        closeWindow(windowId);
        return;
      }
      if (current.title && current.title !== win?.title) updateWindowTitle(windowId, current.title);
    });
    return () => {
      unsubscribe();
    };
  }, [closeWindow, sessionId, updateWindowTitle, win?.title, windowId]);

  return (
    <div ref={surfaceRef} className="native-app-surface" data-status={status} data-session-id={sessionId || undefined}>
      <div className="native-app-placeholder" role={status === 'error' ? 'alert' : 'status'} aria-live="polite">
        <span className="native-app-placeholder-icon" aria-hidden="true">▦</span>
        {status === 'error' ? (
          <>
            <strong>Não foi possível encaixar este aplicativo do Windows</strong>
            <span>{error}</span>
          </>
        ) : (
          <>
            <strong>{status === 'launching' ? 'Abrindo aplicativo do Windows…' : status === 'waiting' ? 'Localizando a janela nativa…' : 'Encaixando no CloudOS…'}</strong>
            <span>A janela real ficará presa a esta superfície.</span>
          </>
        )}
      </div>
    </div>
  );
}
