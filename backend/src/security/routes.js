import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { getKaliToolInventory } from './toolInventory.js';

export const securityToolsRouter = express.Router();
securityToolsRouter.use(authenticateToken);

securityToolsRouter.get('/', async (req, res) => {
  try {
    const inventory = await getKaliToolInventory(req.query.distribution);
    res.status(inventory.operational ? 200 : 503).json(inventory);
  } catch (error) {
    const status = error.code === 'DISTRO_NOT_INSTALLED' ? 404 : 503;
    res.status(status).json({
      error: error.message || 'Não foi possível consultar as ferramentas.',
      errorCode: error.code || 'TOOL_INVENTORY_FAILED'
    });
  }
});
