import jwt from 'jsonwebtoken';
import { config } from '../config/index.js';

export function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Token de autenticação não fornecido.' });
  }

  jwt.verify(token, config.jwtSecret, (err, user) => {
    if (err) {
      return res.status(403).json({ error: 'Token inválido ou expirado.' });
    }
    req.user = user;
    next();
  });
}

export function validateOrigin(req, res, next) {
  const origin = req.headers.origin;
  if (!origin) return next();

  if (config.corsOrigins.includes(origin) || origin.startsWith('http://localhost:') || origin.startsWith('http://127.0.0.1:')) {
    return next();
  }

  return res.status(403).json({ error: 'Origem não permitida pela política CORS.' });
}
