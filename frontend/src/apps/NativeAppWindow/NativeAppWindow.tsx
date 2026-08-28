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
  // The native Host owns application identity. Modern Hosts return the opaque session capability
  // directly; this polling path exists only for older Hosts that returned a PID alone.
  if (typeof launch.sessionId === 'string' && launch.sessionId) return launch.sessionId;

  for (let attempt = 0; attempt < SESSION_ATTEMPTS && !cancelled(); attempt += 1) {
    const result = await nativeHostBridge.listSessions();
    const session: NativeSession | null = nativeSessionForLaunch(result.sessions, launch);
    if (session) return session.sessionId;
    await sleep(SESSION_RETRY_MS);
  }
  return null;
}

async function closeSessionBestEffort(sessionId: string | null | undefined) {
  if (!sessionId) return;
  try {
    await nativeHostBridge.operate('close', sessionId);
  } catch {
    // Host-side Job containment remains the final fail-safe if the WebView transport disappears.
  }
}

async function closeCancelledLaunch(launch: NativeLaunch) {
  if (!launch.managed) return;
  const exactSessionId = typeof launch.sessionId === 'string' && launch.sessionId ? launch.sessionId : null;
  if (exactSessionId) {
    await closeSessionBestEffort(exactSessionId);
    return;
  }

  try {
    const result = await nativeHostBridge.listSessions();
    await closeSessionBestEffort(nativeSessionForLaunch(result.sessions, launch)?.sessionId);
  } catch {
    // An unattached launch is still fail-closed by the Host deadline/Job lifecycle.
  }
}

function errorMessage(error: unknown) {
  if (error instanceof NativeHostError) return error.message;
  if (error instanceof Error) return error.message;
  return 'O runtime nativo do Windows não pôde anexar este aplicativo ao CloudOS.';
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
  const [documentVisible, setDocumentVisible] = useState(() => document.visibilityState === 'visible');

  const appId = win?.appId || '';
  const visible = Boolean(win && !win.isMinimized && win.isActive && !isStartMenuOpen && documentVisible);

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
      if (disposedRef.current || sessionIdRef.current !== currentSessionId) return;
      attachedRef.current = true;
      lastLayoutRef.current = { bounds, visible };
      setStatus('contained');
      return;
    }

    if (!attachedRef.current || !nativeSurfaceLayoutChanged(lastLayoutRef.current, bounds, visible)) return;

    const previous = lastLayoutRef.current;
    const requested = { bounds, visible };
    // Geometry is the web shell's only rendering responsibility for a native app. Windows/DWM
    // renders the real HWND; the shell only keeps its reserved rectangle synchronized.
    lastLayoutRef.current = requested;
    try {
      await nativeHostBridge.layoutSession(currentSessionId, bounds, visible);
    } catch (layoutError) {
      if (lastLayoutRef.current === requested) lastLayoutRef.current = previous;
      throw layoutError;
    }
  }, [visible]);

  useEffect(() => {
    const syncDocumentVisibility = () => setDocumentVisible(document.visibilityState === 'visible');
    document.addEventListener('visibilitychange', syncDocumentVisibility);
    return () => document.removeEventListener('visibilitychange', syncDocumentVisibility);
  }, []);

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
        if (cancelled) {
          await closeCancelledLaunch(launch);
          return;
        }
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
        if (cancelled) {
          await closeSessionBestEffort(resolvedSessionId);
          return;
        }
        if (!resolvedSessionId) {
          throw new NativeHostError(
            'NATIVE_WINDOW_NOT_FOUND',
            'O runtime nativo não encontrou uma janela Windows pertencente a este lançamento.'
          );
        }

        // From here on session identity belongs to the Host/Job, not to a particular HWND.
        // If the application replaces its primary HWND, the Host rebinds this same sessionId.
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
        await closeSessionBestEffort(currentSessionId);
      })();
    };
  }, [appId, updateWindowTitle, windowId]);

  useEffect(() => {
    if (!sessionId) return undefined;
    let frame = 0;
    const scheduleSync = () => {
      window.cancelAnimationFrame(frame);
      frame = window.requestAnimationFrame(() => {
        void syncSurface(!attachedRef.current).catch((surfaceError) => {
          if (disposedRef.current) return;
          setStatus('error');
          setError(errorMessage(surfaceError));
        });
      });
    };

    scheduleSync();
    const observer = new ResizeObserver(scheduleSync);
    if (surfaceRef.current) observer.observe(surfaceRef.current);
    window.addEventListener('resize', scheduleSync);
    window.addEventListener('scroll', scheduleSync, true);

    return () => {
      window.cancelAnimationFrame(frame);
      observer.disconnect();
      window.removeEventListener('resize', scheduleSync);
      window.removeEventListener('scroll', scheduleSync, true);
    };
  }, [sessionId, syncSurface]);

  // Position changes can move the shell rectangle without triggering ResizeObserver.
  // We only send geometry; the browser never renders or forwards pixels for the Windows app.
  useEffect(() => {
    if (!sessionId || status !== 'contained') return undefined;
    const frame = window.requestAnimationFrame(() => {
      void syncSurface(false).catch((surfaceError) => {
        if (disposedRef.current) return;
        setStatus('error');
        setError(errorMessage(surfaceError));
      });
    });
    return () => window.cancelAnimationFrame(frame);
  }, [sessionId, status, syncSurface, win?.x, win?.y, win?.width, win?.height, win?.isMaximized, win?.isMinimized]);

  // Foreground ownership stays with Windows. React only asks the Host to activate the real HWND
  // when its CloudOS shell window becomes active.
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
      if (disposedRef.current || sessionIdRef.current !== sessionId) return;
      const current = sessions.find((session) => session.sessionId === sessionId);
      if (!current) {
        // Primary HWND replacement is handled entirely by the native Host and does not publish
        // a transient session disappearance. If the logical session is actually gone here, the
        // application/Job ended and the shell window should close rather than relaunch it.
        closeWindow(windowId);
        return;
      }
      if (current.title && current.title !== win?.title) updateWindowTitle(windowId, current.title);
    });
    return () => {
      unsubscribe();
    };
  }, [closeWindow, sessionId, updateWindowTitle, win?.title, windowId]);

  useEffect(() => () => {
    disposedRef.current = true;
  }, []);

  const progressText = status === 'launching'
    ? 'Abrindo aplicativo do Windows…'
    : status === 'waiting'
      ? 'Localizando a janela nativa…'
      : 'Conectando a janela nativa…';

  return (
    <div
      ref={surfaceRef}
      className="native-app-surface"
      data-status={status}
      data-session-id={sessionId || undefined}
      data-renderer="native-windows"
    >
      <div className="native-app-placeholder" role={status === 'error' ? 'alert' : 'status'} aria-live="polite">
        <span className="native-app-placeholder-icon" aria-hidden="true">▦</span>
        {status === 'error' ? (
          <>
            <strong>Não foi possível conectar este aplicativo do Windows</strong>
            <span>{error}</span>
          </>
        ) : (
          <>
            <strong>{progressText}</strong>
            <span>O Windows renderiza o aplicativo; o CloudOS controla apenas a superfície e o ciclo de vida.</span>
          </>
        )}
      </div>
    </div>
  );
}
