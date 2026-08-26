import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import kernel from '../../core/kernel';
import { useNativeSessions } from '../../hooks/useNativeSessions';
import { nativeHostBridge, type NativeSession, type NativeViewportBounds } from '../../services/nativeHostBridge';
import { nativeSessionForLaunch, nativeViewportBounds } from '../../services/nativeWindowContract';
import { systemHubClient, type NativeApp, type NativeLaunchResult } from '../../services/systemHubClient';
import { useContextMenuStore } from '../../stores/contextMenuStore';
import { useNativeWindowBindings } from '../../stores/nativeWindowBindings';
import { useSystem } from '../../stores/systemStore';
import { useWindowManager } from '../../stores/windowManager';
import './NativeAppWindow.css';

type Phase = 'launching' | 'waiting' | 'attaching' | 'attached' | 'external' | 'error';

function viewportSize() {
  return { width: document.documentElement.clientWidth, height: document.documentElement.clientHeight };
}

function platformLabel(app: NativeApp) {
  if (app.source === 'wsl') return app.distribution ? `Linux · ${app.distribution}` : 'Linux · WSL';
  return 'Windows';
}

export default function NativeAppWindow({ windowId }: { windowId: string }) {
  const win = useWindowManager((state) => state.windows.find((item) => item.id === windowId));
  const updateWindowTitle = useWindowManager((state) => state.updateWindowTitle);
  const shellOverlayOpen = useSystem((state) => state.isStartMenuOpen || state.isSearchOpen || state.showNotificationCenter);
  const contextMenuOpen = useContextMenuStore((state) => state.isOpen);
  const bindNativeWindow = useNativeWindowBindings((state) => state.bind);
  const unbindNativeWindow = useNativeWindowBindings((state) => state.unbind);
  const sessions = useNativeSessions();
  const surfaceRef = useRef<HTMLDivElement>(null);
  const launchRef = useRef<{ attempt: number; promise: Promise<NativeLaunchResult> } | null>(null);
  const sessionRef = useRef<NativeSession | null>(null);
  const controlledSessionRef = useRef<string | null>(null);
  const lastLayoutRef = useRef<{ sessionId: string; bounds: NativeViewportBounds; visible: boolean } | null>(null);
  const sawSessionRef = useRef(false);
  const missingSessionTimerRef = useRef<number | null>(null);
  const [attempt, setAttempt] = useState(0);
  const [dockAttempt, setDockAttempt] = useState(0);
  const [phase, setPhase] = useState<Phase>('launching');
  const [launch, setLaunch] = useState<NativeLaunchResult | null>(null);
  const [message, setMessage] = useState('Solicitando a abertura ao sistema...');

  const app = win?.params?.nativeApp as NativeApp | undefined;
  const session = useMemo(
    () => launch ? nativeSessionForLaunch(sessions, launch) as NativeSession | null : null,
    [launch, sessions],
  );
  const sessionId = session?.sessionId || null;
  const sessionTitle = session?.title || app?.name || 'Aplicativo';
  const sessionWasContained = session?.contained === true;
  sessionRef.current = session;

  useEffect(() => {
    if (!app) {
      setPhase('error');
      setMessage('Os dados deste aplicativo não estão disponíveis. Abra-o novamente pelo menu Iniciar.');
      return;
    }

    setPhase('launching');
    setMessage(`Abrindo ${app.name}...`);
    if (!launchRef.current || launchRef.current.attempt !== attempt) {
      launchRef.current = { attempt, promise: systemHubClient.launchApp(app.id) };
    }

    let active = true;
    launchRef.current.promise.then((result) => {
      if (!active) return;
      setLaunch(result);
      updateWindowTitle(windowId, result.name || app.name);
      if (!nativeHostBridge.available || result.managed === false) {
        setPhase('external');
        setMessage(result.managementReason || 'O Windows abriu este aplicativo externamente porque ele não oferece uma janela compatível com o encaixe do CloudOS.');
      } else {
        setPhase('waiting');
        setMessage('Aguardando a janela gráfica do aplicativo...');
      }
    }).catch((error) => {
      if (!active) return;
      setPhase('error');
      setMessage(error instanceof Error ? error.message : 'O aplicativo não pôde ser aberto.');
    });

    return () => { active = false; };
  }, [app, attempt, updateWindowTitle, windowId]);

  useEffect(() => {
    if (!launch || session || phase !== 'waiting') return;
    const timeout = window.setTimeout(() => {
      setPhase('external');
      setMessage('O programa foi iniciado, mas sua janela não pôde ser vinculada com segurança. Ele continua disponível no desktop do Windows.');
    }, 15_000);
    return () => window.clearTimeout(timeout);
  }, [launch, phase, session]);

  useEffect(() => {
    if (session) {
      if (missingSessionTimerRef.current !== null) {
        window.clearTimeout(missingSessionTimerRef.current);
        missingSessionTimerRef.current = null;
      }
      sawSessionRef.current = true;
      if (session.title && session.title !== win?.title) updateWindowTitle(windowId, session.title);
      return;
    }
    if (!sawSessionRef.current || !launch || missingSessionTimerRef.current !== null) return;

    // Alterar owner/estilos de uma janela Win32 pode produzir um intervalo curto
    // de eventos destroy/create. Fechar o painel na primeira ausência desmontava
    // a superfície e ocultava programas que ainda estavam inicializando.
    missingSessionTimerRef.current = window.setTimeout(() => {
      missingSessionTimerRef.current = null;
      if (sessionRef.current) return;
      sawSessionRef.current = false;
      controlledSessionRef.current = null;
      lastLayoutRef.current = null;
      setPhase('error');
      setMessage('A janela do programa deixou de responder ao encaixe. O CloudOS manteve este painel aberto para você tentar novamente, sem encerrar outro processo do Windows.');
    }, 4_000);
  }, [launch, session, updateWindowTitle, win?.title, windowId]);

  useEffect(() => () => {
    if (missingSessionTimerRef.current !== null) {
      window.clearTimeout(missingSessionTimerRef.current);
      missingSessionTimerRef.current = null;
    }
    const controlledSessionId = controlledSessionRef.current;
    const lastLayout = lastLayoutRef.current;
    if (controlledSessionId && lastLayout) {
      void nativeHostBridge.layoutSession(controlledSessionId, lastLayout.bounds, false).catch(() => {});
    }
  }, []);

  useEffect(() => {
    if (!sessionId) return;
    bindNativeWindow(sessionId, windowId);
    return () => unbindNativeWindow(sessionId, windowId);
  }, [bindNativeWindow, sessionId, unbindNativeWindow, windowId]);

  const desiredVisible = Boolean(
    session && win && !win.isMinimized && win.isActive && !shellOverlayOpen && !contextMenuOpen && phase !== 'external',
  );

  useEffect(() => {
    if (!sessionId || !surfaceRef.current || !nativeHostBridge.available || phase === 'external') return;
    const surface = surfaceRef.current;
    const cloudWindow = surface.closest('.window');
    let disposed = false;
    let frame = 0;
    let timer = 0;
    let lastSyncAt = 0;

    const synchronize = async () => {
      if (disposed) return;
      const bounds = nativeViewportBounds(surface.getBoundingClientRect(), viewportSize());
      if (!bounds || bounds.width < 32 || bounds.height < 32) return;
      const previous = lastLayoutRef.current;
      if (previous
        && previous.sessionId === sessionId
        && previous.visible === desiredVisible
        && previous.bounds.x === bounds.x
        && previous.bounds.y === bounds.y
        && previous.bounds.width === bounds.width
        && previous.bounds.height === bounds.height) return;

      try {
        setPhase((current) => current === 'attached' ? current : 'attaching');
        if (controlledSessionRef.current === sessionId || sessionWasContained) {
          await nativeHostBridge.layoutSession(sessionId, bounds, desiredVisible);
        } else if (desiredVisible) {
          await nativeHostBridge.attachSession(sessionId, bounds);
          controlledSessionRef.current = sessionId;
        } else {
          return;
        }
        lastLayoutRef.current = { sessionId, bounds, visible: desiredVisible };
        setPhase('attached');
        setMessage(desiredVisible ? `${sessionTitle} está sendo executado dentro do CloudOS.` : `${sessionTitle} está oculto enquanto você usa outra área do CloudOS.`);
      } catch (error) {
        controlledSessionRef.current = null;
        lastLayoutRef.current = null;
        setPhase('external');
        setMessage(error instanceof Error ? error.message : 'O Windows não permitiu encaixar esta janela.');
      }
    };

    const schedule = () => {
      window.cancelAnimationFrame(frame);
      window.clearTimeout(timer);
      timer = window.setTimeout(() => {
        frame = window.requestAnimationFrame(() => {
          lastSyncAt = performance.now();
          void synchronize();
        });
      }, Math.max(0, 40 - (performance.now() - lastSyncAt)));
    };

    const resizeObserver = new ResizeObserver(schedule);
    resizeObserver.observe(surface);
    const mutationObserver = new MutationObserver(schedule);
    if (cloudWindow) mutationObserver.observe(cloudWindow, { attributes: true, attributeFilter: ['class', 'style'] });
    const visibilityListener = () => schedule();
    document.addEventListener('visibilitychange', visibilityListener);
    window.addEventListener('resize', schedule);
    window.addEventListener('scroll', schedule, true);
    window.addEventListener('mousemove', schedule);
    schedule();

    return () => {
      disposed = true;
      window.cancelAnimationFrame(frame);
      window.clearTimeout(timer);
      resizeObserver.disconnect();
      mutationObserver.disconnect();
      document.removeEventListener('visibilitychange', visibilityListener);
      window.removeEventListener('resize', schedule);
      window.removeEventListener('scroll', schedule, true);
      window.removeEventListener('mousemove', schedule);
      // A limpeza também roda entre efeitos (mudança de título, foco, tamanho e
      // StrictMode), não apenas ao fechar a janela. Ocultar o HWND aqui causava
      // o piscar/desaparecer observado logo após a abertura. A visibilidade é
      // sincronizada pelo próximo efeito; o fechamento real usa WM_CLOSE pelo
      // evento process:terminated abaixo.
    };
  }, [desiredVisible, dockAttempt, sessionId, sessionTitle, sessionWasContained]);

  useEffect(() => {
    if (!win?.processId) return;
    return kernel.on('process:terminated', (terminatedPid: number) => {
      if (terminatedPid !== win.processId) return;
      const currentSession = sessionRef.current;
      if (!currentSession || !nativeHostBridge.available) return;
      void nativeHostBridge.operate('close', currentSession.sessionId)
        .catch(() => {})
        .finally(() => {
          window.setTimeout(() => {
            void nativeHostBridge.detachSession(currentSession.sessionId).catch(() => {});
          }, 500);
        });
    });
  }, [win?.processId]);

  const retryLaunch = useCallback(() => {
    if (missingSessionTimerRef.current !== null) {
      window.clearTimeout(missingSessionTimerRef.current);
      missingSessionTimerRef.current = null;
    }
    launchRef.current = null;
    sawSessionRef.current = false;
    setLaunch(null);
    setAttempt((current) => current + 1);
  }, []);

  const retryDock = useCallback(() => {
    setPhase('waiting');
    setMessage('Tentando encaixar a janela novamente...');
    setDockAttempt((current) => current + 1);
  }, []);

  const detach = useCallback(async () => {
    if (!session) return;
    try {
      await nativeHostBridge.detachSession(session.sessionId);
      controlledSessionRef.current = null;
      lastLayoutRef.current = null;
      setPhase('external');
      setMessage('A janela foi solta do CloudOS e continua aberta no desktop do Windows.');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Não foi possível soltar a janela.');
    }
  }, [session]);

  if (!app) {
    return <div className="native-app-state error"><strong>Aplicativo inválido</strong><p>{message}</p></div>;
  }

  return (
    <div className="native-app-window">
      <div ref={surfaceRef} className={`native-app-surface phase-${phase}`} aria-label={`Área nativa de ${app.name}`}>
        <div className="native-app-state">
          <span className={`native-app-platform ${app.source}`}>{app.source === 'wsl' ? '🐧' : '▦'}</span>
          <strong>{phase === 'attached' ? app.name : phase === 'external' ? 'Janela externa' : phase === 'error' ? 'Não foi possível abrir' : 'Preparando aplicativo'}</strong>
          <small>{platformLabel(app)}</small>
          <p>{message}</p>
          <div className="native-app-actions">
            {phase === 'error' && <button className="primary-button" onClick={retryLaunch}>Tentar novamente</button>}
            {phase === 'external' && session && nativeHostBridge.available && <button className="primary-button" onClick={retryDock}>Fixar no CloudOS</button>}
            {session && phase === 'attached' && <button onClick={detach}>Soltar janela</button>}
          </div>
        </div>
      </div>
      <footer className="native-app-footer">
        <span>{nativeHostBridge.available ? 'Integração nativa ativa' : 'Abra o CloudOS Desktop para usar janelas integradas'}</span>
        <span>{session ? `PID ${session.processId}` : launch?.pid ? `PID ${launch.pid}` : 'Inicializando'}</span>
      </footer>
    </div>
  );
}
