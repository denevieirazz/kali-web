import React, { useEffect, useRef, useState } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';

export default function TerminalPane({ wsUrl, isActive }) {
  const terminalRef = useRef(null);
  const wsRef = useRef(null);
  const termRef = useRef(null);
  const fitAddonRef = useRef(null);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    if (!terminalRef.current) return;

    // 1. Inicializa o Terminal e o FitAddon
    const term = new Terminal({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: 'CaskaydiaCode Nerd Font, "Cascadia Code", "Fira Code", Menlo, monospace',
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
      scrollback: 5000,
      allowProposedApi: true,
    });
    
    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    termRef.current = term;
    fitAddonRef.current = fitAddon;

    // 2. CORREÇÃO DO ERRO DE DIMENSIONS:
    let animFrameId;
    const initWhenVisible = () => {
      const el = terminalRef.current;
      if (!el) return;

      if (el.offsetWidth > 0 && el.offsetHeight > 0) {
        try {
          term.open(el);
          fitAddon.fit();
          term.focus();
          setIsReady(true);
        } catch (e) {
          console.error('Erro ao renderizar terminal:', e);
        }
      } else {
        animFrameId = requestAnimationFrame(initWhenVisible);
      }
    };

    initWhenVisible();

    // 3. CORREÇÃO DO WEBSOCKET:
    const userToken = localStorage.getItem('cloudos_token') || '';
    const safeWsUrl = wsUrl ? wsUrl.replace('token=default', `token=${userToken}`) : (userToken ? `ws://localhost:8080?token=${userToken}` : `ws://localhost:8080`);

    const ws = new WebSocket(safeWsUrl);
    wsRef.current = ws;

    ws.onopen = () => {
      term.writeln('\x1b[32m[CloudOS]\x1b[0m Conexão estabelecida com o Kali WSL.');
      term.writeln('');
    };

    ws.onmessage = (event) => {
      term.write(event.data);
    };

    ws.onerror = (error) => {
      term.writeln('\x1b[31m[CloudOS] Erro de conexão com o backend do terminal.\x1b[0m');
    };

    ws.onclose = () => {
      term.writeln('\x1b[33m[CloudOS] Conexão fechada.\x1b[0m');
    };

    // 4. Captura o que o usuário digita e manda direto pro WSL
    term.onData((data) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(data);
      }
    });

    // 5. Resize listener
    const handleResize = () => {
      try {
        if (fitAddonRef.current && terminalRef.current?.offsetWidth > 0) {
          fitAddonRef.current.fit();
          if (ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows }));
          }
        }
      } catch (e) {}
    };

    window.addEventListener('resize', handleResize);

    // 6. Cleanup ao fechar a aba
    return () => {
      if (animFrameId) cancelAnimationFrame(animFrameId);
      window.removeEventListener('resize', handleResize);
      if (wsRef.current) {
        wsRef.current.close();
      }
      if (termRef.current) {
        termRef.current.dispose();
      }
    };
  }, [wsUrl]);

  return (
    <div style={{ width: '100%', height: '100%', background: '#0d1117', padding: '4px' }}>
      <div 
        ref={terminalRef} 
        style={{ 
          width: '100%', 
          height: '100%', 
          display: isReady ? 'block' : 'none'
        }} 
      />
      {!isReady && (
        <div style={{ padding: '20px', color: '#8b949e', fontFamily: 'monospace' }}>
          Inicializando terminal tático...
        </div>
      )}
    </div>
  );
}
