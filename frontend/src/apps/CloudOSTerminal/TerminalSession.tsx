import { useEffect, useRef, useState } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import type { TerminalTabState } from '../../core/terminalWorkspaceState.js';
import { buildWslCdCommand } from '../../core/workflowCore.js';
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
  disposeTerminalAfterViewportSettles,
  hasUsableTerminalGeometry,
  sanitizeTerminalLifecycleError,
  waitForTerminalGeometry,
} from './terminalVisualLifecycle.js';

export type TerminalPaneStatus = TerminalTransportStatus;

const INITIAL_STATUS: TerminalPaneStatus = { state: 'connecting', label: 'Preparando sessão…' };

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
  const layoutRecoveryRequestedRef = useRef(false);
  const [restartGeneration, setRestartGeneration] = useState(0);
  const [status, setStatus] = useState<TerminalPaneStatus>(INITIAL_STATUS);
  const [dimensions, setDimensions] = useState({ cols: 100, rows: 28 });
  const [visualError, setVisualError] = useState('');
  const initialDirectoryKey = tab.initialDirectory?.provider === 'wsl' ? tab.initialDirectory.path.join('\u0000') : '';

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
    let initialDirectoryApplied = false;

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

    const applyInitialDirectory = () => {
      if (initialDirectoryApplied || tab.profile !== 'wsl' || tab.initialDirectory?.provider !== 'wsl') return;
      try {
        const command = buildWslCdCommand(tab.initialDirectory.path);
        transport?.input(`${command}\r`);
        initialDirectoryApplied = true;
      } catch {
        initialDirectoryApplied = true;
        terminal.writeln('\r\n\x1b[1;33m[O caminho inicial solicitado foi recusado.]\x1b[0m');
      }
    };

    const publishTransportStatus = (next: TerminalPaneStatus) => {
      publishStatus(next);
      if (next.state === 'connected') applyInitialDirectory();
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
      disposeTerminalAfterViewportSettles(terminal);
    };

    const failVisual = (error: unknown, label = 'Falha visual do Terminal') => {
      if (disposed) return;
      const message = sanitizeTerminalLifecycleError(error);
      setVisualError(message);
      publishStatus({ state: 'failed', label });
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
            if (!disposed) setVisualError(sanitizeTerminalLifecycleError(error));
          }
        },
      });
      fitSchedulerRef.current = fitScheduler;
      layoutRecoveryRequestedRef.current = false;
      resizeObserver = new ResizeObserver(() => fitScheduler.schedule());
      resizeObserver.observe(host);
      fitScheduler.schedule();

      const token = getStoredToken();
      if (!token) {
        terminal.writeln('\x1b[1;31m[Faça login no CloudOS para abrir um terminal real.]\x1b[0m');
        publishStatus({ state: 'failed', label: 'Autenticação necessária' });
        return;
      }

      publishStatus({ state: 'connecting', label: 'Conectando ao Terminal…' });
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
        onStatus: publishTransportStatus,
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
  }, [initialDirectoryKey, onStatusChange, restartGeneration, tab.distribution, tab.id, tab.profile]);

  useEffect(() => {
    if (!visible) {
      layoutRecoveryRequestedRef.current = false;
      return;
    }
    if (fitSchedulerRef.current) {
      layoutRecoveryRequestedRef.current = false;
      fitSchedulerRef.current.schedule();
      return;
    }
    if (status.state === 'failed' && status.label === 'Layout indisponível' && !layoutRecoveryRequestedRef.current) {
      layoutRecoveryRequestedRef.current = true;
      setRestartGeneration(value => value + 1);
    }
  }, [status.label, status.state, visible]);

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
