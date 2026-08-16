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
  const fitAddonRef = useRef<FitAddon | null>(null);
  const [restartGeneration, setRestartGeneration] = useState(0);
  const [status, setStatus] = useState<TerminalPaneStatus>(INITIAL_STATUS);
  const [dimensions, setDimensions] = useState({ cols: 100, rows: 28 });

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;

    let disposed = false;
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
    fitAddonRef.current = fitAddon;
    terminal.loadAddon(fitAddon);
    terminal.open(host);

    const publishStatus = (next: TerminalPaneStatus) => {
      if (disposed) return;
      setStatus(next);
      onStatusChange(tab.id, next);
    };

    const safeFit = () => {
      if (disposed || host.clientWidth <= 0 || host.clientHeight <= 0) return;
      try {
        fitAddon.fit();
        setDimensions({ cols: terminal.cols, rows: terminal.rows });
      } catch {
        // O layout pode estar transitório durante split/maximize/restore.
      }
    };

    const resizeObserver = new ResizeObserver(safeFit);
    resizeObserver.observe(host);
    requestAnimationFrame(safeFit);

    const token = getStoredToken();
    if (!token) {
      terminal.writeln('\x1b[1;31m[Faça login no CloudOS para abrir um terminal real.]\x1b[0m');
      publishStatus({ state: 'failed', label: 'Autenticação necessária', mode: null });
      return () => {
        disposed = true;
        resizeObserver.disconnect();
        fitAddonRef.current = null;
        terminal.dispose();
      };
    }

    publishStatus({ state: 'connecting', label: 'Conectando ao Terminal…', mode: null });
    const socket = new WebSocket(resolveWebSocketUrl('/ws/terminal'), [token]);
    const transport = createTerminalTransport({
      socket,
      profile: tab.profile,
      distribution: tab.profile === 'wsl' ? tab.distribution : '',
      initialCols: terminal.cols || 100,
      initialRows: terminal.rows || 28,
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

    const inputSubscription = terminal.onData(data => {
      transport.input(data);
    });
    const resizeSubscription = terminal.onResize(({ cols, rows }) => {
      setDimensions({ cols, rows });
      transport.resize(cols, rows);
    });

    return () => {
      disposed = true;
      resizeObserver.disconnect();
      inputSubscription.dispose();
      resizeSubscription.dispose();
      fitAddonRef.current = null;
      transport.dispose();
      terminal.dispose();
    };
  }, [onStatusChange, restartGeneration, tab.distribution, tab.id, tab.profile]);

  useEffect(() => {
    if (!visible) return;
    const frame = requestAnimationFrame(() => {
      try { fitAddonRef.current?.fit(); } catch { /* dimensão transitória */ }
    });
    return () => cancelAnimationFrame(frame);
  }, [visible]);

  return (
    <section
      className="terminal-pane"
      data-terminal-state={status.state}
      data-backend-mode={status.mode || ''}
      data-distribution={tab.profile === 'wsl' ? tab.distribution : ''}
      data-cols={dimensions.cols}
      data-rows={dimensions.rows}
    >
      <div className="terminal-pane__host" ref={hostRef} />
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
