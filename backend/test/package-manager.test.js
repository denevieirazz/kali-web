import test from 'node:test';
import assert from 'node:assert/strict';
import { CURATED_LINUX_APPS, parsePackageStatuses, getDistroFamily, resolvePackageNameForDistro, getCuratedAppsForDistro } from '../src/linuxRuntime/packageManager.js';

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

test('getDistroFamily identifies Linux distributions correctly', () => {
  assert.equal(getDistroFamily('Ubuntu'), 'ubuntu');
  assert.equal(getDistroFamily('Ubuntu-24.04'), 'ubuntu');
  assert.equal(getDistroFamily('kali-linux'), 'debian');
  assert.equal(getDistroFamily('Debian'), 'debian');
  assert.equal(getDistroFamily('FedoraLinux-44'), 'fedora');
  assert.equal(getDistroFamily('archlinux'), 'arch');
  assert.equal(getDistroFamily('openSUSE-Tumbleweed'), 'suse');
});

test('resolvePackageNameForDistro maps package names per distro family', () => {
  // Firefox
  assert.equal(resolvePackageNameForDistro('firefox', 'Ubuntu-24.04'), 'firefox');
  assert.equal(resolvePackageNameForDistro('firefox', 'Ubuntu'), 'firefox');
  assert.equal(resolvePackageNameForDistro('firefox', 'kali-linux'), 'firefox-esr');
  assert.equal(resolvePackageNameForDistro('firefox', 'Debian'), 'firefox-esr');
  assert.equal(resolvePackageNameForDistro('firefox', 'FedoraLinux-44'), 'firefox');
  assert.equal(resolvePackageNameForDistro('firefox', 'archlinux'), 'firefox');
  assert.equal(resolvePackageNameForDistro('firefox', 'openSUSE-Tumbleweed'), 'MozillaFirefox');

  // Chromium
  assert.equal(resolvePackageNameForDistro('chromium', 'Ubuntu-24.04'), 'chromium-browser');
  assert.equal(resolvePackageNameForDistro('chromium', 'kali-linux'), 'chromium');

  // x11-apps / xclock
  assert.equal(resolvePackageNameForDistro('xclock', 'Ubuntu-24.04'), 'x11-apps');
  assert.equal(resolvePackageNameForDistro('xclock', 'FedoraLinux-44'), 'xorg-x11-apps');
  assert.equal(resolvePackageNameForDistro('xclock', 'archlinux'), 'xorg-xclock');
});

test('getCuratedAppsForDistro customizes app details for Ubuntu vs Debian', () => {
  const ubuntuApps = getCuratedAppsForDistro('Ubuntu-24.04');
  const ubuntuFf = ubuntuApps.find(a => a.id === 'firefox');
  assert.equal(ubuntuFf?.packageName, 'firefox');
  assert.equal(ubuntuFf?.name, 'Mozilla Firefox');
  assert.ok(ubuntuFf?.command.startsWith('firefox '));

  const kaliApps = getCuratedAppsForDistro('kali-linux');
  const kaliFf = kaliApps.find(a => a.id === 'firefox');
  assert.equal(kaliFf?.packageName, 'firefox-esr');
  assert.equal(kaliFf?.name, 'Firefox ESR');
  assert.ok(kaliFf?.command.startsWith('firefox-esr '));
});

