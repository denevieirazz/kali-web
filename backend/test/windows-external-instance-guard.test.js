import test from 'node:test';
import assert from 'node:assert/strict';
import {
  evaluateExternalInstanceProbe,
  hasExplicitPerLaunchInstanceIsolation,
  normalizeManagedProcessClaims,
  shouldGuardExternalInstanceHandoff
} from '../src/apps/windowsExternalInstanceGuard.js';

function launch(executable, args = [], launchKind = 'windows-executable') {
  return {
    launchKind,
    launchSpec: {
      executable,
      arguments: args,
      workingDirectory: 'C:\\CloudOS'
    }
  };
}

const TOKEN = 'a'.repeat(32);
const FIRST_START = '134171420000000000';
const SECOND_START = '134171420000000123';

test('per-launch Chromium profile is accepted as explicit instance isolation', () => {
  const item = launch(
    'C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
    [`--user-data-dir=C:\\CloudOS\\profiles\\windows\\brave.exe\\${TOKEN}`, '--no-first-run', '--new-window'],
    'windows-shortcut-argv'
  );
  assert.equal(hasExplicitPerLaunchInstanceIsolation(item), true);
  assert.equal(shouldGuardExternalInstanceHandoff(item), false);
});

test('shared Chromium profile is not sufficient to bypass singleton guard', () => {
  const item = launch(
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    ['--user-data-dir=C:\\CloudOS\\profiles\\windows\\chrome.exe', '--new-window']
  );
  assert.equal(hasExplicitPerLaunchInstanceIsolation(item), false);
  assert.equal(shouldGuardExternalInstanceHandoff(item), true);
});

test('Firefox requires tokenized profile plus no-remote and new-instance', () => {
  const isolated = launch(
    'C:\\Program Files\\Mozilla Firefox\\firefox.exe',
    ['-profile', `C:\\CloudOS\\profiles\\windows\\firefox.exe\\${TOKEN}`, '-no-remote', '-new-instance']
  );
  assert.equal(hasExplicitPerLaunchInstanceIsolation(isolated), true);
  assert.equal(shouldGuardExternalInstanceHandoff(isolated), false);

  const missingNoRemote = launch(
    'C:\\Program Files\\Mozilla Firefox\\firefox.exe',
    ['-profile', `C:\\CloudOS\\profiles\\windows\\firefox.exe\\${TOKEN}`, '-new-instance']
  );
  assert.equal(hasExplicitPerLaunchInstanceIsolation(missingNoRemote), false);
  assert.equal(shouldGuardExternalInstanceHandoff(missingNoRemote), true);
});

test('ordinary direct Win32 executable is guarded while script launch is outside this probe', () => {
  const editor = launch('C:\\Tools\\Editor.exe', ['document.txt']);
  assert.equal(shouldGuardExternalInstanceHandoff(editor), true);
  assert.equal(shouldGuardExternalInstanceHandoff({ ...editor, launchKind: 'windows-script-direct' }), false);
});

test('process probe conflicts only with same executable path and fails closed on unverifiable path', () => {
  const executable = 'C:\\Tools\\Editor.exe';
  const result = evaluateExternalInstanceProbe(executable, [
    { pid: 101, path: 'C:\\Tools\\EDITOR.exe', startTimeFileTimeUtc: FIRST_START },
    { pid: 102, path: 'D:\\Other\\Editor.exe', startTimeFileTimeUtc: FIRST_START },
    { pid: 103, path: null, startTimeFileTimeUtc: FIRST_START },
    { pid: -1, path: executable, startTimeFileTimeUtc: FIRST_START }
  ]);

  assert.deepEqual(result.conflicts, [
    { pid: 101, reason: 'same-executable' },
    { pid: 103, reason: 'path-unverifiable' }
  ]);
  assert.deepEqual(result.unrelated, [
    { pid: 102, path: 'd:\\other\\editor.exe' }
  ]);
  assert.deepEqual(result.unverifiable, [
    { pid: 103, reason: 'path-unverifiable' }
  ]);
  assert.deepEqual(result.managed, []);
});

test('exact Host-managed PID and creation time is excluded from external conflict', () => {
  const executable = 'C:\\Tools\\Editor.exe';
  const result = evaluateExternalInstanceProbe(
    executable,
    [{ pid: 201, path: executable, startTimeFileTimeUtc: FIRST_START }],
    [{ processId: 201, startTimeFileTimeUtc: FIRST_START }]
  );

  assert.deepEqual(result.conflicts, []);
  assert.deepEqual(result.managed, [
    { pid: 201, startTimeFileTimeUtc: FIRST_START }
  ]);
});

test('PID reuse cannot bypass external instance conflict', () => {
  const executable = 'C:\\Tools\\Editor.exe';
  const result = evaluateExternalInstanceProbe(
    executable,
    [{ pid: 202, path: executable, startTimeFileTimeUtc: SECOND_START }],
    [{ processId: 202, startTimeFileTimeUtc: FIRST_START }]
  );

  assert.deepEqual(result.managed, []);
  assert.deepEqual(result.conflicts, [{ pid: 202, reason: 'same-executable' }]);
});

test('unverifiable executable path remains a conflict even with an exact managed process claim', () => {
  const result = evaluateExternalInstanceProbe(
    'C:\\Tools\\Editor.exe',
    [{ pid: 203, path: null, startTimeFileTimeUtc: FIRST_START }],
    [{ processId: 203, startTimeFileTimeUtc: FIRST_START }]
  );

  assert.deepEqual(result.managed, []);
  assert.deepEqual(result.conflicts, [{ pid: 203, reason: 'path-unverifiable' }]);
});

test('managed process claims accept only exact decimal FILETIME strings', () => {
  assert.deepEqual(normalizeManagedProcessClaims([
    { processId: 301, startTimeFileTimeUtc: FIRST_START },
    { processId: 301, startTimeFileTimeUtc: FIRST_START },
    { processId: 302, startTimeFileTimeUtc: Number(FIRST_START) },
    { processId: 303, startTimeFileTimeUtc: '-1' },
    { processId: 304, startTimeFileTimeUtc: '9223372036854775808' },
    { processId: 0, startTimeFileTimeUtc: FIRST_START }
  ]), [
    { processId: 301, startTimeFileTimeUtc: FIRST_START }
  ]);
});
