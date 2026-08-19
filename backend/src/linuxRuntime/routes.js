import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { getAllowedLinuxPocApps, getXpraPocSession, startXpraPoc, stopXpraPoc } from './xpraPoc.js';

export const linuxRuntimeRouter = express.Router();
linuxRuntimeRouter.use(authenticateToken);

linuxRuntimeRouter.get('/poc1', (_req, res) => {
  res.json({
    mode: 'xpra-html5-contained',
    externalWindowsExpected: 0,
    apps: getAllowedLinuxPocApps(),
    session: getXpraPocSession(),
  });
});

linuxRuntimeRouter.post('/poc1/start', async (req, res) => {
  try {
    const session = await startXpraPoc({ app: req.body?.app, distribution: req.body?.distribution });
    res.status(201).json({ session });
  } catch (error) {
    const code = error.code || 'LINUX_POC_START_FAILED';
    const status = code === 'LINUX_POC_APP_NOT_ALLOWED' ? 400
      : code === 'LINUX_POC_SESSION_ACTIVE' ? 409
        : 503;
    res.status(status).json({ error: error.message, errorCode: code });
  }
});

linuxRuntimeRouter.post('/poc1/stop', async (_req, res) => {
  try {
    const session = await stopXpraPoc();
    res.json({ status: 'stopped', session });
  } catch (error) {
    res.status(503).json({ error: error.message, errorCode: error.code || 'LINUX_POC_STOP_FAILED' });
  }
});
