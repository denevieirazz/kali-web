const nodePty = require('node-pty');
const path = require('path');

class TerminalSessionManager {
  constructor() {
    this.sessions = new Map(); // sessionId -> { pty, userId, cwd }
  }

  createSession(userId, options = {}) {
    const sessionId = `sess_${userId}_${Date.now()}_${Math.random().toString(36).substr(2, 4)}`;
    const cwd = options.cwd || process.env.HOME || 'C:\\Users\\dougl';
    
    // Configura shell seguro no Windows / WSL
    const shell = 'wsl.exe';
    const args = ['-d', 'kali-linux', '-u', 'cloudos', '--', 'bash', '-l'];

    try {
      const ptyProcess = nodePty.spawn(shell, args, {
        name: 'xterm-256color',
        cols: 80,
        rows: 30,
        cwd,
        env: process.env
      });

      this.sessions.set(sessionId, { pty: ptyProcess, userId, cwd });

      ptyProcess.onExit(() => {
        this.sessions.delete(sessionId);
      });

      return sessionId;
    } catch (err) {
      console.error("Erro ao criar PTY no WSL:", err);
      // Fallback para cmd caso o WSL não esteja pronto
      const ptyProcess = nodePty.spawn('cmd.exe', [], {
        name: 'xterm-256color',
        cols: 80,
        rows: 30,
        cwd,
        env: process.env
      });
      this.sessions.set(sessionId, { pty: ptyProcess, userId, cwd });
      return sessionId;
    }
  }

  write(sessionId, data, userId) {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    session.pty.write(data);
  }

  resize(sessionId, { cols, rows }, userId) {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    session.pty.resize(Math.max(cols, 1), Math.max(rows, 1));
  }

  kill(sessionId, userId) {
    const session = this.sessions.get(sessionId);
    if (session) {
      try { session.pty.kill(); } catch (e) {}
      this.sessions.delete(sessionId);
    }
  }

  attach(sessionId, ws, userId) {
    const session = this.sessions.get(sessionId);
    if (!session) {
      ws.send(JSON.stringify({ type: 'error', message: 'Sessão não encontrada' }));
      return;
    }

    const onData = (data) => {
      if (ws.readyState === ws.OPEN) {
        ws.send(JSON.stringify({ type: 'output', sessionId, data }));
      }
    };

    session.pty.onData(onData);

    ws.on('close', () => {
      try { session.pty.removeListener('data', onData); } catch (e) {}
    });
  }
}

module.exports = new TerminalSessionManager();
