import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { probeProcessesByExecutableName } from '../src/apps/windowsExternalInstanceGuard.js';

const windowsOnly = process.platform === 'win32' ? {} : { skip: 'Windows-only process probe' };

test('Windows external instance probe returns exact current process identity', windowsOnly, async () => {
  const rows = await probeProcessesByExecutableName(process.execPath);
  const current = rows.find((row) => Number(row?.pid) === process.pid);

  assert.ok(current, `current Node PID ${process.pid} was not returned by the Windows process probe`);
  assert.equal(
    path.win32.normalize(String(current.path)).toLowerCase(),
    path.win32.normalize(process.execPath).toLowerCase()
  );
  assert.match(String(current.startTimeFileTimeUtc), /^[0-9]{1,20}$/);
  assert.ok(BigInt(current.startTimeFileTimeUtc) > 0n);
});
