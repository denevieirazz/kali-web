import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { config } from '../config/index.js';

const USERNAME_PATTERN = /^[a-zA-Z0-9][a-zA-Z0-9._-]*$/;
const RECOVERY_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const RECOVERY_PREFIX = 'CLOUDOS';
const RECOVERY_GROUP_LENGTHS = Object.freeze([3, 4, 4, 4, 4, 4, 4, 4, 4]);
const RECOVERY_PAYLOAD_LENGTH = RECOVERY_GROUP_LENGTHS.reduce((total, length) => total + length, 0);
const RECOVERY_RANDOM_BITS = RECOVERY_PAYLOAD_LENGTH * 5;
const RECOVERY_MASK = (1n << BigInt(RECOVERY_RANDOM_BITS)) - 1n;
const READABLE_RECOVERY_PATTERN = /^CLOUDOS-[2-9A-HJ-NP-Z]{3}(?:-[2-9A-HJ-NP-Z]{4}){8}$/;
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
  if (typeof password !== 'string' || password.length < 4 || password.length > 128) {
    return { error: 'A senha deve conter entre 4 e 128 caracteres.' };
  }
  if (password !== confirmPassword) {
    return { error: 'A confirmação de senha não confere.' };
  }
  return { error: null };
}

function encodeReadableRecoveryPayload(bytes) {
  if (!bytes || bytes.length !== 22) throw new Error('RECOVERY_CODE_GENERATION_FAILED');
  let value = 0n;
  for (const byte of bytes) value = (value << 8n) | BigInt(byte);
  value &= RECOVERY_MASK;
  let output = '';
  for (let shift = BigInt(RECOVERY_RANDOM_BITS - 5); shift >= 0n; shift -= 5n) {
    output += RECOVERY_ALPHABET[Number((value >> shift) & 31n)];
  }
  if (output.length !== RECOVERY_PAYLOAD_LENGTH) throw new Error('RECOVERY_CODE_GENERATION_FAILED');
  return output;
}

function formatReadableRecoveryPayload(payload) {
  const groups = [];
  let offset = 0;
  for (const groupLength of RECOVERY_GROUP_LENGTHS) {
    groups.push(payload.slice(offset, offset + groupLength));
    offset += groupLength;
  }
  return `${RECOVERY_PREFIX}-${groups.join('-')}`;
}

export function generateRecoveryCode() {
  // 22 random bytes feed a 175-bit canonical code, encoded with an unambiguous 32-symbol alphabet.
  return formatReadableRecoveryPayload(encodeReadableRecoveryPayload(crypto.randomBytes(22)));
}

export function normalizeRecoveryCodeInput(value) {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  if (!trimmed || trimmed.length > 128) return '';

  const compact = trimmed.toUpperCase().replace(/[\s-]+/g, '');
  if (compact.startsWith(RECOVERY_PREFIX) && compact.length === RECOVERY_PREFIX.length + RECOVERY_PAYLOAD_LENGTH) {
    const payload = compact.slice(RECOVERY_PREFIX.length);
    if (/^[2-9A-HJ-NP-Z]{35}$/.test(payload)) return formatReadableRecoveryPayload(payload);
  }

  // Existing installations may still have the former base64url recovery code hashed.
  // Keep exact legacy input semantics so those users are not locked out.
  if (/^CLOUDOS-[A-Za-z0-9_-]{17,121}$/.test(trimmed)) return trimmed;
  return '';
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
  const normalized = normalizeRecoveryCodeInput(value);
  return Boolean(normalized && (READABLE_RECOVERY_PATTERN.test(normalized) || normalized.length >= 24));
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
