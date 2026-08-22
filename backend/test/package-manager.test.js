import test from 'node:test';
import assert from 'node:assert/strict';
import { CURATED_LINUX_APPS, parsePackageStatuses } from '../src/linuxRuntime/packageManager.js';

test('CURATED_LINUX_APPS contains mandatory desktop applications', () => {
  const ids = CURATED_LINUX_APPS.map(a => a.id);
  assert.ok(ids.includes('firefox'), 'Firefox presente');
  assert.ok(ids.includes('chromium'), 'Chromium presente');
  assert.ok(ids.includes('code'), 'VS Code presente');
  assert.ok(ids.includes('gimp'), 'GIMP presente');
  assert.ok(ids.includes('vlc'), 'VLC presente');
  assert.ok(ids.includes('libreoffice'), 'LibreOffice presente');
  assert.ok(ids.includes('filezilla'), 'FileZilla presente');
  assert.ok(ids.includes('wireshark'), 'Wireshark presente');
});

test('parsePackageStatuses parses raw output deterministically', () => {
  const rawOutput = 'firefox-esr\x1f1\nchromium\x1f0\ncode\x1f1\n';
  const result = parsePackageStatuses(rawOutput);
  const ff = result.find(a => a.id === 'firefox');
  const chrome = result.find(a => a.id === 'chromium');
  const code = result.find(a => a.id === 'code');
  const gimp = result.find(a => a.id === 'gimp');

  assert.equal(ff?.installed, true);
  assert.equal(chrome?.installed, false);
  assert.equal(code?.installed, true);
  assert.equal(gimp?.installed, false);
});
