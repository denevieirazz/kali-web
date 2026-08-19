import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import {
  checkXpraPocReadiness,
  cleanupXpraPoc,
  getAllowedLinuxPocApps,
  getXpraPocSessions,
  healthXpraPocSession,
  recordXpraPocClientMetrics,
  restartXpraPoc,
  startXpraPoc,
  stopXpraPoc,
} from './xpraPoc.js';
import { finalizePhysicalPreflight, startPhysicalPreflight } from './preflight.js';

export const linuxRuntimeRouter = express.Router();
linuxRuntimeRouter.use(authenticateToken);

function statusForCode(code) {
  if (['LINUX_POC_APP_NOT_ALLOWED', 'LINUX_POC_OWNER_INVALID', 'PREFLIGHT_OWNER_INVALID'].includes(code)) return 400;
  if (['LINUX_POC_SESSION_ACTIVE', 'LINUX_POC_SESSION_LIMIT', 'LINUX_POC_ORPHANED_SESSION', 'LINUX_POC_SESSION_OWNER_MISMATCH', 'PREFLIGHT_OWNER_MISMATCH'].includes(code)) return 409;
  if (['LINUX_POC_SESSION_NOT_FOUND', 'PREFLIGHT_RUN_NOT_FOUND'].includes(code)) return 404;
  return 503;
}

function sendError(res, error, fallback) {
  const code = error.code || fallback;
  res.status(statusForCode(code)).json({
    error: error.message,
    errorCode: code,
    details: error.details || null,
  });
}

linuxRuntimeRouter.get('/poc1', (req, res) => {
  try {
    res.json({
      mode: 'xpra-html5-contained',
      transport: 'cloudos-origin-proxy',
      externalWindowsExpected: 0,
      maxAppsPerWindow: 4,
      apps: getAllowedLinuxPocApps(),
      sessions: getXpraPocSessions(req.query?.ownerId || null),
    });
  } catch (error) {
    sendError(res, error, 'LINUX_POC_STATUS_FAILED');
  }
});

linuxRuntimeRouter.get('/poc1/readiness', async (req, res) => {
  try {
    // Readiness bloqueado é diagnóstico válido, não falha de transporte da API.
    res.json(await checkXpraPocReadiness({
      app: req.query?.app || 'xclock',
      distribution: req.query?.distribution || undefined,
    }));
  } catch (error) {
    sendError(res, error, 'LINUX_POC_READINESS_FAILED');
  }
});

// Comando único de preparação física. Não executa xclock.
linuxRuntimeRouter.post('/poc1/preflight', async (req, res) => {
  try {
    const port = Number(req.app?._cloudosPort || 0);
    const backendOrigin = port > 0 ? `http://127.0.0.1:${port}` : null;
    const result = await startPhysicalPreflight({
      ownerId: req.body?.ownerId,
      distribution: req.body?.distribution || undefined,
      backendOrigin,
    });
    res.json(result);
  } catch (error) {
    sendError(res, error, 'POC1_PREFLIGHT_FAILED');
  }
});

// Segunda metade interna do mesmo comando: recebe a prova do iframe e encerra o dry run.
linuxRuntimeRouter.post('/poc1/preflight/:id/finalize', async (req, res) => {
  try {
    const result = await finalizePhysicalPreflight({
      runId: req.params.id,
      ownerId: req.body?.ownerId,
      iframe: req.body?.iframe || {},
    });
    res.json(result);
  } catch (error) {
    sendError(res, error, 'POC1_PREFLIGHT_FINALIZE_FAILED');
  }
});

linuxRuntimeRouter.post('/poc1/start', async (req, res) => {
  try {
    const session = await startXpraPoc({
      app: req.body?.app,
      distribution: req.body?.distribution,
      ownerId: req.body?.ownerId,
    });
    res.status(201).json({ session });
  } catch (error) {
    sendError(res, error, 'LINUX_POC_START_FAILED');
  }
});

linuxRuntimeRouter.get('/poc1/sessions/:id/health', async (req, res) => {
  try {
    // Sessão degradada continua retornando o payload de health completo.
    res.json(await healthXpraPocSession(req.params.id));
  } catch (error) {
    sendError(res, error, 'LINUX_POC_HEALTH_FAILED');
  }
});

linuxRuntimeRouter.post('/poc1/sessions/:id/restart', async (req, res) => {
  try {
    const session = await restartXpraPoc(req.params.id, req.body?.ownerId || null);
    res.json({ session });
  } catch (error) {
    sendError(res, error, 'LINUX_POC_RESTART_FAILED');
  }
});

linuxRuntimeRouter.post('/poc1/sessions/:id/stop', async (req, res) => {
  try {
    const session = await stopXpraPoc(req.params.id, req.body?.ownerId || null);
    res.json({ status: 'stopped', session });
  } catch (error) {
    sendError(res, error, 'LINUX_POC_STOP_FAILED');
  }
});

linuxRuntimeRouter.post('/poc1/sessions/:id/client-metrics', (req, res) => {
  try {
    const session = recordXpraPocClientMetrics(req.params.id, req.body?.ownerId, req.body || {});
    res.json({ session });
  } catch (error) {
    sendError(res, error, 'LINUX_POC_METRICS_FAILED');
  }
});

linuxRuntimeRouter.post('/poc1/cleanup', async (req, res) => {
  try {
    const result = await cleanupXpraPoc({
      ownerId: req.body?.ownerId || null,
      orphansOnly: req.body?.orphansOnly === true,
    });
    res.json(result);
  } catch (error) {
    sendError(res, error, 'LINUX_POC_CLEANUP_FAILED');
  }
});

// Backward-compatible stop endpoint for the first POC revision.
linuxRuntimeRouter.post('/poc1/stop', async (req, res) => {
  try {
    const sessions = await stopXpraPoc(null, req.body?.ownerId || null);
    res.json({ status: 'stopped', sessions });
  } catch (error) {
    sendError(res, error, 'LINUX_POC_STOP_FAILED');
  }
});
