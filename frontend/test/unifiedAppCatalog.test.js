import test from 'node:test';
import assert from 'node:assert/strict';
import { mapUnifiedCatalogApps } from '../src/services/unifiedAppCatalog.js';

const linuxId = 'linux-0123456789abcdef01234567';
const windowsId = 'native-abcdef0123456789abcdef01';

test('maps Linux and Windows inventory into one metadata-rich registry contract', () => {
  const apps = mapUnifiedCatalogApps({ apps: [
    {
      id: linuxId,
      name: 'L3afpad',
      source: 'linux',
      distribution: 'kali-linux',
      icon: '🐧',
      iconUrl: '/__cloudos/linux-runtime/icons/l3afpad?distro=kali-linux',
      comment: 'Simple text editor',
      keywords: ['text', 'editor'],
      categories: ['Utility', 'TextEditor'],
      mimeTypes: ['text/plain'],
      windowMode: 'xpra-contained',
      launchable: true,
      exec: 'l3afpad %F',
      desktopPath: '/usr/share/applications/l3afpad.desktop',
    },
    {
      id: windowsId,
      name: 'Windows Editor',
      source: 'windows',
      categories: ['Utility'],
      windowMode: 'native-managed',
      launchable: true,
      executable: 'C:\\private\\editor.exe',
    },
  ] });

  assert.equal(apps.length, 2);
  const linux = apps.find(app => app.id === linuxId);
  assert.equal(linux.catalogSource, 'linux');
  assert.equal(linux.launchMode, 'xpra-contained');
  assert.equal(linux.isLinux, true);
  assert.deepEqual(linux.keywords, ['text', 'editor']);
  assert.deepEqual(linux.mimeTypes, ['text/plain']);
  assert.equal(linux.category, 'office');
  assert.equal(Object.hasOwn(linux, 'exec'), false);
  assert.equal(Object.hasOwn(linux, 'desktopPath'), false);

  const windows = apps.find(app => app.id === windowsId);
  assert.equal(windows.catalogSource, 'windows');
  assert.equal(windows.launchMode, 'native-managed');
  assert.equal(windows.isNative, true);
  assert.equal(Object.hasOwn(windows, 'executable'), false);
});

test('normalizes legacy wsl source but fails closed on every uncontained launch mode', () => {
  const apps = mapUnifiedCatalogApps([
    { id: 'native-111111111111111111111111', name: 'Legacy Linux', source: 'wsl', windowMode: 'native-external' },
    { id: 'native-222222222222222222222222', name: 'Windows External', source: 'windows', windowMode: 'native-external' },
  ]);

  assert.equal(apps[0].source, 'linux');
  assert.equal(apps[0].launchMode, 'unavailable');
  assert.equal(apps[0].launchable, false);
  assert.equal(apps[1].launchMode, 'unavailable');
  assert.equal(apps[1].launchable, false);
});

test('rejects non-opaque IDs, unknown sources, duplicates and malformed names', () => {
  const apps = mapUnifiedCatalogApps({ apps: [
    { id: 'firefox', name: 'Unsafe raw command', source: 'linux', windowMode: 'xpra-contained' },
    { id: linuxId, name: 'Accepted', source: 'linux', windowMode: 'xpra-contained' },
    { id: linuxId, name: 'Duplicate', source: 'linux', windowMode: 'xpra-contained' },
    { id: 'native-999999999999999999999999', name: 'Unknown', source: 'remote', windowMode: 'native-managed' },
  ] });

  assert.deepEqual(apps.map(app => app.name), ['Accepted']);
});
