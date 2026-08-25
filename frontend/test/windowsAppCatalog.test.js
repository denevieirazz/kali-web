import test from 'node:test';
import assert from 'node:assert/strict';
import { mapWindowsCatalogApps } from '../src/services/windowsAppCatalog.js';

test('maps only trusted opaque Windows catalog entries into Start-menu app definitions', () => {
  const apps = mapWindowsCatalogApps({
    apps: [
      { id: 'native-0123456789abcdef01234567', name: 'Notepad', source: 'windows', icon: '▤', executable: 'C:\\Windows\\notepad.exe' },
      { id: 'native-aaaaaaaaaaaaaaaaaaaaaaaa', name: 'Linux Tool', source: 'wsl', icon: '🐧' },
      { id: 'calculator', name: 'Bad ID', source: 'windows' },
      { id: 'native-0123456789abcdef01234567', name: 'Duplicate', source: 'windows' },
    ],
  });

  assert.equal(apps.length, 1);
  assert.equal(apps[0].id, 'native-0123456789abcdef01234567');
  assert.equal(apps[0].name, 'Notepad');
  assert.equal(apps[0].category, 'utilities');
  assert.equal(apps[0].isSingleInstance, false);
  assert.equal(Object.hasOwn(apps[0], 'executable'), false);
  assert.equal(Object.hasOwn(apps[0], 'targetPath'), false);
});

test('sorts Windows applications for the CloudOS Start menu and supplies a safe icon fallback', () => {
  const apps = mapWindowsCatalogApps([
    { id: 'native-bbbbbbbbbbbbbbbbbbbbbbbb', name: 'Zeta', source: 'windows', icon: '' },
    { id: 'native-cccccccccccccccccccccccc', name: 'Alpha', source: 'windows' },
  ]);

  assert.deepEqual(apps.map((app) => app.name), ['Alpha', 'Zeta']);
  assert.equal(apps[0].icon, '▦');
  assert.equal(apps[1].icon, '▦');
});
