import crypto from 'node:crypto';

const DEFAULT_TTL_MS = 3 * 60 * 1000; // 3 minutos
const tokens = new Map();

/**
 * Emite um token de recuperação legada curto, aleatório, de uso único e com expiração.
 */
export function issueLegacyToken({ ttlMs = DEFAULT_TTL_MS } = {}) {
  const randomPart = crypto.randomBytes(12).toString('hex').toUpperCase();
  const token = `LEGACY-${randomPart}`;
  const now = Date.now();
  tokens.set(token, {
    token,
    createdAt: now,
    expiresAt: now + ttlMs,
    used: false
  });
  return { token, expiresIn: Math.floor(ttlMs / 1000) };
}

/**
 * Consome o token de recuperação legada (uso único). Retorna true se for válido e não expirado.
 */
export function consumeLegacyToken(tokenString) {
  if (typeof tokenString !== 'string' || !tokenString.trim()) return false;
  const normalized = tokenString.trim();
  const entry = tokens.get(normalized);
  if (!entry) return false;
  if (entry.used) return false;
  if (Date.now() > entry.expiresAt) {
    tokens.delete(normalized);
    return false;
  }
  entry.used = true;
  tokens.delete(normalized);
  return true;
}

/**
 * Limpa todos os tokens em memória (para isolamento de testes).
 */
export function resetLegacyTokensForTests() {
  tokens.clear();
}
