import crypto from 'node:crypto';
import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { hasNativeHostTrust } from '../auth/hostTrust.js';
import { launchCatalogApp, refreshAppCatalog } from './appCatalog.js';
import { classifyCatalogRuntime } from './windowsRuntimeCompatibility.js';
import { assertNoExternalInstanceHandoffRisk } from './windowsExternalInstanceGuard.js';

export const appsRouter = express.Router();
appsRouter.use(authenticateToken);

function publicCatalogSnapshot(apps) {
  const enriched = apps.map((app) => ({
    ...app,
    compatibility: classifyCatalogRuntime(app)
  }));
  const canonical = enriched.map((app) => ({
    id: app.id,
    name: app.name,
    source: app.source,
    discoverySource: app.discoverySource || null,
    runtimeClass: app.runtimeClass || null,
    launchable: Boolean(app.launchable),
    compatibilityStatus: app.compatibility?.status || null
  }));
  const revision = crypto.createHash('sha256').update(JSON.stringify(canonical)).digest('hex');
  return { apps: enriched, revision, generatedAt: new Date().toISOString() };
}

appsRouter.get('/', async (req, res, next) => {
  try {
    const apps = await refreshAppCatalog(req.query.refresh === 'true');
    res.json(publicCatalogSnapshot(apps));
  } catch (error) {
    next(error);
  }
});

appsRouter.post('/refresh', async (req, res) => {
  try {
    if (!hasNativeHostTrust(req, req.app.locals.cloudOsHostTrustPolicy)) {
      return res.status(403).json({
        error: 'Somente o Host nativo confiável pode forçar o rescan do catálogo Windows.',
        errorCode: 'NATIVE_HOST_TRUST_REQUIRED'
      });
    }
    const apps = await refreshAppCatalog(true);
    res.json(publicCatalogSnapshot(apps));
  } catch (error) {
    res.status(503).json({ error: error.message, errorCode: error.code || 'APP_CATALOG_REFRESH_FAILED' });
  }
});

appsRouter.post('/:id/launch', async (req, res) => {
  try {
    if (!hasNativeHostTrust(req, req.app.locals.cloudOsHostTrustPolicy)) {
      return res.status(403).json({ error: 'Somente o Host nativo confiável pode resolver uma especificação de lançamento Windows.', errorCode: 'NATIVE_HOST_TRUST_REQUIRED' });
    }
    const launch = await launchCatalogApp(req.params.id);
    await assertNoExternalInstanceHandoffRisk(launch, req.body?.managedProcesses);
    res.status(202).json(launch);
  } catch (error) {
    const status = error.code === 'APP_NOT_FOUND'
      ? 404
      : (error.code === 'EXTERNAL_INSTANCE_CONFLICT' ? 409 : 503);
    res.status(status).json({ error: error.message, errorCode: error.code || 'APP_LAUNCH_FAILED' });
  }
});
