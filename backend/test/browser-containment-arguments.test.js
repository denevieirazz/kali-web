import test from 'node:test';
import assert from 'node:assert/strict';
import { buildContainedWindowsAppArguments } from '../src/apps/appCatalog.js';

const CLOUDOS_ROOT = 'C:\\CloudOS';

test('atalho Chromium com argv preserva argumentos úteis e força perfil CloudOS', () => {
  const executable = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
  const args = buildContainedWindowsAppArguments(executable, CLOUDOS_ROOT, [
    '--profile-directory=Profile 1',
    'https://example.test/path'
  ]);

  assert.deepEqual(args, [
    '--user-data-dir=C:\\CloudOS\\profiles\\windows\\chrome.exe',
    '--no-first-run',
    '--new-window',
    '--profile-directory=Profile 1',
    'https://example.test/path'
  ]);
});

test('atalho Chromium não pode sobrescrever o user-data-dir contido', () => {
  const executable = 'C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe';
  const args = buildContainedWindowsAppArguments(executable, CLOUDOS_ROOT, [
    '--user-data-dir',
    'C:\\Users\\Host\\AppData\\Local\\BraveSoftware\\Brave-Browser\\User Data',
    '--user-data-dir=D:\\escape-profile',
    '--incognito',
    'https://example.test/'
  ]);

  assert.deepEqual(args, [
    '--user-data-dir=C:\\CloudOS\\profiles\\windows\\brave.exe',
    '--no-first-run',
    '--new-window',
    '--incognito',
    'https://example.test/'
  ]);
});

test('atalho Firefox não pode selecionar perfil externo ou Profile Manager', () => {
  const executable = 'C:\\Program Files\\Mozilla Firefox\\firefox.exe';
  const args = buildContainedWindowsAppArguments(executable, CLOUDOS_ROOT, [
    '-profile',
    'C:\\Users\\Host\\AppData\\Roaming\\Mozilla\\Firefox\\Profiles\\host.default',
    '-P',
    'default-release',
    '-ProfileManager',
    'https://example.test/'
  ]);

  assert.deepEqual(args, [
    '-profile',
    'C:\\CloudOS\\profiles\\windows\\firefox.exe',
    '-no-remote',
    '-new-instance',
    'https://example.test/'
  ]);
});

test('executável Windows comum mantém argv sem injetar perfil de navegador', () => {
  assert.deepEqual(
    buildContainedWindowsAppArguments('C:\\Tools\\Editor.exe', CLOUDOS_ROOT, ['--safe', 'document.txt']),
    ['--safe', 'document.txt']
  );
});
