import test from 'node:test';
import assert from 'node:assert/strict';
import {
  listLinuxPackages,
  mergeLinuxPackageCatalog,
  parsePackageStatuses,
  resolvePackageNameForDistro,
} from '../src/linuxRuntime/packageManager.js';

test('package names are never remapped through a manually curated catalog', () => {
  assert.equal(resolvePackageNameForDistro('l3afpad', 'kali-linux'), 'l3afpad');
  assert.equal(resolvePackageNameForDistro('firefox', 'Ubuntu-24.04'), 'firefox');
  assert.equal(resolvePackageNameForDistro('bad; touch /tmp/pwned', 'kali-linux'), '');
});

test('dynamic package view is derived only from discovered desktop entries', () => {
  const packages = mergeLinuxPackageCatalog([{
    id: 'linux-0123456789abcdef01234567',
    desktopId: 'l3afpad.desktop',
    name: 'L3afpad',
    argv: ['l3afpad'],
    categories: ['Utility', 'TextEditor'],
    comment: 'Simple text editor',
    icon: 'accessories-text-editor',
    iconUrl: '/api/linux-runtime/apps/linux-0123456789abcdef01234567/icon',
    mimeTypes: ['text/plain'],
  }]);

  assert.equal(packages.length, 1);
  assert.equal(packages[0].name, 'L3afpad');
  assert.equal(packages[0].installed, true);
  assert.equal(packages[0].isDiscovered, true);
  assert.equal(packages[0].isPopular, false);
  assert.deepEqual(packages[0].mimeTypes, ['text/plain']);
});

test('listLinuxPackages returns the scanner result without adding pre-registered apps', async () => {
  const discovered = [{
    id: 'linux-fedcba9876543210fedcba98',
    desktopId: 'unexpected-editor.desktop',
    name: 'Unexpected Editor',
    argv: ['unexpected-editor'],
    categories: ['Utility'],
    mimeTypes: [],
  }];

  const result = await listLinuxPackages('kali-linux', {
    getWslSnapshot: async () => ({ operational: true, distributions: [{ name: 'kali-linux' }] }),
    scanDiscoveredLinuxApps: async () => discovered,
  });

  assert.equal(result.operational, true);
  assert.equal(result.totalDiscovered, 1);
  assert.deepEqual(result.packages.map((app) => app.name), ['Unexpected Editor']);
});

test('parsePackageStatuses remains a generic status parser', () => {
  const [app] = parsePackageStatuses('tool\x1f1\n', [{
    id: 'tool', name: 'Tool', packageName: 'tool', command: 'tool --flag',
    category: 'Utility', description: '', icon: 'T', desktopId: 'tool.desktop',
  }]);
  assert.equal(app.installed, true);
});
