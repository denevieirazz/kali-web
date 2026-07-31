import React, { useEffect, useRef, useState } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';

export default function TerminalPane({ wsUrl, isActive }) {
  const terminalRef = useRef(null);
  const termRef = useRef(null);
  const wsRef = useRef(null);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    let isMounted = true;

    // 1. Inicializa o terminal
    const term = new Terminal({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: 'CaskaydiaCode Nerd Font, "Cascadia Code", "Fira Code", Menlo, monospace',
      theme: { background: '#0d1117', foreground: '#c9d1d9', cursor: '#58a6ff' },
      scrollback: 5000,
      allowProposedApi: true,
    });

    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    termRef.current = term;

    // 2. Atraso de 100ms para garantir que o React 18 terminou de montar a DIV
    // Isso mata completamente o erro de "dimensions undefined"
    const initTimer = setTimeout(() => {
      if (!isMounted || !terminalRef.current) return;

      try {
        term.open(terminalRef.current);
        fitAddon.fit();
        term.focus();
        setIsReady(true);

        // 3. Conecta ao WebSocket direto mantendo suporte a JWT se disponível
        const token = localStorage.getItem('cloudos_token');
        const targetWsUrl = token ? `ws://localhost:8080?token=${token}` : 'ws://localhost:8080';
        const ws = new WebSocket(targetWsUrl);
        wsRef.current = ws;

        ws.onopen = () => {
          term.writeln('\x1b[32m[CloudOS]\x1b[0m Conexão estabelecida com Kali WSL.');
          term.writeln('');
        };

        ws.onmessage = (e) => {
          term.write(e.data);
        };

        ws.onerror = () => {
          term.writeln('\x1b[31m[CloudOS] Erro: Backend offline.\x1b[0m');
        };

        ws.onclose = () => {
          term.writeln('\x1b[33m[CloudOS] Conexão fechada.\x1b[0m');
        };

        term.onData((data) => {
          if (ws.readyState === WebSocket.OPEN) ws.send(data);
        });

      } catch (e) {
        console.error('Erro ao abrir xterm:', e);
      }
    }, 100);

    // 4. Limpeza rigorosa (Anti-Strict Mode do React 18)
    return () => {
      isMounted = false;
      clearTimeout(initTimer);
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
      if (termRef.current) {
        termRef.current.dispose();
        termRef.current = null;
      }
    };
  }, []);

  return (
    <div style={{ width: '100%', height: '100%', background: '#0d1117' }}>
      {/* A div mantém opacity 0 até estar pronta para evitar erro de layout no xterm */}
      <div 
        ref={terminalRef} 
        style={{ 
          width: '100%', 
          height: '100%', 
          opacity: isReady ? 1 : 0,
          transition: 'opacity 0.3s'
        }} 
      />
    </div>
  );
}
