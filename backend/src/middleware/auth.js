import jwt from 'jsonwebtoken';
import { config } from '../config/index.js';
import { getDb } from '../database/index.js';
import { sessionClaims } from '../auth/security.js';

export async function verifySessionToken(token) {
  const payload = jwt.verify(token, config.jwtSecret);
  if (!payload || typeof payload !== 'object' || typeof payload.userId !== 'string') {
    throw new Error('INVALID_SESSION_PAYLOAD');
  }
  const user = await new Promise((resolve, reject) => {
    getDb().get('SELECT * FROM users WHERE id = ?', [payload.userId], (error, row) => {
      if (error) reject(error);
      else resolve(row);
    });
  });
  const tokenAuthVersion = Number(payload.authVersion ?? 1);
  const currentAuthVersion = Number(user?.auth_version ?? 1);
  if (!user || user.id !== payload.userId || user.username !== payload.username ||
      user.role !== payload.role || tokenAuthVersion !== currentAuthVersion) {
    throw new Error('SESSION_REVOKED');
  }
  return sessionClaims(user);
}

export async function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const match = typeof authHeader === 'string' ? authHeader.match(/^Bearer\s+([^\s]+)$/i) : null;
  const token = match?.[1];

  if (!token) {
    return res.status(401).json({ error: 'Token de autenticação não fornecido.' });
  }

  try {
    req.user = await verifySessionToken(token);
    next();
  } catch {
    return res.status(403).json({ error: 'Token inválido, expirado ou revogado.' });
  }
}

export function requireAdmin(req, res, next) {
  if (!req.user || req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Esta ação exige uma conta administradora do CloudOS.' });
  }
  next();
}

export function validateOrigin(req, res, next) {
  const origin = req.headers.origin;
  if (!origin) return next();

  if (config.corsOrigins.includes(origin) || origin.startsWith('http://localhost:') || origin.startsWith('http://127.0.0.1:')) {
    return next();
  }

  return res.status(403).json({ error: 'Origem não permitida pela política CORS.' });
}
