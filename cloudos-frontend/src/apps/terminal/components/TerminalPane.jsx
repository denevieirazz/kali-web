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

  // 1. Conexão WebSocket Raw
  useEffect(() => {
    let ws = null;
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
      clearTimeout(timer);
      if (ws) {
        ws.onmessage = null;
        if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) ws.close();
      }
    };
  }, [tabId]);

  // 2. Inicialização xterm Pro com GPU WebGL
  useEffect(() => {
    if (!isActive || isInitialized) return;

    const initTimer = setTimeout(() => {
      if (!containerRef.current || containerRef.current.offsetWidth === 0) return;

      const term = new Terminal({
        theme: {
          background: '#0d111700', foreground: '#c9d1d9', cursor: '#58a6ff',
          black: '#0d1117', red: '#ff7b72', green: '#3fb950', yellow: '#d29922',
          blue: '#58a6ff', magenta: '#bc8cff', cyan: '#39c5cf', white: '#c9d1d9'
        },
        fontFamily: '"CaskaydiaCove Nerd Font", "JetBrains Mono", "Cascadia Code", Menlo, monospace',
        fontSize: 15,
        lineHeight: 1.25,
        cursorBlink: true,
        cursorStyle: 'bar',
        scrollback: 10000,
        convertEol: true,
        allowProposedApi: true,
        allowTransparency: true
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
    }, 100);

    return () => clearTimeout(initTimer);
  }, [isActive, isInitialized]);

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
      style={{ height: '100%', width: '100%', display: isActive ? 'block' : 'none' }}
    />
  );
}

export default TerminalPane;
