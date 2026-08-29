import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildContainedWindowsAppArguments, buildIsolatedWindowsAppArguments } from '../src/apps/appCatalog.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const catalogSource = fs.readFileSync(path.resolve(here, '../src/apps/appCatalog.js'), 'utf8');
const FIRST_LAUNCH = 'a'.repeat(32);
const SECOND_LAUNCH = 'b'.repeat(32);
const CLOUDOS_ROOT = 'C:\\CloudOS';

test('Chromium-family launches receive distinct user-data directories per contained launch', () => {
  const browser = 'C:\\Program Files\\Chromium\\Application\\chrome.exe';
  const first = buildIsolatedWindowsAppArguments(browser, CLOUDOS_ROOT, FIRST_LAUNCH);
  const second = buildIsolatedWindowsAppArguments(browser, CLOUDOS_ROOT, SECOND_LAUNCH);
  assert.equal(first[0], `--user-data-dir=C:\\CloudOS\\profiles\\windows\\chrome.exe\\${FIRST_LAUNCH}`);
  assert.equal(second[0], `--user-data-dir=C:\\CloudOS\\profiles\\windows\\chrome.exe\\${SECOND_LAUNCH}`);
  assert.notEqual(first[0], second[0]);
});

test('Firefox launches receive distinct no-remote profiles per contained launch', () => {
  const browser = 'C:\\Program Files\\Mozilla Firefox\\firefox.exe';
  const first = buildIsolatedWindowsAppArguments(browser, CLOUDOS_ROOT, FIRST_LAUNCH);
  const second = buildIsolatedWindowsAppArguments(browser, CLOUDOS_ROOT, SECOND_LAUNCH);
  assert.equal(first[1], `C:\\CloudOS\\profiles\\windows\\firefox.exe\\${FIRST_LAUNCH}`);
  assert.equal(second[1], `C:\\CloudOS\\profiles\\windows\\firefox.exe\\${SECOND_LAUNCH}`);
  assert.ok(first.includes('-no-remote'));
  assert.ok(first.includes('-new-instance'));
  assert.notEqual(first[1], second[1]);
});

test('invalid browser isolation IDs fail closed instead of becoming profile paths', () => {
  const browser = 'C:\\Program Files\\Chromium\\Application\\chrome.exe';
  assert.deepEqual(buildIsolatedWindowsAppArguments(browser, CLOUDOS_ROOT, '..\\outside'), []);
  assert.throws(
    () => buildContainedWindowsAppArguments(browser, CLOUDOS_ROOT, ['https://example.test/'], '..\\outside'),
    (error) => error?.code === 'BROWSER_PROFILE_ISOLATION_UNAVAILABLE'
  );
});

test('browser launch without a valid CloudOS root fails closed', () => {
  const browser = 'C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe';
  assert.throws(
    () => buildContainedWindowsAppArguments(browser, '', [], FIRST_LAUNCH),
    (error) => error?.code === 'BROWSER_PROFILE_ISOLATION_UNAVAILABLE'
  );
});

test('production browser launch generates a fresh cryptographic isolation ID', () => {
  assert.match(catalogSource, /launchIsolationId\s*=\s*!scriptLaunch[\s\S]*?crypto\.randomBytes\(16\)\.toString\('hex'\)/);
  assert.match(catalogSource, /buildContainedWindowsAppArguments\([\s\S]*?catalogArguments,\s*launchIsolationId\s*\)/);
});
