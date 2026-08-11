import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import crypto from 'node:crypto';
import { createDatabaseForTests } from '../src/database/index.js';

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
