import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { hasNativeHostTrust } from '../auth/hostTrust.js';
import { launchCatalogApp, refreshAppCatalog } from './appCatalog.js';
import { applyCloudFileHandoff } from './fileHandoff.js';

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
    const launch = await launchCatalogApp(req.params.id);
    res.status(202).json(await applyCloudFileHandoff(launch, req.body?.fileRef));
  } catch (error) {
    const clientErrorCodes = new Set([
      'CLOUDOS_FILE_REF_INVALID',
      'CLOUDOS_FILE_REF_SCOPE_DENIED',
      'CLOUDOS_DRIVE_SYMLINK_BLOCKED',
      'CLOUDOS_DRIVE_ESCAPE_BLOCKED',
      'CLOUDOS_DRIVE_NOT_FILE',
      'APP_FILE_HANDOFF_UNSUPPORTED',
      'APP_ARGUMENT_LIMIT',
    ]);
    const status = error.code === 'APP_NOT_FOUND' || error.code === 'CLOUDOS_DRIVE_NOT_FOUND'
      ? 404
      : (clientErrorCodes.has(error.code) ? 400 : 503);
    res.status(status).json({ error: error.message, errorCode: error.code || 'APP_LAUNCH_FAILED' });
  }
});
