import React, { useEffect, useRef, useCallback } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';

const TerminalPane = ({ wsUrl, isActive }) => {
  const termRef = useRef(null);
  const terminal = useRef(null);
  const ws = useRef(null);
  const fitAddon = useRef(new FitAddon());
  const bufferRef = useRef('');

  const initTerminal = useCallback(() => {
    if (terminal.current) return;

    const el = termRef.current;
    if (!el || el.offsetWidth === 0 || el.offsetHeight === 0) return;

    terminal.current = new Terminal({
      theme: {
        background: '#0d1117cc',
        foreground: '#c9d1d9',
        cursor: '#58a6ff',
        selection: '#58a6ff40',
        black: '#161b22',
        red: '#f85149',
        green: '#3fb950',
        yellow: '#d2991d',
        blue: '#58a6ff',
        magenta: '#bc8cff',
        cyan: '#39c5cf',
        white: '#b1bac4',
        brightBlack: '#6e7681',
        brightRed: '#ff7b72',
        brightGreen: '#56d364',
        brightYellow: '#e3b341',
        brightBlue: '#79c0ff',
        brightMagenta: '#d2a8ff',
        brightCyan: '#56d4dd',
        brightWhite: '#f0f6fc',
      },
      fontFamily: 'CaskaydiaCode Nerd Font, "Cascadia Code", "Fira Code", Menlo, monospace',
      fontSize: 14,
      cursorBlink: true,
      cursorStyle: 'bar',
      allowProposedApi: true,
      scrollback: 5000,
    });

    terminal.current.loadAddon(fitAddon.current);
    terminal.current.open(el);

    setTimeout(() => {
      try { fitAddon.current.fit(); } catch (e) {}
    }, 50);

    const onResize = () => {
      try { fitAddon.current.fit(); } catch (e) {}
    };
    window.addEventListener('resize', onResize);

    const token = localStorage.getItem('cloudos_token');
    const safeWsUrl = wsUrl.replace('token=default', `token=${token || ''}`);
    const socket = new WebSocket(safeWsUrl);
    socket.onopen = () => {
      if (bufferRef.current) {
        terminal.current.write(bufferRef.current);
        bufferRef.current = '';
      }
    };
    socket.onmessage = (e) => {
      if (isActive) {
        terminal.current.write(e.data);
      } else {
        bufferRef.current += e.data;
      }
    };
    socket.onclose = () => terminal.current?.write('\r\n\r\n\x1b[31mDesconectado.\x1b[0m\r\n');
    terminal.current.onData((data) => {
      if (socket.readyState === WebSocket.OPEN) socket.send(data);
    });

    ws.current = socket;

    return () => {
      window.removeEventListener('resize', onResize);
      socket.close();
      terminal.current?.dispose();
      terminal.current = null;
    };
  }, [wsUrl, isActive]);

  useEffect(() => {
    let animFrameId;

    const initWhenVisible = () => {
      const el = termRef.current;
      if (!el) return;

      if (el.offsetWidth > 0 && el.offsetHeight > 0) {
        initTerminal();
      } else {
        animFrameId = requestAnimationFrame(initWhenVisible);
      }
    };

    initWhenVisible();

    return () => {
      if (animFrameId) cancelAnimationFrame(animFrameId);
    };
  }, [initTerminal]);

  useEffect(() => {
    if (isActive && terminal.current) {
      setTimeout(() => {
        try { fitAddon.current.fit(); } catch (e) {}
      }, 50);
    }
  }, [isActive]);

  return (
    <div
      className="terminal-pane-wrapper"
      style={{
        position: 'relative',
        width: '100%',
        height: '100%',
        borderRadius: '0 0 8px 8px',
        overflow: 'hidden',
        background: 'rgba(13, 17, 23, 0.8)',
        backdropFilter: 'blur(12px)',
        WebkitBackdropFilter: 'blur(12px)',
        border: '1px solid #30363d',
        boxShadow: '0 0 15px rgba(88, 166, 255, 0.2), inset 0 0 30px rgba(0,0,0,0.8)',
      }}
    >
      <div className="scanlines" style={{
        position: 'absolute',
        top: 0, left: 0, right: 0, bottom: 0,
        background: 'repeating-linear-gradient(0deg, rgba(0,0,0,0.15) 0px, rgba(0,0,0,0.15) 1px, transparent 1px, transparent 2px)',
        pointerEvents: 'none',
        zIndex: 1,
        opacity: 0.3,
      }} />
      <div
        ref={termRef}
        style={{
          width: '100%',
          height: '100%',
          position: 'relative',
          zIndex: 2,
        }}
      />
    </div>
  );
};

export default TerminalPane;
