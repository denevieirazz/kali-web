import { useEffect, useRef, useState } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import type { TerminalTabState } from '../../core/terminalWorkspaceState.js';
import { getStoredToken, resolveWebSocketUrl } from '../../services/apiClient';

export type TerminalPaneStatus = {
  state: 'connecting' | 'active' | 'closed' | 'error' | 'auth';
  label: string;
};

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

    const safeFit = () => {
      if (disposed || host.clientWidth <= 0 || host.clientHeight <= 0) return;
      try { fitAddon.fit(); } catch { /* layout ainda estabilizando */ }
    };

    const resizeObserver = new ResizeObserver(safeFit);
    resizeObserver.observe(host);
    requestAnimationFrame(safeFit);

    const token = getStoredToken();
    if (!token) {
      terminal.writeln('\x1b[1;31m[Faça login no CloudOS para abrir um terminal real.]\x1b[0m');
      onStatusChange(tab.id, { state: 'auth', label: 'Autenticação necessária' });
      return () => {
        disposed = true;
        resizeObserver.disconnect();
        fitAddonRef.current = null;
        terminal.dispose();
      };
    }

    onStatusChange(tab.id, { state: 'connecting', label: 'Conectando ao agente local…' });
    const socket = new WebSocket(resolveWebSocketUrl('/ws/terminal'), [token]);
    const inputSubscription = terminal.onData(data => {
      if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'input', data }));
    });
    const resizeSubscription = terminal.onResize(({ cols, rows }) => {
      if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'resize', cols, rows }));
    });

    socket.onopen = () => {
      if (disposed) return socket.close();
      safeFit();
      socket.send(JSON.stringify({
        type: 'start',
        profile: tab.profile,
        distribution: tab.profile === 'wsl' ? tab.distribution : undefined,
        cols: terminal.cols || 100,
        rows: terminal.rows || 28,
      }));
      onStatusChange(tab.id, {
        state: 'active',
        label: tab.profile === 'wsl' ? `WSL · ${tab.distribution || 'Linux'}` : 'PowerShell · Windows',
      });
    };

    socket.onmessage = event => {
      if (disposed) return;
      try {
        const message = JSON.parse(String(event.data)) as { type?: string; data?: unknown };
        if (message.type === 'output') terminal.write(String(message.data ?? ''));
        else if (message.type === 'error') terminal.writeln(`\r\n\x1b[1;31m[${String(message.data ?? 'Erro')}]\x1b[0m`);
        else if (message.type === 'exit') {
          terminal.writeln('\r\n\x1b[1;33m[Sessão encerrada]\x1b[0m');
          onStatusChange(tab.id, { state: 'closed', label: 'Sessão encerrada' });
        }
      } catch {
        terminal.write(String(event.data));
      }
    };

    socket.onerror = () => {
      if (!disposed) onStatusChange(tab.id, { state: 'error', label: 'Falha na conexão' });
    };
    socket.onclose = () => {
      if (!disposed) onStatusChange(tab.id, { state: 'closed', label: 'Conexão encerrada' });
    };

    return () => {
      disposed = true;
      resizeObserver.disconnect();
      inputSubscription.dispose();
      resizeSubscription.dispose();
      fitAddonRef.current = null;
      try {
        if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'close' }));
        socket.close();
      } catch {
        // O backend também encerra o PTY quando o socket fecha.
      }
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
    <section className="terminal-pane">
      <div className="terminal-pane__host" ref={hostRef} />
      <footer className="terminal-pane__footer">
        <span>{tab.profile === 'wsl' ? `Linux · ${tab.distribution || 'WSL'}` : 'Windows · PowerShell'}</span>
        <button type="button" onClick={() => setRestartGeneration(value => value + 1)}>↻ Reconectar</button>
      </footer>
    </section>
  );
}
