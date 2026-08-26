import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { config } from '../config/index.js';

const USERNAME_PATTERN = /^[a-zA-Z0-9][a-zA-Z0-9._-]*$/;
const dummyPasswordHash = bcrypt.hashSync('CloudOS-dummy-password-2026', config.passwordBcryptRounds);
const dummyRecoveryHash = bcrypt.hashSync('CLOUDOS-dummy-recovery-code-2026', config.recoveryBcryptRounds);

export function validateUsername(value, { required = true } = {}) {
  if ((value === undefined || value === null || value === '') && !required) {
    return { value: null, error: null };
  }
  if (typeof value !== 'string') {
    return { value: null, error: 'O nome de usuário deve ser um texto válido.' };
  }
  const username = value.trim();
  if (username.length < 3 || username.length > 64) {
    return { value: null, error: 'O nome de usuário deve conter entre 3 e 64 caracteres.' };
  }
  if (!USERNAME_PATTERN.test(username)) {
    return { value: null, error: 'Use apenas letras, números, ponto, hífen ou sublinhado no nome de usuário.' };
  }
  return { value: username, error: null };
}

export function validateDisplayName(value, fallback) {
  if (value === undefined || value === null || value === '') {
    return { value: fallback, error: null };
  }
  if (typeof value !== 'string' || /[\u0000-\u001f\u007f]/.test(value)) {
    return { value: null, error: 'O nome de exibição contém caracteres inválidos.' };
  }
  const displayName = value.trim().replace(/\s+/g, ' ');
  if (displayName.length < 1 || displayName.length > 80) {
    return { value: null, error: 'O nome de exibição deve conter no máximo 80 caracteres.' };
  }
  return { value: displayName, error: null };
}

export function validatePassword(password, confirmPassword) {
  if (typeof password !== 'string' || password.length < 10 || password.length > 128) {
    return { error: 'A senha deve conter entre 10 e 128 caracteres.' };
  }
  if (password !== confirmPassword) {
    return { error: 'A confirmação de senha não confere.' };
  }
  return { error: null };
}

export function generateRecoveryCode() {
  return `CLOUDOS-${crypto.randomBytes(32).toString('base64url')}`;
}

export function hashPassword(password) {
  return bcrypt.hash(password, config.passwordBcryptRounds);
}

export function hashRecoveryCode(recoveryCode) {
  return bcrypt.hash(recoveryCode, config.recoveryBcryptRounds);
}

export function verifyPassword(password, passwordHash) {
  return bcrypt.compare(password, passwordHash || dummyPasswordHash);
}

export function verifyRecoveryCode(recoveryCode, recoveryCodeHash) {
  return bcrypt.compare(recoveryCode, recoveryCodeHash || dummyRecoveryHash);
}

export function validRecoveryCodeInput(value) {
  return typeof value === 'string' && value.length >= 24 && value.length <= 128;
}

export function toPublicUser(user) {
  return {
    id: user.id,
    username: user.username,
    displayName: user.display_name || user.username,
    role: user.role
  };
}

export function sessionClaims(user) {
  return {
    userId: user.id,
    username: user.username,
    displayName: user.display_name || user.username,
    role: user.role,
    authVersion: Number(user.auth_version) || 1
  };
}

export function signSessionToken(user) {
  return jwt.sign(sessionClaims(user), config.jwtSecret, { expiresIn: config.jwtExpiresIn });
}

export function noStore(res) {
  res.set('Cache-Control', 'no-store, max-age=0');
  res.set('Pragma', 'no-cache');
}
