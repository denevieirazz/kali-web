import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const routes = fs.readFileSync(path.resolve(here, '../src/wsl/routes.js'), 'utf8');

test('starting and stopping shared WSL distributions are administrator-only mutations', () => {
  assert.match(routes, /wslRouter\.post\('\/distributions\/:name\/start', requireAdmin,/);
  assert.match(routes, /wslRouter\.post\('\/distributions\/:name\/stop', requireAdmin,/);
});
