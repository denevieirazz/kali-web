import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/apps/TaskManager/TaskManager.tsx', import.meta.url), 'utf8');

test('System Center does not display synthetic CPU/thread metrics', () => {
  assert.doesNotMatch(source, /3\.60\s*GHz/i);
  assert.doesNotMatch(source, /processes\.length\s*\*\s*4/);
  assert.doesNotMatch(source, /Commitada/i);
});

test('System Center consumes public kernel resource, service and driver APIs', () => {
  assert.match(source, /kernel\.resources/);
  assert.match(source, /kernel\.getAllServices\(\)/);
  assert.match(source, /kernel\.getAllDrivers\(\)/);
  assert.doesNotMatch(source, /kernel\._/);
});

test('destructive virtual process action remains blocked for the reserved system PID range', () => {
  assert.match(source, /isSystemProcess\(selectedVirtual\)/);
  assert.match(source, /terminateVirtual\(selectedVirtual\.pid\)/);
});