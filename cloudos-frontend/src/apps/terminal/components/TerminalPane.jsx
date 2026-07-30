import React, { useEffect, useRef } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';

export function TerminalPane({ tabId }) {
  const containerRef = useRef(null);
  const termRef = useRef(null);
  const wsRef = useRef(null);

  useEffect(() => {
    if (!containerRef.current) return;

    const term = new Terminal({
      theme: {
        background: '#0d1117', foreground: '#c9d1d9', cursor: '#58a6ff',
        black: '#0d1117', red: '#ff7b72', green: '#3fb950', yellow: '#d29922',
        blue: '#58a6ff', magenta: '#bc8cff', cyan: '#39c5cf', white: '#c9d1d9'
      },
      fontFamily: 'Consolas, "Cascadia Code", "Fira Code", monospace',
      fontSize: 14,
      cursorBlink: true,
      scrollback: 5000,
      allowProposedApi: true
    });

    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(containerRef.current);
    setTimeout(() => { try { fit.fit(); } catch(e) {} }, 100);

    termRef.current = term;

    const token = localStorage.getItem('cloudos_token');
    const ws = new WebSocket(`ws://localhost:8080?token=${encodeURIComponent(token || '')}`);
    wsRef.current = ws;

    ws.onopen = () => {
      try {
        fit.fit();
        ws.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows }));
      } catch(e) {}
    };

    ws.onmessage = (event) => {
      if (typeof event.data === 'string') {
        term.write(event.data);
      } else {
        term.write(new Uint8Array(event.data));
      }
    };

    const onData = term.onData(data => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(data);
      }
    });

    const resizeObserver = new ResizeObserver(() => {
      try {
        fit.fit();
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows }));
        }
      } catch(e) {}
    });
    resizeObserver.observe(containerRef.current);

    return () => {
      onData.dispose();
      resizeObserver.disconnect();
      if (ws.readyState === WebSocket.OPEN) ws.close();
      term.dispose();
    };
  }, [tabId]);

  return (
    <div 
      ref={containerRef} 
      className="terminal-pane-container active"
      style={{ height: '100%', width: '100%', padding: '4px' }}
    />
  );
}

export default TerminalPane;
