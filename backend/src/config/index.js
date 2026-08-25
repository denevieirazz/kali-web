import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import dotenv from 'dotenv';

dotenv.config();

const isTest = process.env.NODE_ENV === 'test';
const testRoot = process.env.CLOUDOS_TEST_ROOT || os.tmpdir();
const defaultDataDir = isTest
  ? path.join(testRoot, `cloudos-unified-test-${process.pid}`)
  : path.resolve(process.cwd(), 'data');

const dataDir = path.resolve(process.env.CLOUDOS_DATA_DIR || defaultDataDir);
fs.mkdirSync(dataDir, { recursive: true });

const expectedNativeShellOrigin = 'https://cloudos.local';

export function resolveNativeShellOrigin(environment = process.env) {
  return environment.CLOUDOS_NATIVE_HOST === '1'
    && environment.CLOUDOS_TRUSTED_ORIGIN === expectedNativeShellOrigin
    ? expectedNativeShellOrigin
    : null;
}

export function resolveSetupResetEnabled(environment = process.env) {
  if (environment.CLOUDOS_NATIVE_HOST === '1') return false;
  if (environment.NODE_ENV === 'test') return true;
  if (environment.CLOUDOS_ALLOW_TEST_RESET === 'true' || environment.CLOUDOS_ALLOW_TEST_RESET === '1') return true;
  return environment.NODE_ENV === 'development'
    && environment.CLOUDOS_ALLOW_SETUP_RESET === '1';
}

const nativeShellOrigin = resolveNativeShellOrigin();

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
  nativeShellOrigin,
  jwtSecret: readOrCreateSecret(),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '2h',
  passwordBcryptRounds: isTest ? 4 : 12,
  recoveryBcryptRounds: isTest ? 4 : 12,
  recoveryMaxAttempts: 5,
  recoveryWindowMs: 15 * 60 * 1000,
  recoveryLockMs: 15 * 60 * 1000,
  loginMaxAttempts: 8,
  loginWindowMs: 10 * 60 * 1000,
  loginLockMs: 5 * 60 * 1000,
  setupResetEnabled: resolveSetupResetEnabled(),
  dataDir,
  databasePath: path.resolve(process.env.DATABASE_PATH || path.join(dataDir, 'cloudos.json')),
  allowedShells: process.platform === 'win32'
    ? ['powershell.exe', 'cmd.exe']
    : ['/bin/bash', '/bin/sh']
});
