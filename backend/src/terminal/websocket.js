import { config } from '../config/index.js';
import { getWslSnapshot, normalizeName } from '../wsl/distroService.js';
import { verifySessionToken } from '../middleware/auth.js';
import {
  createWslCoreTerminalSession,
  wslCoreTerminalEnabled,
  wslCoreTerminalFallbackEnabled
} from './wslCoreAdapter.js';
import {
  buildContainedLegacyShellArgs,
  buildWslHostEnvironment,
  WSL_TERMINAL_EXECUTABLE
} from './wslTerminalContainment.js';

let pty = null;
try {
  pty = (await import('node-pty')).default;
} catch (e) {
  console.warn('⚠️  node-pty não disponível — terminal legado usará emulador local.');
}

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
    'LANG', 'LC_ALL', 'TERM'
  ];
  const environment = { CLOUDOS: '1', TERM: 'xterm-256color' };
  for (const key of allowedKeys) {
    if (typeof process.env[key] === 'string') environment[key] = process.env[key];
  }
  return environment;
}

export function isAllowedWebSocketOrigin(origin, req) {
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

function sendJson(ws, value) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(value));
}

export function setupTerminalWebSocket(wss) {
  wss.on('connection', async (ws, req) => {
    const origin = req.headers.origin;
    if (!isAllowedWebSocketOrigin(origin, req)) {
      ws.close(1008, 'Origin não permitida');
      return;
    }

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
    let coreSession = null;
    let backendMode = null;
    let isInitialized = false;
    let isInitializing = false;
    let cleanupStarted = false;

    const cleanup = async () => {
      if (cleanupStarted) return;
      cleanupStarted = true;
      const activeCore = coreSession;
      coreSession = null;
      if (activeCore) {
        try { await activeCore.close(); }
        catch (error) { console.warn(`WSL core terminal cleanup falhou: ${error?.code || error?.name || 'Error'}`); }
      }
      if (ptyProcess) {
        try { ptyProcess.kill(); }
        catch (error) { console.warn(`PTY cleanup falhou: ${error?.name || 'Error'}`); }
        ptyProcess = null;
      }
    };

    ws.on('message', async (messageRaw) => {
      try {
        const msg = JSON.parse(messageRaw.toString());

        if (msg.type === 'start') {
          if (isInitialized || isInitializing) {
            sendJson(ws, { type: 'error', data: 'Sessão PTY já inicializada ou em preparação.' });
            return;
          }
          isInitializing = true;

          if (msg.executable || msg.args || msg.cwd || msg.env || msg.command) {
            sendJson(ws, { type: 'error', data: 'Parâmetros de execução arbitrários são rejeitados.' });
            ws.close(1008, 'Tentativa de injeção de executável/argumentos');
            isInitializing = false;
            return;
          }

          const requestedProfile = (msg.profile || 'wsl').toLowerCase();
          const cols = Math.max(20, Math.min(300, parseInt(msg.cols || 120, 10)));
          const rows = Math.max(5, Math.min(120, parseInt(msg.rows || 32, 10)));
          let snapshot = null;
          let targetDistro = null;

          if (requestedProfile === 'wsl') {
            const requestedDistro = normalizeName(msg.distribution);
            snapshot = await getWslSnapshot();
            const requested = snapshot.distributions.find((distro) => distro.name.toLowerCase() === requestedDistro.toLowerCase());
            const preferred = snapshot.distributions.find((distro) => distro.name === snapshot.preferred);
            targetDistro = requested?.name || preferred?.name || snapshot.distributions[0]?.name || null;
          }

          if (requestedProfile === 'wsl' && wslCoreTerminalEnabled(process.env)) {
            if (!snapshot?.operational || !targetDistro) {
              if (!wslCoreTerminalFallbackEnabled(process.env)) {
                sendJson(ws, { type: 'error', data: 'WSL Core indisponível: nenhuma distribuição WSL operacional.' });
                ws.close(1011, 'WSL Core indisponível');
                isInitializing = false;
                return;
              }
            } else {
              try {
                coreSession = await createWslCoreTerminalSession({
                  distribution: targetDistro,
                  linuxCorePath: process.env.CLOUDOS_WSL_CORE_LINUX_PATH,
                  cols,
                  rows,
                  onOutput: (data) => sendJson(ws, { type: 'output', data }),
                  onExit: ({ exitCode, signal }) => {
                    sendJson(ws, { type: 'exit', exitCode, signal });
                    if (ws.readyState === ws.OPEN) ws.close();
                  }
                });
                backendMode = 'wsl-core-v2';
                isInitialized = true;
                isInitializing = false;
                sendJson(ws, { type: 'backend', mode: backendMode, protocol: coreSession.protocol, protection: coreSession.protection });
                return;
              } catch (error) {
                coreSession = null;
                if (!wslCoreTerminalFallbackEnabled(process.env)) {
                  sendJson(ws, { type: 'error', data: `WSL Core falhou (${error?.code || 'CORE_START_FAILED'}).` });
                  ws.close(1011, 'WSL Core falhou');
                  isInitializing = false;
                  return;
                }
                sendJson(ws, { type: 'warning', data: `WSL Core indisponível (${error?.code || 'CORE_START_FAILED'}); usando fallback legado explícito.` });
              }
            }
          }

          if (!pty) {
            backendMode = 'emulator';
            isInitialized = true;
            isInitializing = false;
            sendJson(ws, { type: 'backend', mode: backendMode });
            sendJson(ws, { type: 'output', data: 'CloudOS Terminal Emulador (node-pty indisponível)\r\n$ ' });
            return;
          }

          let spawnExe = POWERSHELL_EXE;
          let spawnArgs = ['-NoLogo'];
          if (requestedProfile === 'wsl' && snapshot?.operational && targetDistro) {
            spawnExe = WSL_TERMINAL_EXECUTABLE;
            spawnArgs = buildContainedLegacyShellArgs(targetDistro);
          }

          try {
            ptyProcess = pty.spawn(spawnExe, spawnArgs, {
              name: 'xterm-256color',
              cols,
              rows,
              cwd: process.env.USERPROFILE || 'C:\\',
              env: spawnExe === WSL_TERMINAL_EXECUTABLE
                ? buildWslHostEnvironment(process.env)
                : buildTerminalEnvironment()
            });
            backendMode = 'legacy-pty';
            isInitialized = true;
          } catch (err) {
            sendJson(ws, { type: 'error', data: 'Falha ao iniciar PTY legado.' });
            ws.close(1011, 'Falha ao iniciar PTY');
            isInitializing = false;
            return;
          }
          isInitializing = false;
          sendJson(ws, { type: 'backend', mode: backendMode });

          ptyProcess.onData((data) => sendJson(ws, { type: 'output', data }));
          ptyProcess.onExit(({ exitCode, signal }) => {
            sendJson(ws, { type: 'exit', exitCode, signal });
            if (ws.readyState === ws.OPEN) ws.close();
          });
          return;
        }

        if (!isInitialized) {
          sendJson(ws, { type: 'error', data: 'Envie a mensagem { type: "start" } antes de enviar comandos.' });
          return;
        }

        if (msg.type === 'input') {
          if (typeof msg.data !== 'string') return;
          if (backendMode === 'wsl-core-v2' && coreSession) await coreSession.input(msg.data);
          else if (backendMode === 'legacy-pty' && ptyProcess) ptyProcess.write(msg.data);
          else if (backendMode === 'emulator') {
            if (msg.data === '\r') sendJson(ws, { type: 'output', data: '\r\n$ ' });
            else sendJson(ws, { type: 'output', data: msg.data });
          }
        } else if (msg.type === 'resize') {
          const cols = Math.max(20, Math.min(300, parseInt(msg.cols || 80, 10)));
          const rows = Math.max(5, Math.min(120, parseInt(msg.rows || 24, 10)));
          if (backendMode === 'wsl-core-v2' && coreSession) await coreSession.resize(cols, rows);
          else if (backendMode === 'legacy-pty' && ptyProcess) ptyProcess.resize(cols, rows);
        } else if (msg.type === 'signal') {
          const signal = String(msg.signal || '').toLowerCase();
          if (!['interrupt', 'terminate', 'hangup'].includes(signal)) {
            sendJson(ws, { type: 'error', data: 'Sinal de terminal inválido.' });
            return;
          }
          if (backendMode === 'wsl-core-v2' && coreSession) await coreSession.signal(signal);
          else if (backendMode === 'legacy-pty' && ptyProcess) ptyProcess.kill();
        } else if (msg.type === 'close') {
          await cleanup();
          ws.close();
        } else if (msg.type === 'ping') {
          sendJson(ws, { type: 'pong' });
        }
      } catch (err) {
        isInitializing = false;
        sendJson(ws, { type: 'error', data: `Mensagem inválida ou sessão indisponível (${err?.code || 'TERMINAL_ERROR'}).` });
      }
    });

    ws.on('close', () => { void cleanup(); });
    ws.on('error', () => { void cleanup(); });
  });
}
