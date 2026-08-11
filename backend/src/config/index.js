import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import dotenv from 'dotenv';

dotenv.config();

const isTest = process.env.NODE_ENV === 'test';
const defaultDataDir = isTest
  ? path.join(os.tmpdir(), `cloudos-unified-test-${process.pid}`)
  : path.resolve(process.cwd(), 'data');

const dataDir = path.resolve(process.env.CLOUDOS_DATA_DIR || defaultDataDir);
fs.mkdirSync(dataDir, { recursive: true });

function readOrCreateSecret() {
  if (process.env.JWT_SECRET) return process.env.JWT_SECRET;
  const secretPath = path.join(dataDir, '.jwt-secret');
  try {
    const current = fs.readFileSync(secretPath, 'utf8').trim();
    if (current.length >= 64) return current;
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const secret = crypto.randomBytes(48).toString('hex');
  const temporary = `${secretPath}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, `${secret}\n`, { encoding: 'utf8', mode: 0o600 });
  fs.renameSync(temporary, secretPath);
  return secret;
}

export const config = Object.freeze({
  port: Number.parseInt(process.env.PORT || '5000', 10),
  host: process.env.HOST || '127.0.0.1',
  corsOrigins: (process.env.CORS_ORIGIN || 'http://127.0.0.1:15173,http://localhost:15173')
    .split(',').map(value => value.trim()).filter(Boolean),
  jwtSecret: readOrCreateSecret(),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '2h',
  dataDir,
  databasePath: path.resolve(process.env.DATABASE_PATH || path.join(dataDir, 'cloudos.json')),
  allowedShells: process.platform === 'win32'
    ? ['powershell.exe', 'cmd.exe']
    : ['/bin/bash', '/bin/sh']
});
