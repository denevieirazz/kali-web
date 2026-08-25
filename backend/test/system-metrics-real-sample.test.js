import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const source = fs.readFileSync(path.resolve(here, '../src/system/routes.js'), 'utf8');

test('system metrics seed CPU counters instead of returning a fabricated first percentage', () => {
  assert.match(source, /let prevCpuInfo = readCpuTimes\(\)/);
  assert.doesNotMatch(source, /return 15/);
});

test('memory percentage handles an unavailable zero-sized memory sample', () => {
  assert.match(source, /totalMem > 0 \? Math\.round\(\(usedMem \/ totalMem\) \* 100\) : 0/);
});
