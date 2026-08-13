import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { pathToFileURL } from 'node:url';
import { createDatabaseForTests, DatabaseCorruptionError } from '../src/database/index.js';

test('persistência: usuário permanece após nova instância', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-db-'));
  const file = path.join(dir, 'db.json');
  const first = createDatabaseForTests(file);
  await new Promise((resolve, reject) => first.run(
    'INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?)',
    ['u1', 'Douglas', 'hash-seguro', 'admin'], error => error ? reject(error) : resolve()
  ));
  const second = createDatabaseForTests(file);
  const user = await new Promise((resolve, reject) => second.get(
    'SELECT * FROM users WHERE username = ?', ['douglas'],
    (error, row) => error ? reject(error) : resolve(row)
  ));
  assert.equal(user.username, 'Douglas');
  assert.equal(user.password_hash, 'hash-seguro');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('persistência: usuário duplicado é rejeitado', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-db-'));
  const db = createDatabaseForTests(path.join(dir, 'db.json'));
  const insert = username => new Promise(resolve => db.run(
    'INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?)',
    [crypto.randomUUID(), username, 'hash', 'admin'], error => resolve(error)
  ));
  assert.equal(await insert('Admin'), null);
  assert.equal((await insert('admin')).message, 'USERNAME_EXISTS');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('persistência: apenas um administrador pode ser criado mesmo com nomes diferentes', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-db-'));
  const db = createDatabaseForTests(path.join(dir, 'db.json'));
  const insert = username => new Promise(resolve => db.run(
    'INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?)',
    [crypto.randomUUID(), username, 'hash', 'admin'], error => resolve(error)
  ));
  assert.equal(await insert('AdminOne'), null);
  assert.equal((await insert('AdminTwo')).message, 'ADMIN_EXISTS');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('persistência: banco v1 é migrado sem perder identidade nem credenciais', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-db-migration-'));
  const file = path.join(dir, 'db.json');
  const originalV1 = JSON.stringify({
    version: 1,
    users: [{
      id: 'legacy-id',
      username: 'LegacyAdmin',
      password_hash: 'legacy-secure-hash',
      role: 'admin',
      created_at: '2026-01-01T00:00:00.000Z'
    }],
    operations: [{ id: 'legacy-operation', type: 'test' }]
  });
  fs.writeFileSync(file, originalV1);

  const db = createDatabaseForTests(file);
  const user = await new Promise((resolve, reject) => db.get(
    'SELECT * FROM users WHERE id = ?', ['legacy-id'],
    (error, row) => error ? reject(error) : resolve(row)
  ));
  assert.equal(user.id, 'legacy-id');
  assert.equal(user.username, 'LegacyAdmin');
  assert.equal(user.password_hash, 'legacy-secure-hash');
  assert.equal(user.display_name, 'LegacyAdmin');
  assert.equal(user.recovery_code_hash, null);
  assert.equal(user.auth_version, 1);

  const migrated = JSON.parse(fs.readFileSync(file, 'utf8'));
  assert.equal(migrated.version, 2);
  assert.equal(migrated.operations[0].id, 'legacy-operation');
  assert.equal(fs.existsSync(`${file}.bak`), true);
  assert.equal(fs.readFileSync(`${file}.pre-v2.bak`, 'utf8'), originalV1);

  fs.writeFileSync(`${file}.pre-v2.bak`, 'snapshot-original-imutavel');
  createDatabaseForTests(file);
  assert.equal(fs.readFileSync(`${file}.pre-v2.bak`, 'utf8'), 'snapshot-original-imutavel');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('persistência: migração restaurada de backup v1 preserva o snapshot original', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-db-backup-migration-'));
  const file = path.join(dir, 'db.json');
  const originalV1 = JSON.stringify({
    version: 1,
    users: [{ id: 'backup-legacy-id', username: 'BackupLegacy', password_hash: 'hash-legado', role: 'admin' }],
    operations: []
  });
  fs.writeFileSync(file, '{principal v1 corrompido');
  fs.writeFileSync(`${file}.bak`, originalV1);

  const restored = createDatabaseForTests(file);
  assert.equal(restored.state.version, 2);
  assert.equal(fs.readFileSync(`${file}.pre-v2.bak`, 'utf8'), originalV1);
  assert.equal(JSON.parse(fs.readFileSync(file, 'utf8')).users[0].id, 'backup-legacy-id');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('persistência: principal corrompido é restaurado do último backup válido', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-db-backup-'));
  const file = path.join(dir, 'db.json');
  const db = createDatabaseForTests(file);
  await new Promise((resolve, reject) => db.run(
    'INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?)',
    ['backup-user', 'BackupAdmin', 'hash-preservado', 'admin'],
    error => error ? reject(error) : resolve()
  ));

  fs.writeFileSync(file, '{arquivo principal corrompido');
  const restored = createDatabaseForTests(file);
  const user = await new Promise((resolve, reject) => restored.get(
    'SELECT * FROM users WHERE id = ?', ['backup-user'],
    (error, row) => error ? reject(error) : resolve(row)
  ));
  assert.equal(user.username, 'BackupAdmin');
  assert.equal(JSON.parse(fs.readFileSync(file, 'utf8')).users[0].id, 'backup-user');
  assert.ok(fs.readdirSync(dir).some(name => name.includes('.corrupt-')));
  fs.rmSync(dir, { recursive: true, force: true });
});

test('persistência: principal e backup inválidos falham fechados sem criar instalação vazia', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-db-corrupt-'));
  const file = path.join(dir, 'db.json');
  fs.writeFileSync(file, '{principal invalido');
  fs.writeFileSync(`${file}.bak`, '{backup invalido');
  assert.throws(
    () => createDatabaseForTests(file),
    error => error instanceof DatabaseCorruptionError && error.code === 'DATABASE_CORRUPT'
  );
  assert.equal(fs.readFileSync(file, 'utf8'), '{principal invalido');
  assert.equal(fs.readFileSync(`${file}.bak`, 'utf8'), '{backup invalido');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('persistência: bloqueio de recuperação sobrevive a nova instância', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-db-throttle-'));
  const file = path.join(dir, 'db.json');
  const first = createDatabaseForTests(file);
  const now = Date.now();
  for (let attempt = 0; attempt < 5; attempt += 1) {
    first.recordRecoveryFailure({ now: now + attempt, maxAttempts: 5, windowMs: 60_000, lockMs: 60_000 });
  }
  const second = createDatabaseForTests(file);
  const throttle = second.getRecoveryThrottle(now + 10);
  assert.equal(throttle.limited, true);
  assert.ok(throttle.retryAfterMs > 0);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('persistência: bloqueio de login sobrevive a nova instância sem dados de credencial', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-db-login-throttle-'));
  const file = path.join(dir, 'db.json');
  const first = createDatabaseForTests(file);
  const now = Date.now();
  for (let attempt = 0; attempt < 8; attempt += 1) {
    first.recordLoginFailure({ now: now + attempt, maxAttempts: 8, windowMs: 60_000, lockMs: 60_000 });
  }

  const second = createDatabaseForTests(file);
  const throttle = second.getLoginThrottle(now + 10);
  assert.equal(throttle.limited, true);
  assert.ok(throttle.retryAfterMs > 0);
  const storedLogin = JSON.parse(fs.readFileSync(file, 'utf8')).security.login;
  assert.deepEqual(Object.keys(storedLogin).sort(), ['failed_attempts', 'locked_until', 'window_started_at']);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('persistência: conta permanece após reinício real do processo do backend', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-db-process-'));
  const databaseModule = pathToFileURL(path.resolve('backend/src/database/index.js')).href;
  const environment = { ...process.env, NODE_ENV: 'test', CLOUDOS_DATA_DIR: dir };
  delete environment.DATABASE_PATH;

  const writer = spawnSync(process.execPath, ['--input-type=module', '--eval', `
    import { getDb } from ${JSON.stringify(databaseModule)};
    getDb().run(
      'INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?)',
      ['process-user', 'ProcessAdmin', 'process-hash', 'admin'],
      error => { if (error) throw error; }
    );
  `], { cwd: path.resolve('.'), env: environment, encoding: 'utf8', shell: false });
  assert.equal(writer.status, 0, writer.stderr);

  const reader = spawnSync(process.execPath, ['--input-type=module', '--eval', `
    import { getDb } from ${JSON.stringify(databaseModule)};
    getDb().get('SELECT * FROM users WHERE id = ?', ['process-user'], (error, user) => {
      if (error) throw error;
      if (!user) process.exitCode = 2;
      else process.stdout.write(user.username);
    });
  `], { cwd: path.resolve('.'), env: environment, encoding: 'utf8', shell: false });
  assert.equal(reader.status, 0, reader.stderr);
  assert.equal(reader.stdout, 'ProcessAdmin');
  fs.rmSync(dir, { recursive: true, force: true });
});
