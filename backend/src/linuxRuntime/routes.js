import crypto from 'node:crypto';
import fs from 'node:fs';
import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { validateInstalledAsync } from '../wsl/distroService.js';
import { checkXpraPocReadiness, cleanupXpraPoc, getAllowedLinuxPocApps, getXpraPocSessions, healthXpraPocSession, recordXpraPocClientMetrics, restartXpraPoc, startXpraPoc, stopXpraPoc } from './xpraPoc.js';
import { finalizePhysicalPreflight, startPhysicalPreflight } from './preflight.js';
import { installLinuxPackage, listLinuxPackages, searchLinuxPackages, uninstallLinuxPackage } from './packageManager.js';
import { scanDiscoveredLinuxApps } from './desktopScanner.js';
import { resolveLinuxIconPath, getMimeTypeForIcon } from './iconResolver.js';

import { getActiveDistro, setActiveDistro, listInstalledDistros, listOnlineDistros, installDistro, unregisterDistro, importDistro, provisionDistro, streamProvisionDistro, getCloudOSHome, validateDistroIdentifier } from './distroManager.js';

export const linuxRuntimeRouter = express.Router();

function statusForCode(code, statusCode) {
  if (statusCode && Number.isInteger(statusCode)) return statusCode;
  if (['LINUX_POC_APP_NOT_ALLOWED', 'LINUX_POC_OWNER_INVALID', 'PREFLIGHT_OWNER_INVALID', 'PACKAGE_NOT_FOUND', 'INVALID_PACKAGE_NAME', 'INVALID_DISTRO_NAME'].includes(code)) return 400;
  if (['LINUX_POC_SESSION_ACTIVE', 'LINUX_POC_SESSION_LIMIT', 'LINUX_POC_ORPHANED_SESSION', 'LINUX_POC_SESSION_OWNER_MISMATCH', 'PREFLIGHT_OWNER_MISMATCH'].includes(code)) return 409;
  if (['LINUX_POC_SESSION_NOT_FOUND', 'PREFLIGHT_RUN_NOT_FOUND'].includes(code)) return 404;
  return 503;
}

function sendError(res, error, fallback) {
  const code = error?.code || fallback;
  const status = error?.statusCode || statusForCode(code, error?.statusCode);
  res.status(status).json({ error: error?.message || 'Erro interno.', errorCode: code, details: error?.details || null });
}

// Public icon serving endpoint (no token required for img tags)
linuxRuntimeRouter.get('/icons/:id', (req, res) => {
  try {
    const distro = req.query?.distro || 'kali-linux';
    const iconId = req.params.id;
    const filePath = resolveLinuxIconPath(distro, iconId);
    if (!filePath || !fs.existsSync(filePath)) {
      return res.status(404).send('Icon not found');
    }
    const mime = getMimeTypeForIcon(filePath);
    res.setHeader('Content-Type', mime);
    res.setHeader('Cache-Control', 'public, max-age=604800');
    res.sendFile(filePath);
  } catch {
    res.status(404).send('Icon error');
  }
});

// Public distro lifecycle routes for First Boot Setup & OOBE
linuxRuntimeRouter.get('/distros', async (req, res) => {
  try {
    const active = getActiveDistro();
    const installed = await listInstalledDistros();
    const online = await listOnlineDistros();
    res.json({ active, installed, online });
  } catch (error) {
    sendError(res, error, 'DISTRO_LIST_FAILED');
  }
});

linuxRuntimeRouter.post('/distros/active', (req, res) => {
  try {
    const distro = req.body?.distro;
    const config = setActiveDistro(distro);
    res.json({ success: true, config });
  } catch (error) {
    sendError(res, error, 'DISTRO_SET_ACTIVE_FAILED');
  }
});

linuxRuntimeRouter.post('/distros/install', async (req, res) => {
  try {
    const distro = req.body?.distro;
    const result = await installDistro(distro);
    res.json(result);
  } catch (error) {
    sendError(res, error, 'DISTRO_INSTALL_FAILED');
  }
});

linuxRuntimeRouter.post('/distros/unregister', async (req, res) => {
  try {
    const distro = req.body?.distro;
    const result = await unregisterDistro(distro);
    res.json(result);
  } catch (error) {
    sendError(res, error, 'DISTRO_UNREGISTER_FAILED');
  }
});

linuxRuntimeRouter.post('/distros/import', async (req, res) => {
  try {
    const { distro, location, tarPath } = req.body || {};
    const result = await importDistro(distro, location, tarPath);
    res.json(result);
  } catch (error) {
    sendError(res, error, 'DISTRO_IMPORT_FAILED');
  }
});

linuxRuntimeRouter.post('/distros/provision', async (req, res) => {
  try {
    const distro = req.body?.distro;
    const result = await provisionDistro(distro);
    res.json(result);
  } catch (error) {
    sendError(res, error, 'DISTRO_PROVISION_FAILED');
  }
});

linuxRuntimeRouter.get('/distros/provision/stream', async (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders?.();

  const previousActiveDistro = getActiveDistro();
  let distro = String(req.query?.distro || previousActiveDistro).trim();
  const mode = String(req.query?.mode || 'existing').trim();
  let successConfirmed = false;

  try {
    distro = validateDistroIdentifier(distro);
    if (!['existing', 'reinstall', 'new', 'custom'].includes(mode)) {
      const invalidMode = new Error('Modo de provisionamento inválido.');
      invalidMode.code = 'INVALID_PROVISION_MODE';
      throw invalidMode;
    }

    for await (const event of streamProvisionDistro(distro, mode)) {
      if (event?.error) throw new Error(String(event.error));
      if (event?.done === true) {
        const installed = await listInstalledDistros();
        const registered = installed.find(item => String(item.id || '').toLowerCase() === distro.toLowerCase());
        const installing = /install|instalando|uninstall|desinstalando/i.test(String(registered?.state || ''));
        const installedByCore = await validateInstalledAsync(distro);
        if (!registered || installing || !installedByCore) {
          const notReady = new Error(`A distribuição WSL "${distro}" não confirmou registro concluído. O setup não será finalizado.`);
          notReady.code = 'DISTRO_PROVISION_NOT_READY';
          throw notReady;
        }
        setActiveDistro(distro);
        successConfirmed = true;
      }
      res.write(`data: ${JSON.stringify(event)}\n\n`);
    }
  } catch (error) {
    if (!successConfirmed && previousActiveDistro && previousActiveDistro !== distro) {
      try { setActiveDistro(previousActiveDistro); } catch {}
    }
    res.write(`data: ${JSON.stringify({ error: error?.message || 'Falha no provisionamento da distribuição.' })}\n\n`);
  } finally {
    res.end();
  }
});

linuxRuntimeRouter.get('/home', (req, res) => {
  try {
    res.json({ home: getCloudOSHome() });
  } catch (error) {
    sendError(res, error, 'CLOUDOS_HOME_FAILED');
  }
});

linuxRuntimeRouter.use(authenticateToken);

function rawOwner(value) {
  const owner = String(value || '').trim();
  if (!/^[a-zA-Z0-9._:-]{1,128}$/.test(owner)) {
    const error = new Error('Identificador da CloudOS Window inválido.');
    error.code = 'LINUX_POC_OWNER_INVALID';
    throw error;
  }
  return owner;
}

function principal(req) { return String(req.user?.id || req.user?.userId || req.user?.username || 'anonymous'); }
function principalPrefix(req) { return `${crypto.createHash('sha256').update(principal(req)).digest('hex').slice(0, 24)}:`; }
export function scopedOwnerId(userId, ownerId) { return `${crypto.createHash('sha256').update(String(userId)).digest('hex').slice(0, 24)}:${rawOwner(ownerId)}`; }
function ownerFor(req, value) { return scopedOwnerId(principal(req), value); }
function notFound() { const error = new Error('Sessão POC 1 não encontrada para este principal/window.'); error.code = 'LINUX_POC_SESSION_NOT_FOUND'; return error; }
function assertOwnedSession(id, ownerId) { if (!getXpraPocSessions(ownerId).some(session => session.id === id)) throw notFound(); }
function assertPrincipalSession(req, id) { if (!getXpraPocSessions().some(session => session.id === id && session.ownerId.startsWith(principalPrefix(req)))) throw notFound(); }

// Dynamic Package & Discovery Endpoints
linuxRuntimeRouter.get('/packages', async (req, res) => {
  try {
    const distro = req.query?.distribution || req.query?.distro;
    const result = await listLinuxPackages(distro);
    res.json(result);
  } catch (error) {
    sendError(res, error, 'PACKAGES_LIST_FAILED');
  }
});

linuxRuntimeRouter.get('/discovered', async (req, res) => {
  try {
    const distro = req.query?.distribution || req.query?.distro;
    const apps = await scanDiscoveredLinuxApps(distro, { force: req.query?.force === 'true' });
    res.json({ apps, count: apps.length });
  } catch (error) {
    sendError(res, error, 'DISCOVERY_SCAN_FAILED');
  }
});

linuxRuntimeRouter.post('/packages/:id/install', async (req, res) => {
  try {
    const distro = req.body?.distribution || req.body?.distro;
    const result = await installLinuxPackage(distro, req.params.id);
    res.status(200).json(result);
  } catch (error) {
    sendError(res, error, 'PACKAGE_INSTALL_FAILED');
  }
});

linuxRuntimeRouter.post('/packages/:id/uninstall', async (req, res) => {
  try {
    const distro = req.body?.distribution || req.body?.distro;
    const result = await uninstallLinuxPackage(distro, req.params.id);
    res.status(200).json(result);
  } catch (error) {
    sendError(res, error, 'PACKAGE_UNINSTALL_FAILED');
  }
});

linuxRuntimeRouter.get('/packages/search', async (req, res) => {
  try {
    const distro = req.query?.distribution || req.query?.distro;
    const result = await searchLinuxPackages(distro, req.query?.q);
    res.json(result);
  } catch (error) {
    sendError(res, error, 'PACKAGE_SEARCH_FAILED');
  }
});

// POC & Contained Lifecycle Endpoints
linuxRuntimeRouter.get('/poc1', async (req, res) => {
  try {
    const owner = ownerFor(req, req.query?.ownerId);
    const apps = await getAllowedLinuxPocApps(req.query?.distribution);
    res.json({
      mode: 'xpra-html5-contained-minimal',
      transport: 'capability-proxy',
      externalWindowsExpected: 0,
      maxAppsPerWindow: 4,
      apps,
      sessions: getXpraPocSessions(owner)
    });
  } catch (error) {
    sendError(res, error, 'LINUX_POC_STATUS_FAILED');
  }
});

linuxRuntimeRouter.get('/poc1/readiness', async (req, res) => {
  try {
    res.json(await checkXpraPocReadiness({ app: req.query?.app || 'xclock', distribution: req.query?.distribution || undefined }));
  } catch (error) {
    sendError(res, error, 'LINUX_POC_READINESS_FAILED');
  }
});

linuxRuntimeRouter.post('/poc1/preflight', async (req, res) => {
  try {
    const port = Number(req.app?._cloudosPort || 0);
    res.json(await startPhysicalPreflight({ ownerId: ownerFor(req, req.body?.ownerId), distribution: req.body?.distribution || undefined, backendOrigin: port > 0 ? `http://127.0.0.1:${port}` : null }));
  } catch (error) {
    sendError(res, error, 'POC1_PREFLIGHT_FAILED');
  }
});

linuxRuntimeRouter.post('/poc1/preflight/:id/finalize', async (req, res) => {
  try {
    res.json(await finalizePhysicalPreflight({ runId: req.params.id, ownerId: ownerFor(req, req.body?.ownerId), evidence: req.body?.evidence || {}, iframe: req.body?.iframe || {} }));
  } catch (error) {
    sendError(res, error, 'POC1_PREFLIGHT_FINALIZE_FAILED');
  }
});

linuxRuntimeRouter.post('/poc1/start', async (req, res) => {
  try {
    res.status(201).json({ session: await startXpraPoc({ app: req.body?.app, distribution: req.body?.distribution, ownerId: ownerFor(req, req.body?.ownerId) }) });
  } catch (error) {
    sendError(res, error, 'LINUX_POC_START_FAILED');
  }
});

linuxRuntimeRouter.get('/poc1/sessions/:id/health', async (req, res) => {
  try {
    assertPrincipalSession(req, req.params.id);
    res.json(await healthXpraPocSession(req.params.id));
  } catch (error) {
    sendError(res, error, 'LINUX_POC_HEALTH_FAILED');
  }
});

linuxRuntimeRouter.post('/poc1/sessions/:id/restart', async (req, res) => {
  try {
    const owner = ownerFor(req, req.body?.ownerId);
    assertOwnedSession(req.params.id, owner);
    res.json({ session: await restartXpraPoc(req.params.id, owner) });
  } catch (error) {
    sendError(res, error, 'LINUX_POC_RESTART_FAILED');
  }
});

linuxRuntimeRouter.post('/poc1/sessions/:id/stop', async (req, res) => {
  try {
    const owner = ownerFor(req, req.body?.ownerId);
    assertOwnedSession(req.params.id, owner);
    res.json({ status: 'stopped', session: await stopXpraPoc(req.params.id, owner) });
  } catch (error) {
    sendError(res, error, 'LINUX_POC_STOP_FAILED');
  }
});

linuxRuntimeRouter.post('/poc1/sessions/:id/client-metrics', (req, res) => {
  try {
    const owner = ownerFor(req, req.body?.ownerId);
    assertOwnedSession(req.params.id, owner);
    res.json({ session: recordXpraPocClientMetrics(req.params.id, owner, req.body || {}) });
  } catch (error) {
    sendError(res, error, 'LINUX_POC_METRICS_FAILED');
  }
});

linuxRuntimeRouter.post('/poc1/cleanup', async (req, res) => {
  try {
    res.json(await cleanupXpraPoc({ ownerId: ownerFor(req, req.body?.ownerId), orphansOnly: req.body?.orphansOnly === true }));
  } catch (error) {
    sendError(res, error, 'LINUX_POC_CLEANUP_FAILED');
  }
});

linuxRuntimeRouter.post('/poc1/stop', async (req, res) => {
  try {
    const owner = ownerFor(req, req.body?.ownerId);
    res.json({ status: 'stopped', sessions: await stopXpraPoc(null, owner) });
  } catch (error) {
    sendError(res, error, 'LINUX_POC_STOP_FAILED');
  }
});

// Generic & Contained Launch Endpoint
linuxRuntimeRouter.post('/launch', async (req, res) => {
  try {
    const owner = ownerFor(req, req.body?.ownerId);
    const session = await startXpraPoc({
      app: req.body?.appId || req.body?.app || 'firefox',
      ownerId: owner,
      distribution: req.body?.distribution,
      filePath: req.body?.filePath,
      reuseExisting: req.body?.reuseExisting === true,
    });
    res.status(201).json({ session });
  } catch (error) {
    sendError(res, error, 'LINUX_FAST_LAUNCH_FAILED');
  }
});
