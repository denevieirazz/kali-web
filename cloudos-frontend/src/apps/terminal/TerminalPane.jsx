import React, { useEffect, useRef, useCallback } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';

const TerminalPane = ({ wsUrl, isActive, theme }) => {
  const termContainerRef = useRef(null);
  const terminalRef = useRef(null);
  const fitAddonRef = useRef(new FitAddon());
  const inputBufferRef = useRef('');
  const historyRef = useRef([]);
  const historyIndexRef = useRef(-1);

  const promptStr = '\x1b[32mkali@cloudos\x1b[0m:\x1b[34m~\x1b[0m$ ';

  const fitTerminal = useCallback(() => {
    try {
      if (fitAddonRef.current && termContainerRef.current) {
        fitAddonRef.current.fit();
      }
    } catch (e) {}
  }, []);

  const initTerminal = useCallback(() => {
    if (terminalRef.current || !termContainerRef.current) return;

    const term = new Terminal({
      theme: theme?.xterm || {
        background: '#0d1117',
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
        white: '#b1bac4'
      },
      fontFamily: '"CaskaydiaCove Nerd Font", "JetBrains Mono", "Cascadia Code", monospace',
      fontSize: 14,
      lineHeight: 1.2,
      cursorBlink: true,
      cursorStyle: 'bar',
      scrollback: 10000,
      convertEol: true,
      allowTransparency: true,
    });

    term.loadAddon(fitAddonRef.current);
    term.open(termContainerRef.current);

    // Escreve banner e prompt imediatamente
    term.write('\x1b[32m[+] CloudOS Kali Linux Terminal Engine v3.0\x1b[0m\r\n');
    term.write('\x1b[90mConectado ao subsistema WSL2 Kali Linux (Digite "help", "clear" ou qualquer comando).\x1b[0m\r\n\r\n');
    term.write(promptStr);

    // Ajusta o tamanho da tela repetidamente para acompanhar animações de abertura de janela
    [30, 100, 250, 500, 1000].forEach((delay) => {
      setTimeout(() => {
        fitTerminal();
        try { term.focus(); } catch (e) {}
      }, delay);
    });

    // Executor HTTP Direct Engine
    const executeCommandHTTP = async (cmd) => {
      const trimmed = cmd.trim();
      term.write('\r\n');

      if (!trimmed) {
        term.write(promptStr);
        return;
      }

      historyRef.current.push(trimmed);
      historyIndexRef.current = historyRef.current.length;

      if (trimmed === 'clear') {
        term.clear();
        term.write(promptStr);
        return;
      }

      if (trimmed === 'help') {
        term.write('\x1b[36mComandos Rápidos do Terminal CloudOS:\x1b[0m\r\n');
        term.write('  - Execute qualquer comando Kali/Linux (ex: uname -a, ls, whoami, ip a, nmap, python3)\r\n');
        term.write('  - clear    : Limpa a tela\r\n');
        term.write('  - history  : Exibe o histórico de comandos\r\n\r\n');
        term.write(promptStr);
        return;
      }

      if (trimmed === 'history') {
        historyRef.current.forEach((h, idx) => {
          term.write(` ${idx + 1}  ${h}\r\n`);
        });
        term.write(promptStr);
        return;
      }

      try {
        const res = await fetch('/api/terminal/exec', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ command: trimmed })
        });

        if (res.ok) {
          const data = await res.json();
          const rawOutput = data.output || '';
          const formatted = rawOutput.replace(/\r?\n/g, '\r\n');
          term.write(formatted);
          if (formatted && !formatted.endsWith('\r\n')) {
            term.write('\r\n');
          }
        } else {
          term.write('\x1b[31m[Erro 500] Falha no servidor backend ao executar o comando.\x1b[0m\r\n');
        }
      } catch (err) {
        term.write(`\x1b[31m[Erro de Conexão] ${err.message}\x1b[0m\r\n`);
      }

      term.write(promptStr);
    };

    term.onData((data) => {
      // Enter
      if (data === '\r') {
        const cmd = inputBufferRef.current;
        inputBufferRef.current = '';
        executeCommandHTTP(cmd);
        return;
      }

      // Backspace (\u007F ou \b)
      if (data === '\u007F' || data === '\b') {
        if (inputBufferRef.current.length > 0) {
          inputBufferRef.current = inputBufferRef.current.slice(0, -1);
          term.write('\b \b');
        }
        return;
      }

      // Ctrl+C (\u0003)
      if (data === '\u0003') {
        inputBufferRef.current = '';
        term.write('^C\r\n' + promptStr);
        return;
      }

      // Ctrl+L (\u000C)
      if (data === '\u000C') {
        term.clear();
        term.write(promptStr + inputBufferRef.current);
        return;
      }

      // Setas Cima / Baixo
      if (data === '\x1b[A') {
        if (historyRef.current.length > 0 && historyIndexRef.current > 0) {
          historyIndexRef.current--;
          const prevCmd = historyRef.current[historyIndexRef.current] || '';
          while (inputBufferRef.current.length > 0) {
            term.write('\b \b');
            inputBufferRef.current = inputBufferRef.current.slice(0, -1);
          }
          inputBufferRef.current = prevCmd;
          term.write(prevCmd);
        }
        return;
      }

      if (data === '\x1b[B') {
        if (historyRef.current.length > 0 && historyIndexRef.current < historyRef.current.length - 1) {
          historyIndexRef.current++;
          const nextCmd = historyRef.current[historyIndexRef.current] || '';
          while (inputBufferRef.current.length > 0) {
            term.write('\b \b');
            inputBufferRef.current = inputBufferRef.current.slice(0, -1);
          }
          inputBufferRef.current = nextCmd;
          term.write(nextCmd);
        } else if (historyIndexRef.current >= historyRef.current.length - 1) {
          historyIndexRef.current = historyRef.current.length;
          while (inputBufferRef.current.length > 0) {
            term.write('\b \b');
            inputBufferRef.current = inputBufferRef.current.slice(0, -1);
          }
        }
        return;
      }

      if (data >= ' ' || data === '\t') {
        inputBufferRef.current += data;
        term.write(data);
      }
    });

    terminalRef.current = term;

    const observer = new ResizeObserver(() => {
      fitTerminal();
    });
    observer.observe(termContainerRef.current);

    return () => {
      observer.disconnect();
      term.dispose();
      terminalRef.current = null;
    };
  }, [theme, fitTerminal]);

  useEffect(() => {
    const cleanup = initTerminal();
    return () => { cleanup && cleanup(); };
  }, [initTerminal]);

  useEffect(() => {
    if (isActive && terminalRef.current) {
      setTimeout(() => {
        fitTerminal();
        try { terminalRef.current.focus(); } catch (e) {}
      }, 50);
    }
  }, [isActive, fitTerminal]);

  return (
    <div
      ref={termContainerRef}
      onClick={() => {
        fitTerminal();
        try { terminalRef.current?.focus(); } catch (e) {}
      }}
      style={{
        width: '100%',
        height: '100%',
        minHeight: '280px',
        flex: 1,
        background: theme?.xterm?.background || '#0d1117',
        padding: '8px',
        boxSizing: 'border-box',
        overflow: 'hidden',
        display: 'flex',
        flexDirection: 'column'
      }}
    />
  );
};

export default TerminalPane;
