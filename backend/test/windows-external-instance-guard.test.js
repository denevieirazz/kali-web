import test from 'node:test';
import assert from 'node:assert/strict';
import {
  evaluateExternalInstanceProbe,
  hasExplicitPerLaunchInstanceIsolation,
  shouldGuardExternalInstanceHandoff
} from '../src/apps/windowsExternalInstanceGuard.js';

function launch(executable, argumentsList = [], launchKind = 'windows-executable') {
  return {
    launchKind,
    launchSpec: {
      executable,
      arguments: argumentsList,
      workingDirectory: 'C:\\Program Files\\Example'
    }
  };
}

test('Win32 direto sem namespace isolado exige exclusividade do executável', () => {
  assert.equal(
    shouldGuardExternalInstanceHandoff(launch('C:\\Users\\User\\AppData\\Roaming\\Telegram Desktop\\Telegram.exe')),
    true
  );
  assert.equal(
    shouldGuardExternalInstanceHandoff(launch('C:\\Tools\\Editor.exe', [], 'windows-shortcut-direct')),
    true
  );
  assert.equal(
    shouldGuardExternalInstanceHandoff(launch('C:\\Windows\\System32\\cmd.exe', [], 'windows-script-direct')),
    false
  );
});

test('Chromium com profile aleatório por launch não é confundido com singleton externo', () => {
  const brave = launch(
    'C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
    [
      '--user-data-dir=C:\\CloudOS\\profiles\\windows\\brave.exe\\0123456789abcdef0123456789abcdef',
      '--no-first-run',
      '--new-window'
    ],
    'windows-shortcut-argv'
  );
  assert.equal(hasExplicitPerLaunchInstanceIsolation(brave), true);
  assert.equal(shouldGuardExternalInstanceHandoff(brave), false);

  const sharedProfile = launch(
    'C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
    ['--user-data-dir=C:\\CloudOS\\profiles\\windows\\brave.exe', '--new-window'],
    'windows-shortcut-argv'
  );
  assert.equal(hasExplicitPerLaunchInstanceIsolation(sharedProfile), false);
  assert.equal(shouldGuardExternalInstanceHandoff(sharedProfile), true);
});

test('Firefox só libera concorrência com profile aleatório, no-remote e new-instance', () => {
  const isolated = launch(
    'C:\\Program Files\\Mozilla Firefox\\firefox.exe',
    [
      '-profile',
      'C:\\CloudOS\\profiles\\windows\\firefox.exe\\fedcba9876543210fedcba9876543210',
      '-no-remote',
      '-new-instance'
    ],
    'windows-shortcut-argv'
  );
  assert.equal(hasExplicitPerLaunchInstanceIsolation(isolated), true);
  assert.equal(shouldGuardExternalInstanceHandoff(isolated), false);

  const missingNoRemote = launch(
    'C:\\Program Files\\Mozilla Firefox\\firefox.exe',
    [
      '-profile',
      'C:\\CloudOS\\profiles\\windows\\firefox.exe\\fedcba9876543210fedcba9876543210',
      '-new-instance'
    ],
    'windows-shortcut-argv'
  );
  assert.equal(hasExplicitPerLaunchInstanceIsolation(missingNoRemote), false);
  assert.equal(shouldGuardExternalInstanceHandoff(missingNoRemote), true);
});

test('probe considera o mesmo executável conflito por caminho completo case-insensitive', () => {
  const result = evaluateExternalInstanceProbe(
    'C:\\Users\\User\\AppData\\Roaming\\Telegram Desktop\\Telegram.exe',
    [
      { pid: 14448, path: 'c:\\users\\user\\appdata\\roaming\\telegram desktop\\TELEGRAM.EXE' },
      { pid: 20000, path: 'D:\\Portable\\Telegram.exe' }
    ]
  );
  assert.deepEqual(result.conflicts, [{ pid: 14448, reason: 'same-executable' }]);
  assert.equal(result.unrelated.length, 1);
  assert.equal(result.unrelated[0].pid, 20000);
});

test('probe falha fechado quando processo homônimo não expõe caminho verificável', () => {
  const result = evaluateExternalInstanceProbe(
    'C:\\Program Files\\Vendor\\App.exe',
    [{ pid: 3210, path: null }]
  );
  assert.deepEqual(result.conflicts, [{ pid: 3210, reason: 'path-unverifiable' }]);
  assert.deepEqual(result.unverifiable, [{ pid: 3210, reason: 'path-unverifiable' }]);
});

test('probe ignora linhas inválidas e executável homônimo em outro caminho', () => {
  const result = evaluateExternalInstanceProbe(
    'C:\\Program Files\\Vendor\\App.exe',
    [
      { pid: 0, path: 'C:\\Program Files\\Vendor\\App.exe' },
      { pid: 'not-a-pid', path: 'C:\\Program Files\\Vendor\\App.exe' },
      { pid: 99, path: 'D:\\Other Vendor\\App.exe' }
    ]
  );
  assert.deepEqual(result.conflicts, []);
  assert.deepEqual(result.unrelated, [{ pid: 99, path: 'd:\\other vendor\\app.exe' }]);
});
