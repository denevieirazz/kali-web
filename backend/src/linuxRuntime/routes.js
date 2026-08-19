import crypto from 'node:crypto';
import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { checkXpraPocReadiness, cleanupXpraPoc, getAllowedLinuxPocApps, getXpraPocSessions, healthXpraPocSession, recordXpraPocClientMetrics, restartXpraPoc, startXpraPoc, stopXpraPoc } from './xpraPoc.js';
import { finalizePhysicalPreflight, startPhysicalPreflight } from './preflight.js';

export const linuxRuntimeRouter = express.Router();
linuxRuntimeRouter.use(authenticateToken);

function statusForCode(code) {
  if (['LINUX_POC_APP_NOT_ALLOWED', 'LINUX_POC_OWNER_INVALID', 'PREFLIGHT_OWNER_INVALID'].includes(code)) return 400;
  if (['LINUX_POC_SESSION_ACTIVE', 'LINUX_POC_SESSION_LIMIT', 'LINUX_POC_ORPHANED_SESSION', 'LINUX_POC_SESSION_OWNER_MISMATCH', 'PREFLIGHT_OWNER_MISMATCH'].includes(code)) return 409;
  if (['LINUX_POC_SESSION_NOT_FOUND', 'PREFLIGHT_RUN_NOT_FOUND'].includes(code)) return 404;
  return 503;
}
function sendError(res, error, fallback) { const code = error.code || fallback; res.status(statusForCode(code)).json({ error: error.message, errorCode: code, details: error.details || null }); }
function rawOwner(value) { const owner = String(value || '').trim(); if (!/^[a-zA-Z0-9._:-]{1,128}$/.test(owner)) { const error = new Error('Identificador da CloudOS Window inválido.'); error.code = 'LINUX_POC_OWNER_INVALID'; throw error; } return owner; }
export function scopedOwnerId(userId, ownerId) { return `${crypto.createHash('sha256').update(String(userId)).digest('hex').slice(0, 24)}:${rawOwner(ownerId)}`; }
function ownerFor(req, value) { return scopedOwnerId(req.user?.id || req.user?.userId || req.user?.username || 'anonymous', value); }
function assertOwnedSession(req, id, ownerId) { const owned = getXpraPocSessions(ownerId); if (!owned.some(session => session.id === id)) { const error = new Error('Sessão POC 1 não encontrada para este usuário/window.'); error.code = 'LINUX_POC_SESSION_NOT_FOUND'; throw error; } }

linuxRuntimeRouter.get('/poc1', (req, res) => { try { const owner = ownerFor(req, req.query?.ownerId); res.json({ mode: 'xpra-html5-contained-minimal', transport: 'capability-proxy', externalWindowsExpected: 0, maxAppsPerWindow: 4, apps: getAllowedLinuxPocApps(), sessions: getXpraPocSessions(owner) }); } catch (error) { sendError(res, error, 'LINUX_POC_STATUS_FAILED'); } });
linuxRuntimeRouter.get('/poc1/readiness', async (req, res) => { try { res.json(await checkXpraPocReadiness({ app: req.query?.app || 'xclock', distribution: req.query?.distribution || undefined })); } catch (error) { sendError(res, error, 'LINUX_POC_READINESS_FAILED'); } });
linuxRuntimeRouter.post('/poc1/preflight', async (req, res) => { try { const port = Number(req.app?._cloudosPort || 0); const result = await startPhysicalPreflight({ ownerId: ownerFor(req, req.body?.ownerId), distribution: req.body?.distribution || undefined, backendOrigin: port > 0 ? `http://127.0.0.1:${port}` : null }); res.json(result); } catch (error) { sendError(res, error, 'POC1_PREFLIGHT_FAILED'); } });
linuxRuntimeRouter.post('/poc1/preflight/:id/finalize', async (req, res) => { try { res.json(await finalizePhysicalPreflight({ runId: req.params.id, ownerId: ownerFor(req, req.body?.ownerId), iframe: req.body?.iframe || {} })); } catch (error) { sendError(res, error, 'POC1_PREFLIGHT_FINALIZE_FAILED'); } });
linuxRuntimeRouter.post('/poc1/start', async (req, res) => { try { const session = await startXpraPoc({ app: req.body?.app, distribution: req.body?.distribution, ownerId: ownerFor(req, req.body?.ownerId) }); res.status(201).json({ session }); } catch (error) { sendError(res, error, 'LINUX_POC_START_FAILED'); } });
linuxRuntimeRouter.get('/poc1/sessions/:id/health', async (req, res) => { try { const owner = ownerFor(req, req.query?.ownerId); assertOwnedSession(req, req.params.id, owner); res.json(await healthXpraPocSession(req.params.id)); } catch (error) { sendError(res, error, 'LINUX_POC_HEALTH_FAILED'); } });
linuxRuntimeRouter.post('/poc1/sessions/:id/restart', async (req, res) => { try { const owner = ownerFor(req, req.body?.ownerId); assertOwnedSession(req, req.params.id, owner); res.json({ session: await restartXpraPoc(req.params.id, owner) }); } catch (error) { sendError(res, error, 'LINUX_POC_RESTART_FAILED'); } });
linuxRuntimeRouter.post('/poc1/sessions/:id/stop', async (req, res) => { try { const owner = ownerFor(req, req.body?.ownerId); assertOwnedSession(req, req.params.id, owner); res.json({ status: 'stopped', session: await stopXpraPoc(req.params.id, owner) }); } catch (error) { sendError(res, error, 'LINUX_POC_STOP_FAILED'); } });
linuxRuntimeRouter.post('/poc1/sessions/:id/client-metrics', (req, res) => { try { const owner = ownerFor(req, req.body?.ownerId); assertOwnedSession(req, req.params.id, owner); res.json({ session: recordXpraPocClientMetrics(req.params.id, owner, req.body || {}) }); } catch (error) { sendError(res, error, 'LINUX_POC_METRICS_FAILED'); } });
linuxRuntimeRouter.post('/poc1/cleanup', async (req, res) => { try { res.json(await cleanupXpraPoc({ ownerId: ownerFor(req, req.body?.ownerId), orphansOnly: req.body?.orphansOnly === true })); } catch (error) { sendError(res, error, 'LINUX_POC_CLEANUP_FAILED'); } });
linuxRuntimeRouter.post('/poc1/stop', async (req, res) => { try { const owner = ownerFor(req, req.body?.ownerId); res.json({ status: 'stopped', sessions: await stopXpraPoc(null, owner) }); } catch (error) { sendError(res, error, 'LINUX_POC_STOP_FAILED'); } });
