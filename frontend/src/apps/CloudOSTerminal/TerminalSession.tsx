import { useEffect, useRef, useState } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import type { TerminalTabState } from '../../core/terminalWorkspaceState.js';
import { getStoredToken, resolveWebSocketUrl } from '../../services/apiClient';
import './CloudOSTerminal.transport.css';
import {
  createTerminalTransport,
  EMULATOR_MODE,
  LEGACY_MODE,
  WSL_CORE_MODE,
  type TerminalTransportStatus,
} from './terminalSessionTransport.js';
import {
  TerminalFrameScheduler,
  hasUsableTerminalGeometry,
  sanitizeTerminalLifecycleError,
  waitForTerminalGeometry,
} from './terminalVisualLifecycle.js';

export type TerminalPaneStatus = TerminalTransportStatus;

const INITIAL_STATUS: TerminalPaneStatus = { state: 'connecting', label: 'Preparando sessão…', mode: null };

function stateText(state: TerminalPaneStatus['state']) {
  switch (state) {
    case 'connecting': return 'conectando';
    case 'connected': return 'conectado';
    case 'closing': return 'encerrando';
    case 'closed': return 'fechado';
    case 'failed': return 'falhou';
    case 'legacy-fallback': return 'fallback legado';
  }
}

function transportText(status: TerminalPaneStatus, profile: TerminalTabState['profile']) {
  if (status.mode === WSL_CORE_MODE) return 'WSL Core v2';
  if (status.mode === LEGACY_MODE) return 'PTY legado';
  if (status.mode === EMULATOR_MODE) return 'Emulador legado';
  return profile === 'wsl' ? 'Aguardando backend' : 'PowerShell local';
}

function nextFrame() {
  return new Promise<void>(resolve => requestAnimationFrame(() => resolve()));
}

export function TerminalSession({
  tab,
  visible,
  onStatusChange,
}: {
  tab: TerminalTabState;
  visible: boolean;
  onStatusChange: (tabId: string, status: TerminalPaneStatus) => void;
}) {
  const hostRef = useRef<HTMLDivElement>(null);
  const fitSchedulerRef = useRef<TerminalFrameScheduler | null>(null);
  const [restartGeneration, setRestartGeneration] = useState(0);
  const [status, setStatus] = useState<TerminalPaneStatus>(INITIAL_STATUS);
  const [dimensions, setDimensions] = useState({ cols: 100, rows: 28 });
  const [visualError, setVisualError] = useState('');

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;

    let disposed = false;
    let disposeStarted = false;
    let resizeObserver: ResizeObserver | null = null;
    let inputSubscription: { dispose(): void } | null = null;
    let resizeSubscription: { dispose(): void } | null = null;
    let transport: ReturnType<typeof createTerminalTransport> | null = null;
    let socket: WebSocket | null = null;

    const terminal = new Terminal({
      theme: {
        background: '#090b12',
        foreground: '#e7edf8',
        cursor: '#7dd3fc',
        selectionBackground: '#334a73',
        green: '#34d399',
        cyan: '#67e8f9',
      },
      fontFamily: 'Cascadia Code, Cascadia Mono, Consolas, monospace',
      fontSize: 13,
      lineHeight: 1.15,
      cursorBlink: true,
      scrollback: 8000,
    });
    const fitAddon = new FitAddon();
    terminal.loadAddon(fitAddon);
    setVisualError('');

    const publishStatus = (next: TerminalPaneStatus) => {
      if (disposed) return;
      setStatus(next);
      onStatusChange(tab.id, next);
    };

    const disposeOnce = () => {
      if (disposeStarted) return;
      disposeStarted = true;
      disposed = true;
      fitSchedulerRef.current?.dispose();
      fitSchedulerRef.current = null;
      resizeObserver?.disconnect();
      resizeObserver = null;
      inputSubscription?.dispose();
      resizeSubscription?.dispose();
      inputSubscription = null;
      resizeSubscription = null;
      try { transport?.dispose(); } catch { /* teardown local */ }
      transport = null;
      if (socket && socket.readyState < WebSocket.CLOSING) {
        try { socket.close(1000, 'terminal-dispose'); } catch { /* teardown local */ }
      }
      socket = null;
      try { terminal.dispose(); } catch { /* dispose idempotente no boundary local */ }
    };

    const failVisual = (error: unknown, label = 'Falha visual do Terminal') => {
      if (disposed) return;
      const message = sanitizeTerminalLifecycleError(error);
      setVisualError(message);
      publishStatus({ state: 'failed', label, mode: null });
    };

    const initialise = async () => {
      const geometryReady = await waitForTerminalGeometry(host, { cancelled: () => disposed });
      if (disposed) return;
      if (!geometryReady) {
        failVisual(new Error('A janela do Terminal ainda não possui dimensões utilizáveis.'), 'Layout indisponível');
        return;
      }

      try {
        terminal.open(host);
      } catch (error) {
        failVisual(error, 'Renderer indisponível');
        return;
      }

      // O renderer/viewport do xterm é criado por open(). Um frame posterior evita
      // executar FitAddon enquanto as dimensões internas ainda estão indefinidas.
      await nextFrame();
      if (disposed || !hasUsableTerminalGeometry(host)) return;

      const fitScheduler = new TerminalFrameScheduler({
        task: () => {
          if (disposed || !hasUsableTerminalGeometry(host) || !terminal.element?.isConnected) return;
          try {
            fitAddon.fit();
            if (terminal.cols > 0 && terminal.rows > 0) {
              setDimensions({ cols: terminal.cols, rows: terminal.rows });
              setVisualError('');
            }
          } catch (error) {
            // FitAddon pode observar um frame transitório durante minimize/restore.
            // A exceção fica contida nesta pane e um próximo ResizeObserver tenta de novo.
            if (!disposed) setVisualError(sanitizeTerminalLifecycleError(error));
          }
        },
      });
      fitSchedulerRef.current = fitScheduler;
      resizeObserver = new ResizeObserver(() => fitScheduler.schedule());
      resizeObserver.observe(host);
      fitScheduler.schedule();

      const token = getStoredToken();
      if (!token) {
        terminal.writeln('\x1b[1;31m[Faça login no CloudOS para abrir um terminal real.]\x1b[0m');
        publishStatus({ state: 'failed', label: 'Autenticação necessária', mode: null });
        return;
      }

      publishStatus({ state: 'connecting', label: 'Conectando ao Terminal…', mode: null });
      socket = new WebSocket(resolveWebSocketUrl('/ws/terminal'), [token]);
      transport = createTerminalTransport({
        socket,
        profile: tab.profile,
        distribution: tab.profile === 'wsl' ? tab.distribution : '',
        initialCols: terminal.cols > 0 ? terminal.cols : 100,
        initialRows: terminal.rows > 0 ? terminal.rows : 28,
        onOutput: data => {
          if (!disposed) terminal.write(data);
        },
        onStatus: publishStatus,
        onExit: () => {
          if (!disposed) terminal.writeln('\r\n\x1b[1;33m[Sessão encerrada]\x1b[0m');
        },
        onNotice: notice => {
          if (disposed) return;
          const color = notice.tone === 'error' ? '31' : '33';
          terminal.writeln(`\r\n\x1b[1;${color}m[${notice.message}]\x1b[0m`);
        },
      });

      inputSubscription = terminal.onData(data => {
        if (!disposed) transport?.input(data);
      });
      resizeSubscription = terminal.onResize(({ cols, rows }) => {
        if (disposed || cols <= 0 || rows <= 0) return;
        setDimensions({ cols, rows });
        transport?.resize(cols, rows);
      });
    };

    void initialise().catch(error => failVisual(error));
    return disposeOnce;
  }, [onStatusChange, restartGeneration, tab.distribution, tab.id, tab.profile]);

  useEffect(() => {
    if (visible) fitSchedulerRef.current?.schedule();
  }, [visible]);

  return (
    <section
      className="terminal-pane"
      data-terminal-state={status.state}
      data-backend-mode={status.mode || ''}
      data-distribution={tab.profile === 'wsl' ? tab.distribution : ''}
      data-cols={dimensions.cols}
      data-rows={dimensions.rows}
      data-terminal-visual-error={visualError ? 'true' : 'false'}
    >
      <div className="terminal-pane__host" ref={hostRef} />
      {visualError && (
        <div className="terminal-pane__visual-error" role="status">
          Layout do Terminal em recuperação. {visualError}
        </div>
      )}
      <footer className="terminal-pane__footer" aria-live="polite">
        <div className="terminal-pane__runtime">
          <span>{tab.profile === 'wsl' ? `Linux: ${tab.distribution || 'WSL'}` : 'Sistema: Windows'}</span>
          <span>Transporte: {transportText(status, tab.profile)}</span>
          <span>Estado: {stateText(status.state)}</span>
        </div>
        <button type="button" onClick={() => setRestartGeneration(value => value + 1)}>↻ Reconectar</button>
      </footer>
    </section>
  );
}
