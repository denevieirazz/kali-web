import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const routes = fs.readFileSync(path.resolve(here, '../src/operations/routes.js'), 'utf8');

test('operation inventory and cancellation are guarded by administrator authentication', () => {
  assert.match(routes, /import \{ authenticateToken, requireAdmin \}/);
  assert.match(routes, /operationsRouter\.use\(authenticateToken, requireAdmin\)/);
});
