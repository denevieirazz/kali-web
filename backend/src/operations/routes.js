import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { cancelOperation, getOperation, listOperations } from './operationManager.js';

export const operationsRouter = express.Router();

operationsRouter.use(authenticateToken);

operationsRouter.get('/', (_req, res) => {
  res.json({ operations: listOperations() });
});

operationsRouter.get('/:id', (req, res) => {
  const operation = getOperation(req.params.id);
  if (!operation) return res.status(404).json({ error: 'Operação não encontrada.' });
  res.json(operation);
});

operationsRouter.post('/:id/cancel', (req, res) => {
  const result = cancelOperation(req.params.id);
  if (!result.found) return res.status(404).json({ error: 'Operação não encontrada.' });
  if (!result.cancelled) {
    return res.status(409).json({ error: 'Esta operação não pode mais ser cancelada.', operation: result.operation });
  }
  res.status(202).json(result.operation);
});
