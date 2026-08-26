import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import { getDb, resetLocalDatabase } from '../database/index.js';
import { config } from '../config/index.js';
import { authenticateToken, requireAdmin } from '../middleware/auth.js';
import {
  generateRecoveryCode,
  hashPassword,
  hashRecoveryCode,
  noStore,
  signSessionToken,
  toPublicUser,
  validateDisplayName,
  validatePassword,
  validateUsername
} from '../auth/security.js';

export const setupRouter = express.Router();

function dbGet(db, query, params) {
  return new Promise((resolve, reject) => db.get(query, params, (error, row) => error ? reject(error) : resolve(row)));
}

function dbRun(db, query, params) {
  return new Promise((resolve, reject) => db.run(query, params, error => error ? reject(error) : resolve()));
}

// GET /api/setup/status
setupRouter.get('/status', async (_req, res, next) => {
  try {
    const db = getDb();
    const row = await dbGet(db, 'SELECT COUNT(*) as count FROM users WHERE role = ?', ['admin']);
    res.json({ setupRequired: (row?.count || 0) === 0 });
  } catch (error) {
    next(error);
  }
});

// POST /api/setup/admin
setupRouter.post('/admin', async (req, res, next) => {
  try {
    const db = getDb();
    const row = await dbGet(db, 'SELECT COUNT(*) as count FROM users WHERE role = ?', ['admin']);
    if ((row?.count || 0) > 0) {
      return res.status(409).json({ error: 'Um administrador já foi configurado no sistema.' });
    }

    const { username, displayName, password, confirmPassword } = req.body || {};
    const checkedUsername = validateUsername(username);
    if (checkedUsername.error) return res.status(400).json({ error: checkedUsername.error });

    const checkedDisplayName = validateDisplayName(displayName, checkedUsername.value);
    if (checkedDisplayName.error) return res.status(400).json({ error: checkedDisplayName.error });

    const checkedPassword = validatePassword(password, confirmPassword);
    if (checkedPassword.error) return res.status(400).json({ error: checkedPassword.error });

    const userId = uuidv4();
    const recoveryCode = generateRecoveryCode();
    const [passwordHash, recoveryCodeHash] = await Promise.all([
      hashPassword(password),
      hashRecoveryCode(recoveryCode)
    ]);

    await dbRun(
      db,
      'INSERT INTO users (id, username, display_name, password_hash, recovery_code_hash, auth_version, role) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [userId, checkedUsername.value, checkedDisplayName.value, passwordHash, recoveryCodeHash, 1, 'admin']
    );

    const user = {
      id: userId,
      username: checkedUsername.value,
      display_name: checkedDisplayName.value,
      role: 'admin',
      auth_version: 1
    };
    noStore(res);
    return res.status(201).json({
      message: 'Administrador configurado com sucesso.',
      token: signSessionToken(user),
      user: toPublicUser(user),
      recoveryCode,
      recoveryCodeShownOnce: true
    });
  } catch (error) {
    if (error.message === 'ADMIN_EXISTS') {
      return res.status(409).json({ error: 'Um administrador já foi configurado no sistema.' });
    }
    if (error.message === 'USERNAME_EXISTS') {
      return res.status(409).json({ error: 'Não foi possível concluir a configuração com esse nome de usuário.' });
    }
    return next(error);
  }
});

// POST /api/setup/reset — opção local de desenvolvimento protegida por administrador.
setupRouter.post('/reset', (req, res, next) => {
  if (!config.setupResetEnabled) return res.sendStatus(404);
  return next();
}, authenticateToken, requireAdmin, (req, res) => {
  const { confirm } = req.body || {};
  if (confirm !== true) {
    return res.status(400).json({ error: 'Confirmação explícita necessária para redefinir a instalação local.' });
  }

  resetLocalDatabase();
  res.json({ message: 'Instalação local redefinida com sucesso.' });
});
