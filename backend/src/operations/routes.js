import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import { getDb } from '../database/index.js';
import { authenticateToken } from '../middleware/auth.js';

export const operationsRouter = express.Router();

// Listar ou buscar status de operação
operationsRouter.get('/:id', authenticateToken, (req, res) => {
  const db = getDb();
  db.get('SELECT * FROM operations WHERE id = ?', [req.params.id], (err, row) => {
    if (err) return res.status(500).json({ error: 'Erro no banco de dados.' });
    if (!row) return res.status(404).json({ error: 'Operação não encontrada.' });
    res.json(row);
  });
});

// Criar operação de simulação/mock de instalador
operationsRouter.post('/', authenticateToken, (req, res) => {
  const { type } = req.body;
  const id = uuidv4();
  const db = getDb();

  const query = `
    INSERT INTO operations (id, type, status, progress, step, message)
    VALUES (?, ?, 'running', 10, 'checking', 'Validando pré-requisitos do sistema...')
  `;

  db.run(query, [id, type || 'install_linux'], (err) => {
    if (err) return res.status(500).json({ error: 'Erro ao criar operação.' });
    res.status(201).json({ id, status: 'running', progress: 10 });
  });
});
