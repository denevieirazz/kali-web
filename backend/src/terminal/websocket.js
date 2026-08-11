import jwt from 'jsonwebtoken';
import { config } from '../config/index.js';
import { getPreferred, validateAllowlisted, isInstalled } from '../wsl/distroService.js';

let pty = null;
try {
  pty = (await import('node-pty')).default;
} catch (e) {
  console.warn('⚠️  node-pty não disponível — terminal usará emulador local.');
}

const WSL_EXE = 'C:\\Windows\\System32\\wsl.exe';
const POWERSHELL_EXE = 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';

export function setupTerminalWebSocket(wss) {
  wss.on('connection', (ws, req) => {
    // Validação de Origin
    const origin = req.headers.origin;
    if (origin && !config.corsOrigins.includes(origin) && !origin.startsWith('http://localhost:') && !origin.startsWith('http://127.0.0.1:')) {
      ws.close(1008, 'Origin não permitida');
      return;
    }

    // Token JWT via cabeçalho Sec-WebSocket-Protocol
    const protocol = req.headers['sec-websocket-protocol'];
    if (!protocol) {
      ws.close(1008, 'Token de autenticação ausente');
      return;
    }

    try {
      jwt.verify(protocol, config.jwtSecret);
    } catch (e) {
      ws.close(1008, 'Token inválido');
      return;
    }

    let ptyProcess = null;
    let isInitialized = false;

    // Se node-pty não está disponível, modo emulador
    if (!pty) {
      ws.send(JSON.stringify({ type: 'output', data: 'CloudOS Terminal Emulador (node-pty indisponível)\r\n$ ' }));
      ws.on('message', (msg) => {
        try {
          const parsed = JSON.parse(msg.toString());
          if (parsed.type === 'input') {
            if (parsed.data === '\r') {
              ws.send(JSON.stringify({ type: 'output', data: '\r\n$ ' }));
            } else {
              ws.send(JSON.stringify({ type: 'output', data: parsed.data }));
            }
          }
        } catch (e) {}
      });
      return;
    }

    ws.on('message', (messageRaw) => {
      try {
        const msg = JSON.parse(messageRaw.toString());

        // Mensagem 1: "start" — Inicialização controlada
        if (msg.type === 'start') {
          if (isInitialized) {
            ws.send(JSON.stringify({ type: 'error', data: 'Sessão PTY já inicializada.' }));
            return;
          }

          // Bloqueio estrito de parâmetros inseguros do cliente
          if (msg.executable || msg.args || msg.cwd || msg.env || msg.command) {
            ws.send(JSON.stringify({ type: 'error', data: 'Parâmetros de execução arbitrários são rejeitados.' }));
            ws.close(1008, 'Tentativa de injeção de executável/argumentos');
            return;
          }

          const requestedProfile = (msg.profile || 'wsl').toLowerCase();
          const cols = Math.max(20, Math.min(300, parseInt(msg.cols || 120, 10)));
          const rows = Math.max(5, Math.min(120, parseInt(msg.rows || 32, 10)));

          let spawnExe = POWERSHELL_EXE;
          let spawnArgs = ['-NoLogo'];

          if (requestedProfile === 'wsl') {
            const requestedDistro = msg.distribution;
            let targetDistro = null;

            if (requestedDistro && validateAllowlisted(requestedDistro)) {
              targetDistro = requestedDistro;
            } else {
              targetDistro = getPreferred();
            }

            if (targetDistro && isInstalled(targetDistro)) {
              spawnExe = WSL_EXE;
              spawnArgs = ['-d', targetDistro, '--', '/bin/bash', '-l'];
            } else {
              // Fallback explícito para PowerShell se não houver WSL
              spawnExe = POWERSHELL_EXE;
              spawnArgs = ['-NoLogo'];
            }
          }

          try {
            ptyProcess = pty.spawn(spawnExe, spawnArgs, {
              name: 'xterm-256color',
              cols,
              rows,
              cwd: process.env.USERPROFILE || 'C:\\',
              env: { ...process.env, CLOUDOS: '1' }
            });
            isInitialized = true;
          } catch (err) {
            ws.send(JSON.stringify({ type: 'error', data: 'Falha ao iniciar PTY: ' + err.message }));
            ws.close(1011, err.message);
            return;
          }

          ptyProcess.onData((data) => {
            if (ws.readyState === ws.OPEN) {
              ws.send(JSON.stringify({ type: 'output', data }));
            }
          });

          ptyProcess.onExit(({ exitCode, signal }) => {
            if (ws.readyState === ws.OPEN) {
              ws.send(JSON.stringify({ type: 'exit', exitCode, signal }));
              ws.close();
            }
          });

          return;
        }

        // Se ainda não foi inicializado, exigir mensagem start
        if (!isInitialized || !ptyProcess) {
          ws.send(JSON.stringify({ type: 'error', data: 'Envie a mensagem { type: "start" } antes de enviar comandos.' }));
          return;
        }

        if (msg.type === 'input') {
          if (typeof msg.data === 'string') {
            ptyProcess.write(msg.data);
          }
        } else if (msg.type === 'resize') {
          const cols = Math.max(20, Math.min(300, parseInt(msg.cols || 80, 10)));
          const rows = Math.max(5, Math.min(120, parseInt(msg.rows || 24, 10)));
          ptyProcess.resize(cols, rows);
        } else if (msg.type === 'close') {
          if (ptyProcess) {
            ptyProcess.kill();
            ptyProcess = null;
          }
          ws.close();
        } else if (msg.type === 'ping') {
          ws.send(JSON.stringify({ type: 'pong' }));
        }

      } catch (err) {
        ws.send(JSON.stringify({ type: 'error', data: 'Mensagem inválida: ' + err.message }));
      }
    });

    ws.on('close', () => {
      if (ptyProcess) {
        try {
          ptyProcess.kill();
        } catch (e) {}
        ptyProcess = null;
      }
    });
  });
}
