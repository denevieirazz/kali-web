import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { WebSocketServer } from 'ws';
import { createApp } from './app.js';
import { getDb } from './database/index.js';
import { setupTerminalWebSocket } from './terminal/websocket.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const runtimeDir = path.resolve(__dirname, '../../runtime');
const runtimeFile = path.join(runtimeDir, 'backend-port.json');

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
      return port;
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
      if (oldData.pid) {
        try {
          process.kill(oldData.pid, 0);
          console.log(`Processo backend anterior (PID ${oldData.pid}) ainda ativo. Abortando duplicação.`);
          process.exit(1);
        } catch (e) {
          // PID morto, limpar
          fs.unlinkSync(runtimeFile);
        }
      }
    } catch (e) {
      try { fs.unlinkSync(runtimeFile); } catch (_) {}
    }
  }

  // Inicializa banco de dados
  getDb();

  // Cria app sem porta (será definida após listen)
  const app = createApp(null);
  const server = http.createServer(app);

  // Bind real em 127.0.0.1 — sem race condition
  // WebSocketServer é criado DEPOIS do listen para não capturar erros de bind
  const port = await listenOnFreePort(server, 18080, 18180, '127.0.0.1');

  // Agora que o server está escutando, anexar WebSocket
  const wss = new WebSocketServer({ server, path: '/ws/terminal' });
  setupTerminalWebSocket(wss);

  // Atualiza a porta real no app
  app._cloudosPort = port;

  console.log(`🚀 CloudOS-Unified Backend rodando em http://127.0.0.1:${port}`);

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
    pid: process.pid
  };

  const tempFile = runtimeFile + '.tmp';
  fs.writeFileSync(tempFile, JSON.stringify(runtimeData, null, 2), 'utf-8');
  fs.renameSync(tempFile, runtimeFile);

  // Encerramento limpo
  function handleShutdown(signal) {
    console.log(`\nRecebido ${signal}. Encerrando backend...`);
    if (fs.existsSync(runtimeFile)) {
      try { fs.unlinkSync(runtimeFile); } catch (e) {}
    }
    server.close(() => {
      const db = getDb();
      if (db) {
        db.close(() => process.exit(0));
      } else {
        process.exit(0);
      }
    });
  }

  process.on('SIGINT', () => handleShutdown('SIGINT'));
  process.on('SIGTERM', () => handleShutdown('SIGTERM'));
}

startServer().catch((err) => {
  console.error('Falha crítica ao iniciar servidor:', err.message);
  process.exit(1);
});
