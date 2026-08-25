import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const source = fs.readFileSync(path.resolve(here, '../src/services/apiClient.ts'), 'utf8');

test('HTTP 403 is a permission denial and must not clear an otherwise valid session', () => {
  assert.doesNotMatch(source, /response\.status === 401 \|\| response\.status === 403/);
  assert.match(source, /if \(response\.status === 401\) handleUnauthorizedStatus\(response\.status\)/);
  assert.match(source, /if \(response\.status === 401 && !suppressUnauthorizedHandler\)/);
});
