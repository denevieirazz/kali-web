import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  nativeHostBridge,
  type NativeSession,
  type NativeViewportBounds
} from '../../services/nativeHostBridge';
import { nativeViewportBounds } from '../../services/nativeWindowContract.js';

type DockNotice = { tone: 'info' | 'success' | 'error'; text: string };

interface NativeAppDockProps {
  active: boolean;
  sessions: NativeSession[];
  selectedSessionId: string | null;
  pendingAppName: string | null;
  onSelect: (sessionId: string) => void;
  onNotice: (notice: DockNotice) => void;
}

function viewportSize() {
  return {
    width: document.documentElement.clientWidth,
    height: document.documentElement.clientHeight
  };
}

export default function NativeAppDock({
  active,
  sessions,
  selectedSessionId,
  pendingAppName,
  onSelect,
  onNotice
}: NativeAppDockProps) {
  const surfaceRef = useRef<HTMLDivElement | null>(null);
  const lastBoundsRef = useRef<NativeViewportBounds | null>(null);
  const controlledSessionsRef = useRef(new Set<string>());
  const inFlightRef = useRef(new Set<string>());
  const lastLayoutRef = useRef(new Map<string, { bounds: NativeViewportBounds; visible: boolean }>());
  const [dockedSessionIds, setDockedSessionIds] = useState<Set<string>>(() => new Set());
  const [externalSessionIds, setExternalSessionIds] = useState<Set<string>>(() => new Set());
  const [retryVersion, setRetryVersion] = useState(0);
  const noticeRef = useRef(onNotice);
  noticeRef.current = onNotice;

  const selectedSession = useMemo(
    () => sessions.find((session) => session.sessionId === selectedSessionId) || null,
    [selectedSessionId, sessions]
  );
  const isDocked = Boolean(
    selectedSession && (selectedSession.contained === true || dockedSessionIds.has(selectedSession.sessionId))
  );
  const explicitlyExternal = Boolean(selectedSession && externalSessionIds.has(selectedSession.sessionId));

  const measureSurface = useCallback((): NativeViewportBounds | null => {
    const surface = surfaceRef.current;
    if (!surface) return null;
    const bounds = nativeViewportBounds(surface.getBoundingClientRect(), viewportSize());
    if (bounds) lastBoundsRef.current = bounds;
    return bounds;
  }, []);

  const rememberDocked = useCallback((sessionId: string) => {
    controlledSessionsRef.current.add(sessionId);
    setDockedSessionIds((current) => {
      if (current.has(sessionId)) return current;
      const next = new Set(current);
      next.add(sessionId);
      return next;
    });
    setExternalSessionIds((current) => {
      if (!current.has(sessionId)) return current;
      const next = new Set(current);
      next.delete(sessionId);
      return next;
    });
  }, []);

  const showExternally = useCallback((sessionId: string) => {
    lastLayoutRef.current.delete(sessionId);
    setDockedSessionIds((current) => {
      if (!current.has(sessionId)) return current;
      const next = new Set(current);
      next.delete(sessionId);
      return next;
    });
    setExternalSessionIds((current) => new Set(current).add(sessionId));
  }, []);

  const sendLayout = useCallback(async (sessionId: string, bounds: NativeViewportBounds, visible: boolean) => {
    const previous = lastLayoutRef.current.get(sessionId);
    if (previous
      && previous.visible === visible
      && previous.bounds.x === bounds.x
      && previous.bounds.y === bounds.y
      && previous.bounds.width === bounds.width
      && previous.bounds.height === bounds.height) return;
    lastLayoutRef.current.set(sessionId, { bounds, visible });
    try {
      await nativeHostBridge.layoutSession(sessionId, bounds, visible);
    } catch (error) {
      lastLayoutRef.current.delete(sessionId);
      throw error;
    }
  }, []);

  useEffect(() => {
    const liveIds = new Set(sessions.map((session) => session.sessionId));
    setDockedSessionIds((current) => new Set([...current].filter((id) => liveIds.has(id))));
    setExternalSessionIds((current) => new Set([...current].filter((id) => liveIds.has(id))));
    for (const sessionId of controlledSessionsRef.current) {
      if (!liveIds.has(sessionId)) {
        controlledSessionsRef.current.delete(sessionId);
        lastLayoutRef.current.delete(sessionId);
      }
    }
  }, [sessions]);

  useEffect(() => {
    if (active || !selectedSession || !controlledSessionsRef.current.has(selectedSession.sessionId)) return;
    const bounds = lastBoundsRef.current;
    if (bounds) void sendLayout(selectedSession.sessionId, bounds, false).catch(() => {});
  }, [active, selectedSession?.sessionId, sendLayout]);

  useEffect(() => {
    const session = selectedSession;
    const surface = surfaceRef.current;
    if (!active || !session || !surface || !nativeHostBridge.available || explicitlyExternal) return;

    let disposed = false;
    let frame = 0;
    let scheduleTimer = 0;
    let lastSynchronizationAt = 0;
    let intersecting = true;
    const cloudWindow = surface.closest<HTMLElement>('.window');

    const surfaceIsTopmost = (bounds: NativeViewportBounds) => {
      if (cloudWindow && !cloudWindow.classList.contains('active')) return false;
      const centerX = Math.max(0, Math.min(document.documentElement.clientWidth - 1, bounds.x + Math.floor(bounds.width / 2)));
      const centerY = Math.max(0, Math.min(document.documentElement.clientHeight - 1, bounds.y + Math.floor(bounds.height / 2)));
      const topElement = document.elementFromPoint(centerX, centerY);
      return Boolean(topElement && surface.contains(topElement));
    };

    const synchronize = async () => {
      if (disposed || inFlightRef.current.has(session.sessionId)) return;
      const bounds = measureSurface();
      if (!bounds) return;
      const visible = !document.hidden && intersecting && surfaceIsTopmost(bounds);
      const alreadyDocked = session.contained === true || controlledSessionsRef.current.has(session.sessionId);
      inFlightRef.current.add(session.sessionId);
      try {
        if (alreadyDocked) {
          await sendLayout(session.sessionId, bounds, visible);
          rememberDocked(session.sessionId);
        } else if (visible) {
          await nativeHostBridge.attachSession(session.sessionId, bounds);
          lastLayoutRef.current.set(session.sessionId, { bounds, visible: true });
          rememberDocked(session.sessionId);
        }
      } catch (error) {
        if (!disposed) {
          showExternally(session.sessionId);
          noticeRef.current({
            tone: 'info',
            text: `${session.title} continua aberto em uma janela externa. ${error instanceof Error ? error.message : 'O Windows não permitiu fixar esta janela no Hub.'}`
          });
        }
      } finally {
        inFlightRef.current.delete(session.sessionId);
      }
    };

    const schedule = () => {
      window.cancelAnimationFrame(frame);
      window.clearTimeout(scheduleTimer);
      const delay = Math.max(0, 40 - (performance.now() - lastSynchronizationAt));
      scheduleTimer = window.setTimeout(() => {
        frame = window.requestAnimationFrame(() => {
          lastSynchronizationAt = performance.now();
          void synchronize();
        });
      }, delay);
    };
    const resizeObserver = new ResizeObserver(schedule);
    resizeObserver.observe(surface);
    const mutationObserver = new MutationObserver(schedule);
    if (cloudWindow) mutationObserver.observe(cloudWindow, { attributes: true, attributeFilter: ['class', 'style'] });
    const intersectionObserver = new IntersectionObserver((entries) => {
      intersecting = Boolean(entries[0]?.isIntersecting);
      schedule();
    }, { threshold: 0.05 });
    intersectionObserver.observe(surface);
    const visibilityListener = () => schedule();
    const movementListener = (event: MouseEvent) => { if (event.buttons) schedule(); };
    document.addEventListener('visibilitychange', visibilityListener);
    window.addEventListener('resize', schedule);
    window.addEventListener('scroll', schedule, true);
    window.addEventListener('mousemove', movementListener);
    schedule();

    return () => {
      disposed = true;
      window.cancelAnimationFrame(frame);
      window.clearTimeout(scheduleTimer);
      resizeObserver.disconnect();
      mutationObserver.disconnect();
      intersectionObserver.disconnect();
      document.removeEventListener('visibilitychange', visibilityListener);
      window.removeEventListener('resize', schedule);
      window.removeEventListener('scroll', schedule, true);
      window.removeEventListener('mousemove', movementListener);
      if (controlledSessionsRef.current.has(session.sessionId)) {
        const bounds = measureSurface() || lastBoundsRef.current;
        if (bounds) void sendLayout(session.sessionId, bounds, false).catch(() => {});
      }
    };
  }, [active, explicitlyExternal, measureSurface, rememberDocked, retryVersion, selectedSession?.contained, selectedSession?.sessionId, selectedSession?.title, sendLayout, showExternally]);

  useEffect(() => () => {
    for (const sessionId of controlledSessionsRef.current) {
      void nativeHostBridge.detachSession(sessionId).catch(() => {});
    }
    controlledSessionsRef.current.clear();
    lastLayoutRef.current.clear();
  }, []);

  const detachSelected = useCallback(async () => {
    if (!selectedSession) return;
    try {
      await nativeHostBridge.detachSession(selectedSession.sessionId);
      controlledSessionsRef.current.delete(selectedSession.sessionId);
      lastLayoutRef.current.delete(selectedSession.sessionId);
      showExternally(selectedSession.sessionId);
      onNotice({ tone: 'info', text: `${selectedSession.title} foi solto do Hub e continua aberto no desktop.` });
    } catch (error) {
      onNotice({ tone: 'error', text: error instanceof Error ? error.message : 'Não foi possível soltar a janela.' });
    }
  }, [onNotice, selectedSession, showExternally]);

  const retryAttach = useCallback(() => {
    if (!selectedSession) return;
    setExternalSessionIds((current) => {
      const next = new Set(current);
      next.delete(selectedSession.sessionId);
      return next;
    });
    setRetryVersion((current) => current + 1);
  }, [selectedSession]);

  return (
    <article className="native-dock-panel hub-panel">
      <div className="native-dock-toolbar">
        <div className="native-dock-heading">
          <span className={`status-dot ${isDocked ? 'ready' : selectedSession ? 'attention' : 'neutral'}`} />
          <div>
            <strong>{isDocked ? 'Aplicativo dentro do Hub' : selectedSession ? 'Janela externa' : 'Espaço de aplicativos'}</strong>
            <small>{selectedSession?.title || pendingAppName || 'Abra um aplicativo Windows ou Linux'}</small>
          </div>
        </div>
        <div className="native-dock-actions">
          {sessions.length > 1 && (
            <label>
              <span>Janela</span>
              <select value={selectedSessionId || ''} onChange={(event) => onSelect(event.target.value)}>
                {sessions.map((session) => <option key={session.sessionId} value={session.sessionId}>{session.title}</option>)}
              </select>
            </label>
          )}
          {selectedSession && <button onClick={() => nativeHostBridge.operate(selectedSession.minimized ? 'restore' : 'focus', selectedSession.sessionId).catch(() => {})}>Trazer</button>}
          {selectedSession && isDocked && <button onClick={detachSelected}>Soltar</button>}
          {selectedSession && explicitlyExternal && nativeHostBridge.available && <button className="primary-button" onClick={retryAttach}>Fixar no Hub</button>}
        </div>
      </div>

      <div
        ref={surfaceRef}
        className={`native-dock-surface ${isDocked ? 'docked' : explicitlyExternal ? 'external' : ''}`}
        aria-label="Área para o aplicativo nativo selecionado"
      >
        {!nativeHostBridge.available ? (
          <div className="native-dock-placeholder"><span>▣</span><strong>Abra pelo CloudOS Desktop</strong><p>O navegador comum pode iniciar o programa, mas somente o host nativo consegue mantê-lo preso neste espaço.</p></div>
        ) : pendingAppName && !selectedSession ? (
          <div className="native-dock-placeholder waiting"><span>↻</span><strong>Aguardando {pendingAppName}</strong><p>O Hub está identificando a janela criada pelo Windows.</p></div>
        ) : !selectedSession ? (
          <div className="native-dock-placeholder"><span>▦</span><strong>Nenhum aplicativo aberto</strong><p>Escolha um item do catálogo. Quando a janela for compatível, ela será fixada aqui automaticamente.</p></div>
        ) : explicitlyExternal ? (
          <div className="native-dock-placeholder"><span>↗</span><strong>{selectedSession.title} está fora do Hub</strong><p>Você pode continuar usando a janela no desktop ou tentar fixá-la novamente.</p><button className="primary-button" onClick={retryAttach}>Fixar no Hub</button></div>
        ) : (
          <div className="native-dock-placeholder waiting"><span>↻</span><strong>Preparando {selectedSession.title}</strong><p>A janela será ancorada neste espaço sem bloquear o restante do CloudOS.</p></div>
        )}
      </div>

      <footer className="native-dock-footnote">
        <span>O Windows continua renderizando o programa de forma nativa.</span>
        <span>Janelas de administrador, DRM ou brokers compartilhados podem permanecer externas.</span>
      </footer>
    </article>
  );
}
