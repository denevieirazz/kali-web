import React, { useEffect, useRef, useState } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';

export default function TerminalPane({ wsUrl, isActive }) {
  const terminalRef = useRef(null);
  const wsRef = useRef(null);
  const termRef = useRef(null);
  const [status, setStatus] = useState('Iniciando...');

  useEffect(() => {
    let isDisposed = false;
    let attempts = 0;

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

    // Função inteligente que espera a DIV ficar pronta sem display:none
    const tryOpenTerminal = () => {
      if (isDisposed || !terminalRef.current) return;

      const el = terminalRef.current;
      
      // Se a div tem tamanho visível, abre o terminal
      if (el.offsetWidth > 0 && el.offsetHeight > 0) {
        try {
          term.open(el);
          fitAddon.fit();
          term.focus();
          setStatus('ready');
          connectWebSocket();
        } catch (e) {
          console.error('Erro ao abrir xterm:', e);
          setStatus('Erro ao renderizar terminal.');
        }
      } else {
        // Se não tem tamanho, tenta novamente em 50ms (até 20 vezes)
        attempts++;
        if (attempts < 20) {
          setTimeout(tryOpenTerminal, 50);
        } else {
          console.error('Falha ao encontrar dimensões da tela após 20 tentativas.');
        }
      }
    };

    const connectWebSocket = () => {
      // Pega token limpo (o autoFix já garantiu que não é 'default')
      const token = localStorage.getItem('cloudos_token') || '';
      const safeWsUrl = wsUrl ? wsUrl.replace('token=default', `token=${token}`) : (token ? `ws://localhost:8080?token=${token}` : `ws://localhost:8080`);

      const ws = new WebSocket(safeWsUrl);
      wsRef.current = ws;

      ws.onopen = () => {
        term.writeln('\x1b[32m[CloudOS]\x1b[0m Conexão estabelecida com Kali WSL.');
        term.writeln('');
      };
      
      ws.onmessage = (e) => term.write(e.data);
      
      ws.onerror = () => {
        term.writeln('\x1b[31m[CloudOS] Erro: Backend offline ou conexão recusada.\x1b[0m');
      };
      
      ws.onclose = () => {
        term.writeln('\x1b[33m[CloudOS] Conexão fechada.\x1b[0m');
      };

      term.onData((data) => {
        if (ws.readyState === WebSocket.OPEN) ws.send(data);
      });
    };

    // Inicia a tentativa de abertura
    tryOpenTerminal();

    return () => {
      isDisposed = true;
      if (wsRef.current) wsRef.current.close();
      if (termRef.current) termRef.current.dispose();
    };
  }, [wsUrl]);

  return (
    <div style={{ width: '100%', height: '100%', background: '#0d1117', position: 'relative' }}>
      {/* A div NUNCA usa display:none, garantindo que o xterm consiga medir ela */}
      <div 
        ref={terminalRef} 
        style={{ 
          width: '100%', 
          height: '100%', 
          opacity: status === 'ready' ? 1 : 0, 
          transition: 'opacity 0.3s' 
        }} 
      />
      {status !== 'ready' && (
        <div style={{
          position: 'absolute',
          top: 0, left: 0, right: 0, bottom: 0,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#8b949e', fontFamily: 'monospace', fontSize: '12px'
        }}>
          {status}
        </div>
      )}
    </div>
  );
}
