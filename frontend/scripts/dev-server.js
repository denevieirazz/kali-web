import { createServer } from 'vite';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const runtimeDir = path.resolve(__dirname, '../../runtime');
const runtimeFile = path.join(runtimeDir, 'frontend-port.json');

async function startDevServer() {
  if (!fs.existsSync(runtimeDir)) {
    fs.mkdirSync(runtimeDir, { recursive: true });
  }

  // Obter porta do backend
  let backendPort = 18080;
  try {
    const bPortFile = path.join(runtimeDir, 'backend-port.json');
    if (fs.existsSync(bPortFile)) {
      const bData = JSON.parse(fs.readFileSync(bPortFile, 'utf-8'));
      if (bData.backendPort) backendPort = bData.backendPort;
    }
  } catch (e) {}

  const server = await createServer({
    configFile: path.resolve(rootDir, 'vite.config.ts'),
    root: rootDir,
    server: {
      port: 15173,
      host: '127.0.0.1',
      strictPort: false
    }
  });

  await server.listen();

  const addr = server.httpServer?.address();
  const actualPort = (addr && typeof addr === 'object') ? addr.port : 15173;

  console.log(`🚀 CloudOS Frontend Dev Server rodando em http://127.0.0.1:${actualPort}`);

  const runtimeData = {
    host: '127.0.0.1',
    port: actualPort,
    url: `http://127.0.0.1:${actualPort}`,
    startedAt: new Date().toISOString(),
    pid: process.pid
  };

  const tempFile = runtimeFile + '.tmp';
  fs.writeFileSync(tempFile, JSON.stringify(runtimeData, null, 2), 'utf-8');
  fs.renameSync(tempFile, runtimeFile);

  function handleShutdown() {
    if (fs.existsSync(runtimeFile)) {
      try { fs.unlinkSync(runtimeFile); } catch (_) {}
    }
    server.close().then(() => process.exit(0));
  }

  process.on('SIGINT', handleShutdown);
  process.on('SIGTERM', handleShutdown);
}

startDevServer().catch((err) => {
  console.error('Erro crítico no dev-server do frontend:', err);
  process.exit(1);
});
