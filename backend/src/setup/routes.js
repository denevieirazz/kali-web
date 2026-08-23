import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import { getDb, resetLocalDatabase } from '../database/index.js';
import { config, resolveSetupResetEnabled } from '../config/index.js';
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

function validateSetupAdminInput(req, res, next) {
  const { username, displayName, password = '', confirmPassword = '' } = req.body || {};
  const checkedUsername = validateUsername(username);
  if (checkedUsername.error) return res.status(400).json({ error: checkedUsername.error });

  const checkedDisplayName = validateDisplayName(displayName, checkedUsername.value);
  if (checkedDisplayName.error) return res.status(400).json({ error: checkedDisplayName.error });

  const checkedPassword = validatePassword(password, confirmPassword);
  if (checkedPassword.error) return res.status(400).json({ error: checkedPassword.error });

  req.setupAdminInput = {
    username: checkedUsername.value,
    displayName: checkedDisplayName.value,
    password
  };
  return next();
}

async function guardExistingAdminSetup(req, res, next) {
  try {
    const existingAdmin = await dbGet(getDb(), 'SELECT id FROM users WHERE role = ? LIMIT 1', ['admin']);
    if (!existingAdmin) return next();

    // A second setup attempt is a resource conflict, not an authentication challenge.
    // Only an explicit replacement request enters the administrator auth gate.
    if (req.body?.allowUpdate !== true) {
      return res.status(409).json({ error: 'Um administrador já foi configurado no sistema.' });
    }

    return authenticateToken(req, res, () => requireAdmin(req, res, next));
  } catch (error) {
    return next(error);
  }
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
// Validate the payload before deciding whether this is a first-boot creation,
// a conflicting second creation, or an authenticated administrator replacement.
setupRouter.post('/admin', validateSetupAdminInput, guardExistingAdminSetup, async (req, res, next) => {
  try {
    const db = getDb();
    const { username, displayName, password } = req.setupAdminInput;
    const existingAdmin = await dbGet(db, 'SELECT * FROM users WHERE role = ?', ['admin']);
    if (existingAdmin && req.body?.allowUpdate !== true) {
      return res.status(409).json({ error: 'Um administrador já foi configurado no sistema.' });
    }

    const userId = existingAdmin?.id || uuidv4();
    const recoveryCode = generateRecoveryCode();
    const [passwordHash, recoveryCodeHash] = await Promise.all([
      hashPassword(password),
      hashRecoveryCode(recoveryCode)
    ]);

    if (existingAdmin) {
      await dbRun(
        db,
        'UPDATE users SET username = ?, display_name = ?, password_hash = ?, recovery_code_hash = ?, auth_version = auth_version + 1 WHERE id = ?',
        [username, displayName, passwordHash, recoveryCodeHash, userId]
      );
    } else {
      await dbRun(
        db,
        'INSERT INTO users (id, username, display_name, password_hash, recovery_code_hash, auth_version, role) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [userId, username, displayName, passwordHash, recoveryCodeHash, 1, 'admin']
      );
    }

    const user = {
      id: userId,
      username,
      display_name: displayName,
      role: 'admin',
      auth_version: (existingAdmin?.auth_version || 0) + 1
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
  if (!resolveSetupResetEnabled(process.env)) return res.sendStatus(404);
  return next();
}, authenticateToken, requireAdmin, (req, res) => {
  const { confirm } = req.body || {};
  if (confirm !== true) {
    return res.status(400).json({ error: 'Confirmação explícita necessária para redefinir a instalação local.' });
  }

  resetLocalDatabase();
  res.json({ message: 'Instalação local redefinida com sucesso.' });
});
