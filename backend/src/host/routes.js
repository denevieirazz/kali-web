import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { getHostCapabilities } from '../wsl/distroService.js';

export const hostRouter = express.Router();

hostRouter.use(authenticateToken);

hostRouter.get('/capabilities', async (_req, res, next) => {
  try {
    res.json(await getHostCapabilities());
  } catch (error) {
    next(error);
  }
});
