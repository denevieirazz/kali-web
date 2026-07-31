import React, { useEffect, useRef, useCallback } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';

const TerminalPane = ({ wsUrl, isActive, theme }) => {
  const termContainerRef = useRef(null);
  const terminalRef = useRef(null);
  const fitAddonRef = useRef(new FitAddon());
  const wsRef = useRef(null);
  const bufferRef = useRef('');
  const observerRef = useRef(null);

  const initTerminal = useCallback(() => {
    if (terminalRef.current) return;

    const term = new Terminal({
      theme: theme.xterm,
      fontFamily: '"CaskaydiaCove Nerd Font", "JetBrains Mono", "Cascadia Code", monospace',
      fontSize: 15,
      lineHeight: 1.25,
      cursorBlink: true,
      cursorStyle: 'bar',
      scrollback: 10000,
      convertEol: true,
      allowTransparency: true,
    });

    term.loadAddon(fitAddonRef.current);
    term.open(termContainerRef.current);

    // Ajustar tamanho assim que possível
    setTimeout(() => {
      try { fitAddonRef.current.fit(); } catch (e) {}
    }, 50);

    // WebSocket
    const socket = new WebSocket(wsUrl);
    socket.onopen = () => {
      if (bufferRef.current) {
        term.write(bufferRef.current);
        bufferRef.current = '';
      }
    };
    socket.onmessage = (e) => {
      if (isActive) {
        term.write(e.data);
      } else {
        bufferRef.current += e.data;
      }
    };
    socket.onclose = () => term.write('\r\n\n\x1b[31mDesconectado.\x1b[0m\r\n');
    term.onData((data) => {
      if (socket.readyState === WebSocket.OPEN) socket.send(data);
    });

    terminalRef.current = term;
    wsRef.current = socket;

    // ResizeObserver para manter o fit correto
    const observer = new ResizeObserver(() => {
      try { fitAddonRef.current.fit(); } catch (e) {}
    });
    observer.observe(termContainerRef.current);
    observerRef.current = observer;

    return () => {
      observer.disconnect();
      socket.close();
      term.dispose();
      terminalRef.current = null;
    };
  }, [wsUrl, isActive, theme]);

  useEffect(() => {
    const cleanup = initTerminal();
    return () => { cleanup && cleanup(); };
  }, [initTerminal]);

  // Quando a aba ficar ativa, despeja buffer e reajusta
  useEffect(() => {
    if (isActive && terminalRef.current) {
      const term = terminalRef.current;
      if (bufferRef.current) {
        term.write(bufferRef.current);
        bufferRef.current = '';
      }
      setTimeout(() => {
        try { fitAddonRef.current.fit(); } catch (e) {}
      }, 10);
    }
  }, [isActive]);

  return (
    <div
      ref={termContainerRef}
      style={{
        width: '100%',
        height: '100%',
        background: theme.xterm.background,
        borderRadius: '0 0 8px 8px',
        overflow: 'hidden',
        boxShadow: 'inset 0 0 20px rgba(0,0,0,0.6)',
      }}
    />
  );
};

export default TerminalPane;
