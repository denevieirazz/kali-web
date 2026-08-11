import express from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { getDb, resetLocalDatabase } from '../database/index.js';
import { config } from '../config/index.js';

export const setupRouter = express.Router();

// GET /api/setup/status
setupRouter.get('/status', (req, res) => {
  const db = getDb();
  db.get('SELECT COUNT(*) as count FROM users WHERE role = ?', ['admin'], (err, row) => {
    if (err) {
      return res.status(500).json({ error: 'Erro ao verificar status do sistema.' });
    }
    const count = row ? row.count : 0;
    res.json({ setupRequired: count === 0 });
  });
});

// POST /api/setup/admin
setupRouter.post('/admin', (req, res) => {
  const db = getDb();

  db.get('SELECT COUNT(*) as count FROM users WHERE role = ?', ['admin'], async (err, row) => {
    if (err) {
      return res.status(500).json({ error: 'Erro ao verificar instalacao.' });
    }

    const count = row ? row.count : 0;
    if (count > 0) {
      return res.status(409).json({ error: 'Um administrador já foi configurado no sistema.' });
    }

    const { username, password, confirmPassword } = req.body || {};

    const cleanUsername = (username || '').trim();
    if (!cleanUsername || cleanUsername.length < 3) {
      return res.status(400).json({ error: 'O nome de usuario deve conter pelo menos 3 caracteres.' });
    }

    if (!/^[a-zA-Z0-9._-]+$/.test(cleanUsername)) {
      return res.status(400).json({ error: 'Nome de usuario contem caracteres invalidos.' });
    }

    if (!password || typeof password !== 'string' || password.length < 6) {
      return res.status(400).json({ error: 'A senha deve conter pelo menos 6 caracteres.' });
    }

    if (password !== confirmPassword) {
      return res.status(400).json({ error: 'A confirmacao de senha nao confere.' });
    }

    const userId = uuidv4();
    const passwordHash = await bcrypt.hash(password, 10);

    db.run(
      'INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?)',
      [userId, cleanUsername, passwordHash, 'admin'],
      (insertErr) => {
        if (insertErr) {
          return res.status(500).json({ error: 'Erro ao registrar administrador no banco.' });
        }

        const payload = {
          userId,
          username: cleanUsername,
          role: 'admin'
        };

        const token = jwt.sign(payload, config.jwtSecret, { expiresIn: config.jwtExpiresIn });

        res.status(201).json({
          message: 'Administrador configurado com sucesso.',
          token,
          user: {
            id: userId,
            username: cleanUsername,
            role: 'admin'
          }
        });
      }
    );
  });
});

// POST /api/setup/reset — Opcao segura de redefinicao local para desenvolvimento
setupRouter.post('/reset', (req, res) => {
  const { confirm } = req.body || {};
  if (confirm !== true) {
    return res.status(400).json({ error: 'Confirmacao explicita necessaria para redefinir a instalacao local.' });
  }

  resetLocalDatabase();
  res.json({ message: 'Instalacao local redefinida com sucesso.' });
});
