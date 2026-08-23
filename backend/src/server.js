import http from 'http';
import crypto from 'node:crypto';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { WebSocketServer } from 'ws';
import { createApp } from './app.js';
import { getDb } from './database/index.js';
import { connectHostLease, readHostLeaseConfig } from './runtime/hostLease.js';
import { setupTerminalWebSocket } from './terminal/websocket.js';
import { handleXpraProxyUpgrade } from './linuxRuntime/xpraProxy.js';
import { restoreSessionsFromLedger, shutdownXpraPocRuntime } from './linuxRuntime/xpraPoc.js';
import { shutdownPhysicalPreflight } from './linuxRuntime/preflight.js';
import { startMotwWatcher } from './files/motwService.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const runtimeDir = path.resolve(process.env.CLOUDOS_RUNTIME_DIR || path.resolve(__dirname, '../../runtime'));
const runtimeFile = path.join(runtimeDir, 'backend-port.json');
const instanceId = crypto.randomUUID();

function removeRuntimeFileIfOwned() {
  if (!fs.existsSync(runtimeFile)) return;
  try {
    const current = JSON.parse(fs.readFileSync(runtimeFile, 'utf8'));
    if (current.instanceId === instanceId) fs.unlinkSync(runtimeFile);
  } catch {}
}

async function probeRuntime(candidate) {
  if (!Number.isInteger(candidate?.pid) || !Number.isInteger(candidate?.backendPort) || typeof candidate?.instanceId !== 'string') return false;
  if (candidate.host !== '127.0.0.1' || candidate.backendPort < 1024 || candidate.backendPort > 65535) return false;
  try {
    process.kill(candidate.pid, 0);
    const response = await fetch(`http://127.0.0.1:${candidate.backendPort}/api/runtime`, {
      signal: AbortSignal.timeout(1500)
    });
    if (!response.ok) return false;
    const live = await response.json();
    return live.instanceId === candidate.instanceId && live.backendPort === candidate.backendPort;
  } catch {
    return false;
  }
}

// Bind approach: try each port by actually binding the HTTP server.
// No find-then-release race condition.
async function listenOnFreePort(server, start, end, host) {
  for (let port = start; port <= end; port++) {
    try {
      await new Promise((resolve, reject) => {
        const onError = (err) => {
          server.removeListener('listening', onListen);
          reject(err);
        };
        const onListen = () => {
          server.removeListener('error', onError);
          resolve();
        };
        server.once('error', onError);
        server.once('listening', onListen);
        server.listen(port, host);
      });
      const address = server.address();
      return address && typeof address === 'object' ? address.port : port;
    } catch (e) {
      if (e.code !== 'EADDRINUSE') throw e;
      // Port in use, try next
    }
  }
  throw new Error(`Nenhuma porta livre entre ${start}-${end} em ${host}`);
}

async function startServer() {
  // Limpeza de arquivo de runtime obsoleto
  if (fs.existsSync(runtimeFile)) {
    try {
      const oldData = JSON.parse(fs.readFileSync(runtimeFile, 'utf-8'));
      if (await probeRuntime(oldData)) {
        console.log(`Backend CloudOS anterior (PID ${oldData.pid}) ainda está ativo e autenticado pelo runtime. Abortando duplicação.`);
        process.exit(1);
      }
      fs.unlinkSync(runtimeFile);
    } catch (e) {
      try { fs.unlinkSync(runtimeFile); } catch (_) {}
    }
  }

  // Inicializa banco de dados
  getDb();

  let server = null;
  let wss = null;
  let hostLease = null;
  let leaseLost = false;
  let shutdownReady = false;
  let shuttingDown = false;

  const leaseConfig = readHostLeaseConfig();
  if (leaseConfig) {
    hostLease = await connectHostLease(leaseConfig, {
      onLost: () => {
        leaseLost = true;
        if (shutdownReady) handleShutdown('HOST_LEASE_CLOSED');
      }
    });
  }

  // Cria app sem porta (será definida após listen)
  const app = createApp(null);
  app._cloudosInstanceId = instanceId;
  server = http.createServer(app);

  // Bind real em 127.0.0.1 — sem race condition
  const configuredPort = Number.parseInt(process.env.PORT || '', 10);
  const useEphemeralPort = process.env.CLOUDOS_NATIVE_HOST === '1' || configuredPort === 0;
  const port = useEphemeralPort
    ? await listenOnFreePort(server, 0, 0, '127.0.0.1')
    : await listenOnFreePort(server, Number.isInteger(configuredPort) ? configuredPort : 18080, Number.isInteger(configuredPort) ? configuredPort : 18180, '127.0.0.1');

  // Dispatcher único de upgrades: evita que o WebSocket do terminal rejeite o tunnel Xpra.
  wss = new WebSocketServer({ noServer: true });
  setupTerminalWebSocket(wss);
  server.on('upgrade', (request, socket, head) => {
    let pathname = '';
    try { pathname = new URL(request.url || '/', 'http://127.0.0.1').pathname; } catch {}
    if (pathname === '/ws/terminal') {
      wss.handleUpgrade(request, socket, head, client => wss.emit('connection', client, request));
      return;
    }
    if (handleXpraProxyUpgrade(request, socket, head)) return;
    socket.destroy();
  });

  // Atualiza a porta real no app
  app._cloudosPort = port;

  console.log(`🚀 CloudOS-Unified Backend rodando em http://127.0.0.1:${port}`);

  // Re-hidrata sessões ativas do Linux Runtime
  restoreSessionsFromLedger().catch(() => undefined);

  // Inicia o watcher de Mark of the Web (Zone.Identifier) para arquivos baixados
  startMotwWatcher();

  // Gravação atômica do arquivo de runtime — APÓS listen efetivo
  if (!fs.existsSync(runtimeDir)) {
    fs.mkdirSync(runtimeDir, { recursive: true });
  }

  const runtimeData = {
    host: '127.0.0.1',
    backendPort: port,
    apiBase: `http://127.0.0.1:${port}`,
    webSocketBase: `ws://127.0.0.1:${port}`,
    startedAt: new Date().toISOString(),
    pid: process.pid,
    instanceId,
    runId: process.env.CLOUDOS_RUN_ID || null,
    executablePath: process.execPath,
    parentPid: Number.parseInt(process.env.CLOUDOS_PARENT_PID || '', 10) || null,
    nativeHost: process.env.CLOUDOS_NATIVE_HOST === '1',
    leaseProtocol: hostLease?.protocol || null
  };

  const tempFile = runtimeFile + '.tmp';
  fs.writeFileSync(tempFile, JSON.stringify(runtimeData, null, 2), 'utf-8');
  fs.renameSync(tempFile, runtimeFile);

  // Encerramento limpo
  function handleShutdown(signal) {
    if (shuttingDown) return;
    shuttingDown = true;
    console.log(`\nRecebido ${signal}. Encerrando backend...`);
    removeRuntimeFileIfOwned();

    const forcedExit = setTimeout(() => {
      hostLease?.close();
      process.exit(0);
    }, 8000);

    for (const client of wss?.clients || []) client.terminate();
    wss?.close();
    const finish = async () => {
      await shutdownPhysicalPreflight();
      await shutdownXpraPocRuntime();
      const db = getDb();
      if (db) {
        db.close(() => {
          clearTimeout(forcedExit);
          hostLease?.close();
          process.exit(0);
        });
      } else {
        clearTimeout(forcedExit);
        hostLease?.close();
        process.exit(0);
      }
    };

    if (server?.listening) server.close(() => { void finish(); });
    else void finish();
  }

  process.on('SIGINT', () => handleShutdown('SIGINT'));
  process.on('SIGTERM', () => handleShutdown('SIGTERM'));
  app.on('cloudos:shutdown', () => handleShutdown('SUPERVISOR'));
  process.on('message', (message) => {
    if (message === 'shutdown') handleShutdown('IPC');
  });
  shutdownReady = true;
  if (leaseLost) handleShutdown('HOST_LEASE_CLOSED');
}

startServer().catch((err) => {
  console.error('Falha crítica ao iniciar servidor:', err.message);
  process.exit(1);
});