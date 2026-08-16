import express from 'express';
import crypto from 'node:crypto';
import { getDb } from '../database/index.js';
import { config } from '../config/index.js';
import { authenticateToken, requireAdmin } from '../middleware/auth.js';
import { issueLegacyToken, consumeLegacyToken } from './legacyTokenStore.js';
import { hasNativeHostTrust } from './hostTrust.js';
import {
  generateRecoveryCode,
  hashPassword,
  hashRecoveryCode,
  normalizeRecoveryCodeInput,
  noStore,
  signSessionToken,
  toPublicUser,
  validRecoveryCodeInput,
  validateDisplayName,
  validatePassword,
  validateUsername,
  verifyPassword,
  verifyRecoveryCode
} from './security.js';

export const authRouter = express.Router();

const RECOVERY_ERROR = 'Não foi possível recuperar a conta com os dados informados.';
const LOGIN_ERROR = 'Credenciais inválidas.';

function dbGet(db, query, params) {
  return new Promise((resolve, reject) => db.get(query, params, (error, row) => error ? reject(error) : resolve(row)));
}

function rotateRecoveryCode(db, userId, recoveryCodeHash) {
  return new Promise((resolve, reject) => db.rotateRecoveryCode(
    userId,
    recoveryCodeHash,
    error => error ? reject(error) : resolve()
  ));
}

function enrollRecoveryCode(db, userId, recoveryCodeHash) {
  return new Promise((resolve, reject) => db.enrollRecoveryCode(
    userId,
    recoveryCodeHash,
    (error, enrolled) => error ? reject(error) : resolve(enrolled)
  ));
}

function recoverAdmin(db, credentials) {
  return new Promise((resolve, reject) => db.recoverAdmin(
    credentials,
    (error, user) => error ? reject(error) : resolve(user)
  ));
}

function clearLoginThrottle(db) {
  return new Promise((resolve, reject) => db.clearLoginThrottle(
    error => error ? reject(error) : resolve()
  ));
}

function loginLimitedResponse(res, throttle) {
  const retryAfterSeconds = Math.max(1, Math.ceil(throttle.retryAfterMs / 1000));
  noStore(res);
  res.set('Retry-After', String(retryAfterSeconds));
  return res.status(429).json({
    error: 'Não foi possível autenticar agora. Aguarde e tente novamente.'
  });
}

function loginFailureResponse(db, res) {
  const throttle = db.recordLoginFailure({
    maxAttempts: config.loginMaxAttempts,
    windowMs: config.loginWindowMs,
    lockMs: config.loginLockMs
  });
  if (throttle.limited) return loginLimitedResponse(res, throttle);
  noStore(res);
  return res.status(401).json({ error: LOGIN_ERROR });
}

function recoveryLimitedResponse(res, throttle) {
  const retryAfterSeconds = Math.max(1, Math.ceil(throttle.retryAfterMs / 1000));
  noStore(res);
  res.set('Retry-After', String(retryAfterSeconds));
  return res.status(429).json({
    error: 'Não foi possível concluir a recuperação agora. Aguarde e tente novamente.'
  });
}

function recoveryFailureResponse(db, res) {
  const throttle = db.recordRecoveryFailure({
    maxAttempts: config.recoveryMaxAttempts,
    windowMs: config.recoveryWindowMs,
    lockMs: config.recoveryLockMs
  });
  if (throttle.limited) return recoveryLimitedResponse(res, throttle);
  noStore(res);
  return res.status(401).json({ error: RECOVERY_ERROR });
}

// Login
authRouter.post('/login', async (req, res, next) => {
  try {
    const { username, password } = req.body || {};
    if (typeof username !== 'string' || !username.trim() || typeof password !== 'string' || !password) {
      return res.status(400).json({ error: 'Usuário e senha são obrigatórios.' });
    }

    const db = getDb();
    const currentThrottle = db.getLoginThrottle();
    if (currentThrottle.limited) return loginLimitedResponse(res, currentThrottle);

    const user = await dbGet(db, 'SELECT * FROM users WHERE username = ?', [username.trim()]);
    // A comparação com um hash sentinela reduz diferenças de tempo entre usuário ausente e senha incorreta.
    const isMatch = await verifyPassword(password, user?.password_hash);
    if (!user || !isMatch) return loginFailureResponse(db, res);

    await clearLoginThrottle(db);

    let recoveryCode;
    if (user.role === 'admin' && !user.recovery_code_hash) {
      const candidateRecoveryCode = generateRecoveryCode();
      const candidateHash = await hashRecoveryCode(candidateRecoveryCode);
      if (await enrollRecoveryCode(db, user.id, candidateHash)) recoveryCode = candidateRecoveryCode;
    }

    noStore(res);
    return res.json({
      message: 'Autenticado com sucesso.',
      token: signSessionToken(user),
      user: toPublicUser(user),
      ...(recoveryCode ? { recoveryCode, recoveryCodeShownOnce: true } : {})
    });
  } catch (error) {
    next(error);
  }
});

// Sessão atual
authRouter.get('/session', authenticateToken, (req, res) => {
  noStore(res);
  res.json({
    authenticated: true,
    user: {
      id: req.user.userId,
      userId: req.user.userId,
      username: req.user.username,
      displayName: req.user.displayName,
      role: req.user.role
    }
  });
});

// Logout (o token é removido pelo cliente; tokens antigos também são invalidados por authVersion após recuperação).
authRouter.post('/logout', authenticateToken, (_req, res) => {
  noStore(res);
  res.json({ message: 'Sessão encerrada com sucesso.' });
});

// Informa apenas se a recuperação foi preparada, sem revelar identificação da conta.
authRouter.get('/recovery/status', async (_req, res, next) => {
  try {
    const db = getDb();
    const admin = await dbGet(db, 'SELECT * FROM users WHERE role = ?', ['admin']);
    noStore(res);
    res.json({
      available: Boolean(admin?.recovery_code_hash),
      legacyAdmin: Boolean(admin && !admin.recovery_code_hash)
    });
  } catch (error) {
    next(error);
  }
});

// Redefine a única conta administradora usando somente o código de recuperação.
authRouter.post('/recovery/reset', async (req, res, next) => {
  try {
    const body = req.body || {};
    const checkedUsername = validateUsername(body.newUsername, { required: false });
    if (checkedUsername.error) return res.status(400).json({ error: checkedUsername.error });

    const checkedPassword = validatePassword(body.password, body.confirmPassword);
    if (checkedPassword.error) return res.status(400).json({ error: checkedPassword.error });

    if (body.displayName !== undefined) {
      const checkedDisplayName = validateDisplayName(body.displayName, checkedUsername.value || 'CloudOS');
      if (checkedDisplayName.error) return res.status(400).json({ error: checkedDisplayName.error });
    }

    const db = getDb();
    const currentThrottle = db.getRecoveryThrottle();
    if (currentThrottle.limited) return recoveryLimitedResponse(res, currentThrottle);

    const admin = await dbGet(db, 'SELECT * FROM users WHERE role = ?', ['admin']);
    const rawRecoveryCode = typeof body.recoveryCode === 'string' ? body.recoveryCode : '';
    const recoveryCode = normalizeRecoveryCodeInput(rawRecoveryCode);
    const inputIsValid = validRecoveryCodeInput(rawRecoveryCode);
    const recoveryMatches = await verifyRecoveryCode(
      inputIsValid ? recoveryCode : 'CLOUDOS-invalid-recovery-code',
      inputIsValid ? admin?.recovery_code_hash : null
    );
    if (!inputIsValid || !admin || !admin.recovery_code_hash || !recoveryMatches) {
      return recoveryFailureResponse(db, res);
    }

    const username = checkedUsername.value || admin.username;
    const checkedDisplayName = body.displayName === undefined
      ? { value: admin.display_name || username, error: null }
      : validateDisplayName(body.displayName, username);

    const nextRecoveryCode = generateRecoveryCode();
    const [passwordHash, recoveryCodeHash] = await Promise.all([
      hashPassword(body.password),
      hashRecoveryCode(nextRecoveryCode)
    ]);

    let updatedUser;
    try {
      updatedUser = await recoverAdmin(db, {
        id: admin.id,
        expectedRecoveryCodeHash: admin.recovery_code_hash,
        username,
        displayName: checkedDisplayName.value,
        passwordHash,
        recoveryCodeHash,
        authVersion: (Number(admin.auth_version) || 1) + 1
      });
    } catch (error) {
      if (['RECOVERY_CODE_CHANGED', 'USERNAME_EXISTS'].includes(error.message)) {
        return recoveryFailureResponse(db, res);
      }
      throw error;
    }

    noStore(res);
    return res.json({
      message: 'Conta recuperada com sucesso.',
      token: signSessionToken(updatedUser),
      user: toPublicUser(updatedUser),
      recoveryCode: nextRecoveryCode,
      recoveryCodeShownOnce: true
    });
  } catch (error) {
    next(error);
  }
});

// Gera um novo código para contas existentes; exige uma sessão administrativa válida.
authRouter.post('/recovery/rotate', authenticateToken, requireAdmin, async (req, res, next) => {
  try {
    const db = getDb();
    const recoveryCode = generateRecoveryCode();
    const recoveryCodeHash = await hashRecoveryCode(recoveryCode);
    await rotateRecoveryCode(db, req.user.userId, recoveryCodeHash);
    noStore(res);
    return res.json({
      message: 'Novo código de recuperação gerado com sucesso.',
      recoveryCode,
      recoveryCodeShownOnce: true
    });
  } catch (error) {
    next(error);
  }
});

// Emite token de uso único para recuperação legada; exige autorização do host nativo.
authRouter.post('/legacy-recovery/issue-token', async (req, res, next) => {
  try {
    if (!hasNativeHostTrust(req, req.app.locals.cloudOsHostTrustPolicy)) {
      return res.status(403).json({ error: 'Apenas o host nativo local pode solicitar o token de recuperação legada.' });
    }

    const db = getDb();
    const admin = await dbGet(db, 'SELECT * FROM users WHERE role = ?', ['admin']);
    if (!admin || admin.recovery_code_hash) {
      return res.status(400).json({ error: 'Nenhuma conta legada pendente de recuperação.' });
    }

    const tokenData = issueLegacyToken();
    noStore(res);
    return res.json(tokenData);
  } catch (error) {
    next(error);
  }
});

// Redefine a senha de conta antiga sem recovery_code_hash usando token emitido pelo host local.
authRouter.post('/legacy-recovery/reset', async (req, res, next) => {
  try {
    const body = req.body || {};
    const checkedUsername = validateUsername(body.newUsername, { required: false });
    if (checkedUsername.error) return res.status(400).json({ error: checkedUsername.error });

    const checkedPassword = validatePassword(body.password, body.confirmPassword);
    if (checkedPassword.error) return res.status(400).json({ error: checkedPassword.error });

    if (body.displayName !== undefined) {
      const checkedDisplayName = validateDisplayName(body.displayName, checkedUsername.value || 'CloudOS');
      if (checkedDisplayName.error) return res.status(400).json({ error: checkedDisplayName.error });
    }

    const db = getDb();
    const currentThrottle = db.getRecoveryThrottle();
    if (currentThrottle.limited) return recoveryLimitedResponse(res, currentThrottle);

    const admin = await dbGet(db, 'SELECT * FROM users WHERE role = ?', ['admin']);
    if (!admin || admin.recovery_code_hash) {
      return recoveryFailureResponse(db, res);
    }

    const legacyToken = typeof body.legacyToken === 'string'
      ? body.legacyToken.trim()
      : (typeof body.token === 'string' ? body.token.trim() : '');
    const tokenValid = consumeLegacyToken(legacyToken);
    if (!tokenValid) {
      return recoveryFailureResponse(db, res);
    }

    const username = checkedUsername.value || admin.username;
    const checkedDisplayName = body.displayName === undefined
      ? { value: admin.display_name || username, error: null }
      : validateDisplayName(body.displayName, username);

    const nextRecoveryCode = generateRecoveryCode();
    const [passwordHash, recoveryCodeHash] = await Promise.all([
      hashPassword(body.password),
      hashRecoveryCode(nextRecoveryCode)
    ]);

    let updatedUser;
    try {
      updatedUser = await new Promise((resolve, reject) => db.recoverLegacyAdmin({
        id: admin.id,
        username,
        displayName: checkedDisplayName.value,
        passwordHash,
        recoveryCodeHash,
        authVersion: (Number(admin.auth_version) || 1) + 1
      }, (error, user) => error ? reject(error) : resolve(user)));
    } catch (error) {
      if (['LEGACY_ADMIN_NOT_FOUND', 'USERNAME_EXISTS'].includes(error.message)) {
        return recoveryFailureResponse(db, res);
      }
      throw error;
    }

    // Registrar operação de auditoria sem gravar senhas, hashes ou tokens
    try {
      await new Promise((resolve) => db.run(
        'INSERT INTO operations (id, type, target, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [
          `op-${crypto.randomUUID()}`,
          'legacy-account-recovery',
          updatedUser.username,
          'completed',
          new Date().toISOString(),
          new Date().toISOString()
        ],
        () => resolve()
      ));
    } catch {}

    noStore(res);
    return res.json({
      message: 'Conta legada recuperada com sucesso.',
      token: signSessionToken(updatedUser),
      user: toPublicUser(updatedUser),
      recoveryCode: nextRecoveryCode,
      recoveryCodeShownOnce: true
    });
  } catch (error) {
    next(error);
  }
});