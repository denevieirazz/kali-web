import express from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { getDb } from '../database/index.js';
import { config } from '../config/index.js';
import { authenticateToken } from '../middleware/auth.js';

export const authRouter = express.Router();

// Login
authRouter.post('/login', (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Usuário e senha são obrigatórios.' });
  }

  const db = getDb();
  db.get('SELECT * FROM users WHERE username = ?', [username], async (err, user) => {
    if (err) {
      return res.status(500).json({ error: 'Erro interno no banco de dados.' });
    }

    if (!user) {
      // Para fins de dev/bootstrap inicial controlado, se for admin e senha configurada, cria usuário
      return res.status(401).json({ error: 'Credenciais inválidas.' });
    }

    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) {
      return res.status(401).json({ error: 'Credenciais inválidas.' });
    }

    const payload = {
      userId: user.id,
      username: user.username,
      role: user.role
    };

    const token = jwt.sign(payload, config.jwtSecret, { expiresIn: config.jwtExpiresIn });

    res.json({
      message: 'Autenticado com sucesso.',
      token,
      user: {
        id: user.id,
        username: user.username,
        role: user.role
      }
    });
  });
});

// Sessão atual
authRouter.get('/session', authenticateToken, (req, res) => {
  res.json({
    authenticated: true,
    user: req.user
  });
});

// Logout
authRouter.post('/logout', authenticateToken, (req, res) => {
  res.json({ message: 'Sessão encerrada com sucesso.' });
});
