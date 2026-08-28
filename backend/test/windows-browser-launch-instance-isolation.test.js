import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildIsolatedWindowsAppArguments, mergeIsolatedWindowsAppArguments } from '../src/apps/appCatalog.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const catalogSource = fs.readFileSync(path.resolve(here, '../src/apps/appCatalog.js'), 'utf8');
const FIRST_LAUNCH = 'a'.repeat(32);
const SECOND_LAUNCH = 'b'.repeat(32);

test('Chromium-family launches receive distinct user-data directories per contained Job launch', () => {
  const browser = 'C:\\Program Files\\Chromium\\Application\\chrome.exe';
  const first = buildIsolatedWindowsAppArguments(browser, 'C:\\CloudOS', FIRST_LAUNCH);
  const second = buildIsolatedWindowsAppArguments(browser, 'C:\\CloudOS', SECOND_LAUNCH);

  assert.equal(first[0], `--user-data-dir=C:\\CloudOS\\profiles\\windows\\chrome.exe\\${FIRST_LAUNCH}`);
  assert.equal(second[0], `--user-data-dir=C:\\CloudOS\\profiles\\windows\\chrome.exe\\${SECOND_LAUNCH}`);
  assert.notEqual(first[0], second[0]);
});

test('Firefox launches receive distinct locked profiles per contained Job launch', () => {
  const browser = 'C:\\Program Files\\Mozilla Firefox\\firefox.exe';
  const first = buildIsolatedWindowsAppArguments(browser, 'C:\\CloudOS', FIRST_LAUNCH);
  const second = buildIsolatedWindowsAppArguments(browser, 'C:\\CloudOS', SECOND_LAUNCH);

  assert.equal(first[1], `C:\\CloudOS\\profiles\\windows\\firefox.exe\\${FIRST_LAUNCH}`);
  assert.equal(second[1], `C:\\CloudOS\\profiles\\windows\\firefox.exe\\${SECOND_LAUNCH}`);
  assert.notEqual(first[1], second[1]);
});

test('invalid browser launch isolation IDs fail closed instead of becoming profile paths', () => {
  const browser = 'C:\\Program Files\\Chromium\\Application\\chrome.exe';
  assert.deepEqual(buildIsolatedWindowsAppArguments(browser, 'C:\\CloudOS', '..\\outside'), []);
  assert.throws(
    () => mergeIsolatedWindowsAppArguments(browser, 'C:\\CloudOS', ['https://example.com/'], '..\\outside'),
    (error) => error?.code === 'BROWSER_PROFILE_ISOLATION_UNAVAILABLE'
  );
});

test('production browser launch generates a fresh cryptographic isolation ID and passes it into argv merge', () => {
  assert.match(catalogSource, /launchIsolationId\s*=\s*!scriptLaunch[\s\S]*?crypto\.randomBytes\(16\)\.toString\('hex'\)/);
  assert.match(catalogSource, /mergeIsolatedWindowsAppArguments\([\s\S]*?catalogArguments,\s*launchIsolationId\s*\)/);
});
