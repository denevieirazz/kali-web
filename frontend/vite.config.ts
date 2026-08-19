import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const runtimeDir = path.resolve(process.env.CLOUDOS_RUNTIME_DIR || path.resolve(__dirname, '../runtime'));

export default defineConfig(() => {
  let backendPort = 18080;
  try {
    const bPortFile = path.join(runtimeDir, 'backend-port.json');
    if (fs.existsSync(bPortFile)) {
      const bData = JSON.parse(fs.readFileSync(bPortFile, 'utf-8'));
      if (bData.backendPort) backendPort = bData.backendPort;
    }
  } catch {}
  const configuredFrontendPort = Number.parseInt(process.env.CLOUDOS_FRONTEND_PORT || '15173', 10);
  const frontendPort = Number.isInteger(configuredFrontendPort) && configuredFrontendPort > 0 ? configuredFrontendPort : 15173;
  const backendHttpTarget = `http://127.0.0.1:${backendPort}`;
  return {
    plugins: [
      react(),
      {
        name: 'cloudos-runtime-writer',
        configureServer(server) {
          server.httpServer?.once('listening', () => {
            const addr = server.httpServer?.address();
            if (addr && typeof addr === 'object') {
              if (!fs.existsSync(runtimeDir)) fs.mkdirSync(runtimeDir, { recursive: true });
              const runtimeData = { host: '127.0.0.1', port: addr.port, url: `http://127.0.0.1:${addr.port}`, startedAt: new Date().toISOString(), pid: process.pid };
              const tempFile = path.join(runtimeDir, 'frontend-port.json.tmp');
              const targetFile = path.join(runtimeDir, 'frontend-port.json');
              fs.writeFileSync(tempFile, JSON.stringify(runtimeData, null, 2), 'utf-8');
              fs.renameSync(tempFile, targetFile);
              console.log(`[CloudOS] Frontend runtime registrado: porta ${addr.port}`);
            }
          });
        }
      }
    ],
    define: { __CLOUDOS_BACKEND_PORT__: JSON.stringify(backendPort) },
    server: {
      port: frontendPort,
      host: '127.0.0.1',
      strictPort: process.env.CLOUDOS_FRONTEND_STRICT_PORT === '1',
      proxy: {
        '/api': { target: backendHttpTarget, changeOrigin: false },
        '/ws': { target: `ws://127.0.0.1:${backendPort}`, ws: true, changeOrigin: false },
        // A surface Xpra usa URL relativa para permanecer same-origin com o CloudOS.
        // No dev server, HTTP e Upgrade WebSocket precisam atravessar o mesmo backend capability proxy.
        '/__cloudos': { target: backendHttpTarget, ws: true, changeOrigin: false }
      }
    }
  };
});
