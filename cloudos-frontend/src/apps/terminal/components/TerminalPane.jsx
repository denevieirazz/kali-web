import React, { useState, useEffect, useRef } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';

export function TerminalPane({ tabId, isActive }) {
  const containerRef = useRef(null);
  const termRef = useRef(null);
  const fitRef = useRef(null);
  const wsRef = useRef(null);
  const bufferRef = useRef([]);
  const [isInitialized, setIsInitialized] = useState(false);

  // 1. Conexão WebSocket (Roda independente de estar ativo ou não)
  useEffect(() => {
    const token = localStorage.getItem('cloudos_token');
    const ws = new WebSocket(`ws://localhost:8080?token=${encodeURIComponent(token || '')}`);
    wsRef.current = ws;

    ws.onopen = () => {
      // Se o terminal já existir, manda o tamanho inicial
      if (termRef.current) {
        try {
          ws.send(JSON.stringify({ type: 'resize', cols: termRef.current.cols, rows: termRef.current.rows }));
        } catch (e) {}
      }
    };

    ws.onmessage = (event) => {
      if (termRef.current) {
        if (typeof event.data === 'string') {
          termRef.current.write(event.data);
        } else {
          termRef.current.write(new Uint8Array(event.data));
        }
      } else {
        // Se o xterm ainda não montou, guarda no buffer
        bufferRef.current.push(event.data);
      }
    };

    return () => {
      if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
        ws.close();
      }
    };
  }, [tabId]);

  // 2. Inicialização do xterm (SÓ RODA QUANDO A ABA ESTÁ ATIVA)
  useEffect(() => {
    if (!isActive || !containerRef.current || isInitialized) return;

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
    setTimeout(() => { try { fit.fit(); } catch (e) {} }, 50);

    termRef.current = term;
    fitRef.current = fit;
    setIsInitialized(true);

    // Despeja o buffer acumulado enquanto inativo
    if (bufferRef.current.length > 0) {
      bufferRef.current.forEach(data => {
        if (typeof data === 'string') term.write(data);
        else term.write(new Uint8Array(data));
      });
      bufferRef.current = [];
    }

    // Input do usuário
    const onData = term.onData(data => {
      if (wsRef.current?.readyState === WebSocket.OPEN) {
        wsRef.current.send(data);
      }
    });

    // Resize
    const resizeObserver = new ResizeObserver(() => {
      if (containerRef.current && containerRef.current.offsetWidth > 0) {
        try {
          fit.fit();
          if (wsRef.current?.readyState === WebSocket.OPEN) {
            wsRef.current.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows }));
          }
        } catch (e) {}
      }
    });
    resizeObserver.observe(containerRef.current);

    return () => {
      onData.dispose();
      resizeObserver.disconnect();
      term.dispose();
    };
  }, [isActive, isInitialized]);

  // 3. Reajustar o tamanho quando voltar a ser ativo
  useEffect(() => {
    if (isActive && isInitialized && fitRef.current && containerRef.current) {
      setTimeout(() => {
        if (containerRef.current.offsetWidth > 0) {
          try {
            fitRef.current.fit();
          } catch (e) {}
        }
      }, 50);
    }
  }, [isActive, isInitialized]);

  return (
    <div 
      ref={containerRef} 
      className={`terminal-pane-container ${isActive ? 'active' : ''}`}
      style={{ 
        height: '100%', 
        width: '100%', 
        padding: '4px',
        display: isActive ? 'block' : 'none'
      }}
    />
  );
}

export default TerminalPane;
