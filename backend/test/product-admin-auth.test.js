import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const routes = fs.readFileSync(path.resolve(here, '../src/product/routes.js'), 'utf8');

test('cache, diagnostics export and host-folder open require administrator role', () => {
  assert.match(routes, /router\.post\('\/cache\/clear', requireAdmin,/);
  assert.match(routes, /router\.post\('\/diagnostics\/export', requireAdmin,/);
  assert.match(routes, /router\.post\('\/folder\/:kind\/open', requireAdmin,/);
});
