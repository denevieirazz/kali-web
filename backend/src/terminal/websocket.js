import { config } from '../config/index.js';
import { getWslSnapshot, normalizeName } from '../wsl/distroService.js';
import { verifySessionToken } from '../middleware/auth.js';

let pty = null;
try {
  pty = (await import('node-pty')).default;
} catch (e) {
  console.warn('⚠️  node-pty não disponível — terminal usará emulador local.');
}

const WSL_EXE = 'C:\\Windows\\System32\\wsl.exe';
const POWERSHELL_EXE = 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';

function buildTerminalEnvironment() {
  const allowedKeys = [
    'ALLUSERSPROFILE', 'APPDATA', 'CommonProgramFiles', 'CommonProgramFiles(x86)',
    'CommonProgramW6432', 'COMPUTERNAME', 'ComSpec', 'HOMEDRIVE', 'HOMEPATH',
    'LOCALAPPDATA', 'NUMBER_OF_PROCESSORS', 'OS', 'Path', 'PATHEXT',
    'PROCESSOR_ARCHITECTURE', 'PROCESSOR_IDENTIFIER', 'PROCESSOR_LEVEL',
    'PROCESSOR_REVISION', 'ProgramData', 'ProgramFiles', 'ProgramFiles(x86)',
    'ProgramW6432', 'PSModulePath', 'PUBLIC', 'SystemDrive', 'SystemRoot',
    'TEMP', 'TMP', 'USERDOMAIN', 'USERNAME', 'USERPROFILE', 'windir',
    'LANG', 'LC_ALL', 'TERM', 'WSLENV'
  ];
  const environment = { CLOUDOS: '1', TERM: 'xterm-256color' };
  for (const key of allowedKeys) {
    if (typeof process.env[key] === 'string') environment[key] = process.env[key];
  }
  return environment;
}

function isAllowedWebSocketOrigin(origin, req) {
  if (!origin) return true;
  if (config.corsOrigins.includes(origin)) return true;
  if (config.nativeShellOrigin && origin === config.nativeShellOrigin) return true;
  try {
    const parsed = new URL(origin);
    const localPort = Number(req.socket?.localPort);
    return parsed.protocol === 'http:'
      && parsed.hostname === '127.0.0.1'
      && Number(parsed.port) === localPort;
  } catch {
    return false;
  }
}

export function setupTerminalWebSocket(wss) {
  wss.on('connection', async (ws, req) => {
    // Validação de Origin
    const origin = req.headers.origin;
    if (!isAllowedWebSocketOrigin(origin, req)) {
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
      await verifySessionToken(protocol);
    } catch (e) {
      ws.close(1008, 'Token inválido ou revogado');
      return;
    }

    let ptyProcess = null;
    let isInitialized = false;
    let isInitializing = false;

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

    ws.on('message', async (messageRaw) => {
      try {
        const msg = JSON.parse(messageRaw.toString());

        // Mensagem 1: "start" — Inicialização controlada
        if (msg.type === 'start') {
          if (isInitialized || isInitializing) {
            ws.send(JSON.stringify({ type: 'error', data: 'Sessão PTY já inicializada ou em preparação.' }));
            return;
          }
          isInitializing = true;

          // Bloqueio estrito de parâmetros inseguros do cliente
          if (msg.executable || msg.args || msg.cwd || msg.env || msg.command) {
            ws.send(JSON.stringify({ type: 'error', data: 'Parâmetros de execução arbitrários são rejeitados.' }));
            ws.close(1008, 'Tentativa de injeção de executável/argumentos');
            isInitializing = false;
            return;
          }

          const requestedProfile = (msg.profile || 'wsl').toLowerCase();
          const cols = Math.max(20, Math.min(300, parseInt(msg.cols || 120, 10)));
          const rows = Math.max(5, Math.min(120, parseInt(msg.rows || 32, 10)));

          let spawnExe = POWERSHELL_EXE;
          let spawnArgs = ['-NoLogo'];

          if (requestedProfile === 'wsl') {
            const requestedDistro = normalizeName(msg.distribution);
            const snapshot = await getWslSnapshot();
            const requested = snapshot.distributions.find((distro) => distro.name.toLowerCase() === requestedDistro.toLowerCase());
            const preferred = snapshot.distributions.find((distro) => distro.name === snapshot.preferred);
            const targetDistro = requested?.name || preferred?.name || snapshot.distributions[0]?.name || null;

            if (snapshot.operational && targetDistro) {
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
              env: buildTerminalEnvironment()
            });
            isInitialized = true;
          } catch (err) {
            ws.send(JSON.stringify({ type: 'error', data: 'Falha ao iniciar PTY: ' + err.message }));
            ws.close(1011, err.message);
            isInitializing = false;
            return;
          }
          isInitializing = false;

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
        isInitializing = false;
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
