import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from './config/index.js';
import { authRouter } from './auth/routes.js';
import { systemRouter } from './system/routes.js';
import { operationsRouter } from './operations/routes.js';
import { userRouter } from './user/routes.js';
import { wslRouter } from './wsl/routes.js';
import { setupRouter } from './setup/routes.js';
import { hostRouter } from './host/routes.js';
import { appsRouter } from './apps/routes.js';
import { readinessRouter } from './readiness/routes.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const defaultFrontendDist = path.resolve(__dirname, '../../frontend/dist');

function normalizeOrigin(origin) {
  try {
    const parsed = new URL(origin);
    if (!['http:', 'https:'].includes(parsed.protocol)) return null;
    return parsed.origin;
  } catch {
    return null;
  }
}

function hasSupervisorAccess(req) {
  const expected = process.env.CLOUDOS_SUPERVISOR_TOKEN;
  const provided = req.get('X-CloudOS-Supervisor-Token');
  if (!expected || !provided) return false;
  const expectedBytes = Buffer.from(expected);
  const providedBytes = Buffer.from(provided);
  return expectedBytes.length === providedBytes.length && crypto.timingSafeEqual(expectedBytes, providedBytes);
}

function hasTraversalPath(requestUrl) {
  let candidate = String(requestUrl || '').split(/[?#]/, 1)[0];
  try {
    candidate = decodeURIComponent(candidate);
    candidate = decodeURIComponent(candidate);
  } catch {
    return true;
  }
  return candidate.includes('\0') || candidate.split(/[\\/]/).includes('..');
}

export function createApp(initialPort) {
  const app = express();

  app._cloudosPort = initialPort;

  app.use((req, res, next) => {
    if (hasTraversalPath(req.originalUrl)) {
      return res.status(400).json({ error: 'Caminho inválido.' });
    }
    next();
  });

  app.use(helmet({
    contentSecurityPolicy: false
  }));

  app.use(cors({
    origin: (origin, callback) => {
      const normalized = origin ? normalizeOrigin(origin) : null;
      const ownOrigin = app._cloudosPort ? `http://127.0.0.1:${app._cloudosPort}` : null;
      const allowedOrigins = new Set([
        ...config.corsOrigins.map(normalizeOrigin).filter(Boolean),
        normalizeOrigin(config.nativeShellOrigin),
        ownOrigin
      ].filter(Boolean));
      if (!origin || allowedOrigins.has(normalized)) {
        callback(null, true);
      } else {
        const error = new Error('Bloqueado pela política CORS');
        error.status = 403;
        callback(error);
      }
    },
    credentials: true
  }));

  app.use(express.json({ limit: '5mb' }));

  app.get('/_cloudos/supervisor/health', (req, res) => {
    if (!hasSupervisorAccess(req)) return res.sendStatus(404);
    const port = app._cloudosPort || 0;
    res.json({
      protocol: 1,
      status: 'ready',
      component: 'backend',
      runId: process.env.CLOUDOS_RUN_ID || null,
      instanceId: app._cloudosInstanceId || null,
      pid: process.pid,
      host: '127.0.0.1',
      port,
      leaseProtocol: process.env.CLOUDOS_HOST_LEASE_PIPE ? 1 : 0
    });
  });

  app.post('/_cloudos/supervisor/shutdown', (req, res) => {
    if (!hasSupervisorAccess(req)) return res.sendStatus(404);
    res.status(202).json({ status: 'stopping' });
    setImmediate(() => app.emit('cloudos:shutdown'));
  });

  // Rejeitar payloads excessivos
  app.use((err, req, res, next) => {
    if (err.type === 'entity.too.large') {
      return res.status(413).json({ error: 'Payload excede o limite de 5MB.' });
    }
    next(err);
  });

  // Endpoint de Runtime Dinamico
  app.get('/api/runtime', (req, res) => {
    const port = app._cloudosPort || 18080;
    res.json({
      host: '127.0.0.1',
      backendPort: port,
      apiBase: `http://127.0.0.1:${port}`,
      webSocketBase: `ws://127.0.0.1:${port}`,
      instanceId: app._cloudosInstanceId || null,
      nativeHost: process.env.CLOUDOS_NATIVE_HOST === '1'
    });
  });

  // Rotas da API
  app.use('/api/auth', authRouter);
  app.use('/api/user', userRouter);
  app.use('/api/system', systemRouter);
  app.use('/api/operations', operationsRouter);
  app.use('/api/wsl', wslRouter);
  app.use('/api/setup', setupRouter);
  app.use('/api/host', hostRouter);
  app.use('/api/apps', appsRouter);
  app.use('/api/readiness', readinessRouter);

  app.get('/api/health', (req, res) => {
    res.json({
      status: 'ok',
      service: 'CloudOS-Unified Backend',
      instanceId: app._cloudosInstanceId || null,
      timestamp: new Date().toISOString()
    });
  });

  app.use('/api', (_req, res) => {
    res.status(404).json({ error: 'Endpoint não encontrado.' });
  });

  const frontendDist = path.resolve(process.env.CLOUDOS_FRONTEND_DIST || defaultFrontendDist);
  const frontendIndex = path.join(frontendDist, 'index.html');
  if (fs.existsSync(frontendIndex)) {
    app.use(express.static(frontendDist, { index: 'index.html', fallthrough: true }));
    app.get('/', (_req, res) => res.sendFile(frontendIndex));
    app.use((_req, res) => res.status(404).json({ error: 'Recurso não encontrado.' }));
  } else {
    app.get('/', (_req, res) => {
      res.status(503).type('text/plain').send('Frontend CloudOS não compilado. Execute npm run build.');
    });
  }

  // Tratamento de erros centralizado
  app.use((err, req, res, next) => {
    const status = Number.isInteger(err.status) ? err.status : 500;
    if (status >= 500) console.error('Erro não tratado na API:', err.message);
    res.status(status).json({ error: status === 403 ? 'Origem não permitida.' : 'Erro interno no servidor.' });
  });

  return app;
}
