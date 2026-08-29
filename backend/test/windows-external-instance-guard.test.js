import test from 'node:test';
import assert from 'node:assert/strict';
import {
  evaluateExternalInstanceProbe,
  hasExplicitPerLaunchInstanceIsolation,
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
    { pid: 101, path: 'C:\\Tools\\EDITOR.exe' },
    { pid: 102, path: 'D:\\Other\\Editor.exe' },
    { pid: 103, path: null },
    { pid: -1, path: executable }
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
});
