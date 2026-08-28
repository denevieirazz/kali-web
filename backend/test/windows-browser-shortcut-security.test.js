import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeIsolatedWindowsAppArguments } from '../src/apps/appCatalog.js';

test('Chromium-family shortcut cannot weaken CloudOS browser isolation or expose remote control', () => {
  const brave = 'C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe';
  const result = mergeIsolatedWindowsAppArguments(brave, 'C:\\CloudOS', [
    '--remote-debugging-port=9222',
    '--remote-debugging-address',
    '0.0.0.0',
    '--remote-allow-origins=*',
    '--no-sandbox',
    '--disable-gpu-sandbox',
    '--disable-web-security',
    '--ignore-certificate-errors',
    '--ignore-certificate-errors-spki-list',
    'deadbeef',
    '--allow-running-insecure-content',
    '--load-extension',
    'C:\\Temp\\Untrusted Extension',
    '--disable-extensions-except=C:\\Temp\\OnlyThis',
    '--incognito',
    'https://example.com/'
  ]);

  assert.deepEqual(result, [
    '--user-data-dir=C:\\CloudOS\\profiles\\windows\\brave.exe',
    '--no-first-run',
    '--new-window',
    '--incognito',
    'https://example.com/'
  ]);
  assert.equal(result.some((arg) => /remote-debugging|remote-allow-origins|no-sandbox|disable-gpu-sandbox|disable-web-security|ignore-certificate-errors|allow-running-insecure-content|load-extension|disable-extensions-except/i.test(arg)), false);
  assert.equal(result.includes('0.0.0.0'), false);
  assert.equal(result.includes('deadbeef'), false);
  assert.equal(result.includes('C:\\Temp\\Untrusted Extension'), false);
});

test('Firefox shortcut cannot replace profile or enable remote automation endpoints', () => {
  const firefox = 'C:\\Program Files\\Mozilla Firefox\\firefox.exe';
  const result = mergeIsolatedWindowsAppArguments(firefox, 'C:\\CloudOS', [
    '--start-debugger-server',
    '6000',
    '--marionette',
    '--remote-debugging-port=9222',
    '-P',
    'Personal',
    '--ProfileManager',
    '-private-window',
    'https://example.com/'
  ]);

  assert.deepEqual(result, [
    '-profile',
    'C:\\CloudOS\\profiles\\windows\\firefox.exe',
    '-no-remote',
    '-new-instance',
    '-private-window',
    'https://example.com/'
  ]);
  assert.equal(result.includes('6000'), false);
  assert.equal(result.includes('Personal'), false);
});

test('browser-specific sanitization never mutates arbitrary non-browser application argv', () => {
  const editor = 'C:\\Tools\\Editor.exe';
  const args = [
    '--remote-debugging-port=9222',
    '--no-sandbox',
    '--profile-directory=Workspace',
    'document.txt'
  ];
  assert.deepEqual(mergeIsolatedWindowsAppArguments(editor, 'C:\\CloudOS', args), args);
});
