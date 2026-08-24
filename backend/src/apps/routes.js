import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { hasNativeHostTrust } from '../auth/hostTrust.js';
import { launchCatalogApp, refreshAppCatalog } from './appCatalog.js';

export const appsRouter = express.Router();
appsRouter.use(authenticateToken);

appsRouter.get('/', async (req, res, next) => {
  try {
    const apps = await refreshAppCatalog(req.query.refresh === 'true');
    res.json({ apps });
  } catch (error) {
    next(error);
  }
});

appsRouter.post('/:id/launch', async (req, res) => {
  try {
    if (!hasNativeHostTrust(req, req.app.locals.cloudOsHostTrustPolicy)) {
      return res.status(403).json({ error: 'Somente o Host nativo confiável pode resolver uma especificação de lançamento Windows.', errorCode: 'NATIVE_HOST_TRUST_REQUIRED' });
    }
    res.status(202).json(await launchCatalogApp(req.params.id));
  } catch (error) {
    res.status(error.code === 'APP_NOT_FOUND' ? 404 : 503).json({ error: error.message, errorCode: error.code || 'APP_LAUNCH_FAILED' });
  }
});
