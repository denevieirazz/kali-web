import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
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
    res.status(202).json(await launchCatalogApp(req.params.id));
  } catch (error) {
    res.status(error.code === 'APP_NOT_FOUND' ? 404 : 503).json({ error: error.message, errorCode: error.code || 'APP_LAUNCH_FAILED' });
  }
});
