import { useEffect, useRef } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';

export const TerminalApp = ({ payload }) => {
  const termRef = useRef(null);

  useEffect(() => {
    if (!termRef.current) return;

    let term;
    let fit;
    let ws;
    let ro;
    let resizeTimeout;

    const initTimer = setTimeout(() => {
      if (!termRef.current) return;

      try {
        term = new Terminal({
          cursorBlink: true,
          fontSize: 14,
          fontFamily: 'Consolas, "Courier New", monospace',
          theme: { background: '#0a0a0a', foreground: '#e0e0e0', cursor: '#ffffff' }
        });
        
        fit = new FitAddon();
        term.loadAddon(fit);
        term.open(termRef.current);
        
        setTimeout(() => {
          if (fit && termRef.current) {
            try { fit.fit(); } catch (e) {}
          }
        }, 50);

        const token = localStorage.getItem('cloudos_token');
        const wsUrl = `ws://localhost:8080?token=${encodeURIComponent(token || '')}`;
        ws = new WebSocket(wsUrl);
        ws.binaryType = 'arraybuffer';

        ws.onopen = () => {
          if (fit) {
            try {
              fit.fit();
              ws.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows }));
            } catch (e) {}
          }
          if (payload?.cwd) {
            setTimeout(() => {
              if (ws.readyState === WebSocket.OPEN) {
                ws.send(`cd "${payload.cwd}"\r`);
              }
            }, 300);
          }
          if (payload?.tool) {
            setTimeout(() => {
              if (ws.readyState === WebSocket.OPEN) {
                ws.send(`# Tool selected: ${payload.tool}\r\n`);
              }
            }, 500);
          }
        };

        ws.onmessage = (event) => {
          if (term) term.write(new Uint8Array(event.data));
        };

        term.onData((data) => {
          if (ws && ws.readyState === WebSocket.OPEN) ws.send(data);
        });

        ro = new ResizeObserver(() => {
          clearTimeout(resizeTimeout);
          resizeTimeout = setTimeout(() => {
            if (fit && termRef.current && ws && ws.readyState === WebSocket.OPEN) {
              try {
                fit.fit();
                ws.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows }));
              } catch (e) {}
            }
          }, 100);
        });
        ro.observe(termRef.current);
      } catch (err) {
        console.error("Erro ao inicializar Terminal:", err);
      }
    }, 150);

    return () => {
      clearTimeout(initTimer);
      clearTimeout(resizeTimeout);
      if (ro) ro.disconnect();
      if (ws) ws.close();
      if (term) term.dispose();
    };
  }, [payload]);

  return <div ref={termRef} style={{ width: '100%', height: '100%', backgroundColor: '#0a0a0a', overflow: 'hidden' }} />;
};
