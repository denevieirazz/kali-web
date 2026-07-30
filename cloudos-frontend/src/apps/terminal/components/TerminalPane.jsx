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

  // 1. Conexão WebSocket (Com atraso para ignorar o Strict Mode)
  useEffect(() => {
    let ws = null;
    
    // Atrasa a conexão em 50ms. Se o React desmontar antes (Strict Mode), cancela.
    const timer = setTimeout(() => {
      const token = localStorage.getItem('cloudos_token');
      ws = new WebSocket(`ws://localhost:8080?token=${encodeURIComponent(token || '')}`);
      wsRef.current = ws;

      ws.onmessage = (event) => {
        if (termRef.current) {
          if (typeof event.data === 'string') {
            termRef.current.write(event.data);
          } else {
            termRef.current.write(new Uint8Array(event.data));
          }
        } else {
          bufferRef.current.push(event.data);
        }
      };
    }, 50);

    return () => {
      clearTimeout(timer); // Cancela a criação se desmontar rápido
      if (ws) {
        ws.onmessage = null; // Remove o listener para evitar memory leak
        if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
          ws.close();
        }
      }
    };
  }, [tabId]);

  // 2. Inicialização do xterm
  useEffect(() => {
    if (!isActive || isInitialized) return;

    const initTimer = setTimeout(() => {
      if (!containerRef.current || containerRef.current.offsetWidth === 0) return;

      const term = new Terminal({
        theme: {
          background: '#0d111700', // Fundo transparente para pegar o CSS da div
          foreground: '#c9d1d9',
          cursor: '#58a6ff',
          black: '#0d1117', red: '#ff7b72', green: '#3fb950', yellow: '#d29922',
          blue: '#58a6ff', magenta: '#bc8cff', cyan: '#39c5cf', white: '#c9d1d9'
        },
        fontFamily: '"Cascadia Code", "Fira Code", Menlo, monospace',
        fontSize: 14,
        cursorBlink: true,
        scrollback: 5000,
        allowProposedApi: true
      });

      const fit = new FitAddon();
      term.loadAddon(fit);
      
      term.open(containerRef.current);
      
      if (bufferRef.current.length > 0) {
        bufferRef.current.forEach(data => {
          if (typeof data === 'string') term.write(data);
          else term.write(new Uint8Array(data));
        });
        bufferRef.current = [];
      }

      termRef.current = term;
      fitRef.current = fit;
      setIsInitialized(true);

      try { fit.fit(); } catch (e) {}

      // Manda apenas os dados puros das teclas (sem JSON)
      const onData = term.onData(data => {
        if (wsRef.current?.readyState === WebSocket.OPEN) {
          wsRef.current.send(data);
        }
      });

      const resizeObserver = new ResizeObserver(() => {
        if (containerRef.current && containerRef.current.offsetWidth > 0) {
          try { fit.fit(); } catch (e) {}
        }
      });
      resizeObserver.observe(containerRef.current);

      return () => {
        onData.dispose();
        resizeObserver.disconnect();
      };
    }, 100); // 100ms para garantir que o CSS aplicou o tamanho na div

    return () => clearTimeout(initTimer);
  }, [isActive, isInitialized]);

  // 3. Reajustar o tamanho quando voltar a ser ativo
  useEffect(() => {
    if (isActive && isInitialized && fitRef.current && containerRef.current) {
      const resizeTimer = setTimeout(() => {
        if (containerRef.current && containerRef.current.offsetWidth > 0) {
          try { fitRef.current.fit(); } catch (e) {}
        }
      }, 50);
      return () => clearTimeout(resizeTimer);
    }
  }, [isActive, isInitialized]);

  return (
    <div 
      ref={containerRef} 
      className={`terminal-pane-container ${isActive ? 'active' : ''}`}
      style={{ 
        height: '100%', 
        width: '100%', 
        display: isActive ? 'block' : 'none'
      }}
    />
  );
}

export default TerminalPane;
