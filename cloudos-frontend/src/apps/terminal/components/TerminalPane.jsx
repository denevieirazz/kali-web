import React, { useEffect, useRef } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';

/**
 * TerminalPane - Cada instância abre sua PRÓPRIA conexão WebSocket.
 * O backend (server.js) cria um PTY por conexão e manda dados brutos.
 * Sem protocolo JSON de sessão — dados vão e voltam como texto puro.
 */
export function TerminalPane({ tabId, cwd, active }) {
  const containerRef = useRef(null);
  const termRef = useRef(null);
  const wsRef = useRef(null);
  const fitRef = useRef(null);
  const initializedRef = useRef(false);

  useEffect(() => {
    // Impede dupla inicialização no React Strict Mode
    if (initializedRef.current || !containerRef.current) return;
    initializedRef.current = true;

    // 1. Cria instância do xterm
    const term = new Terminal({
      theme: {
        background: '#0d1117', foreground: '#c9d1d9', cursor: '#58a6ff',
        black: '#0d1117', red: '#ff7b72', green: '#3fb950', yellow: '#d29922',
        blue: '#58a6ff', magenta: '#bc8cff', cyan: '#39c5cf', white: '#c9d1d9'
      },
      fontFamily: 'Consolas, "Cascadia Code", "Fira Code", monospace',
      fontSize: 14,
      cursorBlink: true,
      scrollback: 5000
    });

    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(containerRef.current);

    termRef.current = term;
    fitRef.current = fit;

    // Fit inicial com um pequeno delay para garantir que o container tem dimensões
    setTimeout(() => { try { fit.fit(); } catch (e) {} }, 100);

    // 2. Abre uma conexão WebSocket dedicada para este terminal
    const token = localStorage.getItem('cloudos_token');
    const wsUrl = `ws://localhost:8080?token=${encodeURIComponent(token || '')}`;
    const ws = new WebSocket(wsUrl);
    ws.binaryType = 'arraybuffer';
    wsRef.current = ws;

    ws.onopen = () => {
      // Faz fit e envia resize para o backend dimensionar o PTY corretamente
      try {
        fit.fit();
        ws.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows }));
      } catch (e) {}

      // Se veio com um diretório de trabalho, navega para ele
      if (cwd) {
        setTimeout(() => {
          if (ws.readyState === WebSocket.OPEN) {
            ws.send(`cd "${cwd}"\r`);
          }
        }, 300);
      }
    };

    // 3. Dados do backend (saída do PTY) -> escreve no xterm
    ws.onmessage = (event) => {
      if (!term) return;
      if (typeof event.data === 'string') {
        term.write(event.data);
      } else {
        // ArrayBuffer (binaryType)
        term.write(new Uint8Array(event.data));
      }
    };

    ws.onerror = () => {
      term.write('\r\n\x1b[31m[Erro] Falha na conexão com o backend (porta 8080).\x1b[0m\r\n');
    };

    ws.onclose = () => {
      term.write('\r\n\x1b[33m[Desconectado] Sessão encerrada.\x1b[0m\r\n');
    };

    // 4. Entrada do usuário (teclado) -> envia para o backend
    const onData = term.onData(data => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(data);
      }
    });

    // 5. Observador de redimensionamento
    const resizeObserver = new ResizeObserver(() => {
      try {
        fit.fit();
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows }));
        }
      } catch (e) {}
    });
    resizeObserver.observe(containerRef.current);

    // 6. Cleanup ao desmontar
    return () => {
      initializedRef.current = false;
      onData.dispose();
      resizeObserver.disconnect();
      if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
        ws.close();
      }
      term.dispose();
    };
  }, [tabId]);

  return (
    <div 
      ref={containerRef} 
      className={`terminal-pane-container ${active ? 'active' : ''}`}
      style={{ height: '100%', width: '100%', padding: '4px' }}
    />
  );
}

export default TerminalPane;
