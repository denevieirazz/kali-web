import React, { useEffect, useRef } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';

export function TerminalPane({ sessionId, ws, active }) {
  const containerRef = useRef(null);
  const termRef = useRef(null);
  const fitRef = useRef(null);

  useEffect(() => {
    if (!containerRef.current || !ws) return;

    const term = new Terminal({
      theme: {
        background: '#0d1117', foreground: '#c9d1d9', cursor: '#58a6ff',
        black: '#0d1117', red: '#ff7b72', green: '#3fb950', yellow: '#d29922',
        blue: '#58a6ff', magenta: '#bc8cff', cyan: '#39c5cf', white: '#c9d1d9'
      },
      fontFamily: 'Consolas, "Cascadia Code", "Fira Code", monospace',
      fontSize: 14,
      cursorBlink: true,
      scrollback: 10000
    });

    const fit = new FitAddon();
    
    term.loadAddon(fit);
    term.open(containerRef.current);
    setTimeout(() => { try { fit.fit(); } catch (e) {} }, 50);

    termRef.current = term;
    fitRef.current = fit;

    // Anexa à sessão existente
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'attach', sessionId }));
    }

    // Listener de mensagens do WS (apenas para esta sessão)
    const onWsMessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === 'output' && msg.sessionId === sessionId) {
          term.write(msg.data);
        }
      } catch (e) {}
    };

    ws.addEventListener('message', onWsMessage);

    // Input do usuário
    const onData = term.onData(data => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: 'input', sessionId, data }));
      }
    });

    // Resize
    const resizeObserver = new ResizeObserver(() => {
      try {
        fit.fit();
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'resize', sessionId, cols: term.cols, rows: term.rows }));
        }
      } catch (e) {}
    });
    resizeObserver.observe(containerRef.current);

    return () => {
      onData.dispose();
      ws.removeEventListener('message', onWsMessage);
      resizeObserver.disconnect();
      term.dispose();
    };
  }, [sessionId, ws]);

  return (
    <div 
      ref={containerRef} 
      className={`terminal-pane-container ${active ? 'active' : ''}`}
      style={{ height: '100%', width: '100%', padding: '4px' }}
    />
  );
}

export default TerminalPane;
