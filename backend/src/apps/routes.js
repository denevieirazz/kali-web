import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { hasNativeHostTrust } from '../auth/hostTrust.js';
import { launchCatalogApp, refreshAppCatalog } from './appCatalog.js';
import { applyCloudFileHandoff } from './fileHandoff.js';
import { consumeNativeLaunchCapability, issueNativeLaunchCapability } from './launchCapability.js';

export const appsRouter = express.Router();
appsRouter.use(authenticateToken);

function principal(req) {
  return String(req.user?.id || req.user?.userId || req.user?.username || 'anonymous');
}

function statusForLaunchError(error) {
  const clientErrorCodes = new Set([
    'CLOUDOS_FILE_REF_INVALID',
    'CLOUDOS_FILE_REF_SCOPE_DENIED',
    'CLOUDOS_DRIVE_SYMLINK_BLOCKED',
    'CLOUDOS_DRIVE_ESCAPE_BLOCKED',
    'CLOUDOS_DRIVE_NOT_FILE',
    'APP_FILE_HANDOFF_UNSUPPORTED',
    'APP_ARGUMENT_LIMIT',
    'APP_LAUNCH_CAPABILITY_INVALID',
    'APP_LAUNCH_CAPABILITY_LIMIT',
  ]);
  if (error.code === 'APP_NOT_FOUND' || error.code === 'CLOUDOS_DRIVE_NOT_FOUND' || error.code === 'APP_LAUNCH_CAPABILITY_NOT_FOUND') return 404;
  return clientErrorCodes.has(error.code) ? 400 : 503;
}

appsRouter.get('/', async (req, res, next) => {
  try {
    const apps = await refreshAppCatalog(req.query.refresh === 'true');
    res.json({ apps });
  } catch (error) {
    next(error);
  }
});

// The renderer never receives a host filesystem path. It submits a logical CloudOS
// Drive reference and gets a short-lived, one-time native app ID that is useful only
// when the trusted Host redeems it with the same authenticated principal.
appsRouter.post('/:id/file-handoff', async (req, res) => {
  try {
    const baseLaunch = await launchCatalogApp(req.params.id);
    const launch = await applyCloudFileHandoff(baseLaunch, req.body?.fileRef);
    const capability = issueNativeLaunchCapability({ principal: principal(req), launch });
    res.status(201).json({ launchAppId: capability.id, expiresAt: capability.expiresAt });
  } catch (error) {
    res.status(statusForLaunchError(error)).json({ error: error.message, errorCode: error.code || 'APP_FILE_HANDOFF_FAILED' });
  }
});

appsRouter.post('/:id/launch', async (req, res) => {
  try {
    if (!hasNativeHostTrust(req, req.app.locals.cloudOsHostTrustPolicy)) {
      return res.status(403).json({ error: 'Somente o Host nativo confiável pode resolver uma especificação de lançamento Windows.', errorCode: 'NATIVE_HOST_TRUST_REQUIRED' });
    }
    const stagedLaunch = consumeNativeLaunchCapability(req.params.id, principal(req));
    res.status(202).json(stagedLaunch || await launchCatalogApp(req.params.id));
  } catch (error) {
    res.status(statusForLaunchError(error)).json({ error: error.message, errorCode: error.code || 'APP_LAUNCH_FAILED' });
  }
});
