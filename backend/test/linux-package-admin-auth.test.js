import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const appSource = fs.readFileSync(path.resolve(here, '../src/app.js'), 'utf8');

test('Linux package install and uninstall require an administrator session', () => {
  assert.match(appSource, /app\.post\('\/api\/linux-runtime\/packages\/:id\/install', authenticateToken, requireAdmin\)/);
  assert.match(appSource, /app\.post\('\/api\/linux-runtime\/packages\/:id\/uninstall', authenticateToken, requireAdmin\)/);
});
