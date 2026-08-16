import { createServer } from 'vite';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const runtimeDir = path.resolve(process.env.CLOUDOS_RUNTIME_DIR || path.resolve(__dirname, '../../runtime'));
const runtimeFile = path.join(runtimeDir, 'frontend-port.json');
const requestedPort = Number.parseInt(process.env.CLOUDOS_FRONTEND_PORT || '15173', 10);

async function startDevServer() {
  if (!fs.existsSync(runtimeDir)) fs.mkdirSync(runtimeDir, { recursive: true });
  const server = await createServer({
    configFile: path.resolve(rootDir, 'vite.config.ts'),
    root: rootDir,
    server: {
      port: Number.isInteger(requestedPort) && requestedPort > 0 ? requestedPort : 15173,
      host: '127.0.0.1',
      strictPort: process.env.CLOUDOS_FRONTEND_STRICT_PORT === '1'
    }
  });
  await server.listen();
  const addr = server.httpServer?.address();
  const actualPort = (addr && typeof addr === 'object') ? addr.port : requestedPort;
  console.log(`🚀 CloudOS Frontend Dev Server rodando em http://127.0.0.1:${actualPort}`);
  const runtimeData = { host: '127.0.0.1', port: actualPort, url: `http://127.0.0.1:${actualPort}`, startedAt: new Date().toISOString(), pid: process.pid };
  const tempFile = `${runtimeFile}.tmp`;
  fs.writeFileSync(tempFile, JSON.stringify(runtimeData, null, 2), 'utf-8');
  fs.renameSync(tempFile, runtimeFile);
  async function handleShutdown() {
    if (fs.existsSync(runtimeFile)) { try { fs.unlinkSync(runtimeFile); } catch {} }
    await server.close(); process.exit(0);
  }
  process.on('SIGINT', () => { void handleShutdown(); });
  process.on('SIGTERM', () => { void handleShutdown(); });
}
startDevServer().catch((err) => { console.error('Erro crítico no dev-server do frontend:', err instanceof Error ? err.message : String(err)); process.exit(1); });
