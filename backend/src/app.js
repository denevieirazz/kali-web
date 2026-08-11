import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { config } from './config/index.js';
import { authRouter } from './auth/routes.js';
import { systemRouter } from './system/routes.js';
import { operationsRouter } from './operations/routes.js';
import { userRouter } from './user/routes.js';
import { wslRouter } from './wsl/routes.js';
import { setupRouter } from './setup/routes.js';

export function createApp(initialPort) {
  const app = express();

  app._cloudosPort = initialPort;

  app.use(helmet({
    contentSecurityPolicy: false
  }));

  app.use(cors({
    origin: (origin, callback) => {
      if (!origin || origin.startsWith('http://127.0.0.1:') || origin.startsWith('http://localhost:')) {
        callback(null, true);
      } else {
        callback(new Error('Bloqueado pela política CORS'));
      }
    },
    credentials: true
  }));

  app.use(express.json({ limit: '5mb' }));

  // Rejeitar payloads excessivos
  app.use((err, req, res, next) => {
    if (err.type === 'entity.too.large') {
      return res.status(413).json({ error: 'Payload excede o limite de 5MB.' });
    }
    next(err);
  });

  // Endpoint de Runtime Dinâmico
  app.get('/api/runtime', (req, res) => {
    const port = app._cloudosPort || 18080;
    res.json({
      host: '127.0.0.1',
      backendPort: port,
      apiBase: `http://127.0.0.1:${port}`,
      webSocketBase: `ws://127.0.0.1:${port}`
    });
  });

  // Rotas da API
  app.use('/api/auth', authRouter);
  app.use('/api/user', userRouter);
  app.use('/api/system', systemRouter);
  app.use('/api/operations', operationsRouter);
  app.use('/api/wsl', wslRouter);
  app.use('/api/setup', setupRouter);

  app.get('/api/health', (req, res) => {
    res.json({ status: 'ok', service: 'CloudOS-Unified Backend', timestamp: new Date().toISOString() });
  });

  // Tratamento de erros centralizado
  app.use((err, req, res, next) => {
    console.error('Erro não tratado na API:', err.message);
    res.status(500).json({ error: 'Erro interno no servidor.' });
  });

  return app;
}
