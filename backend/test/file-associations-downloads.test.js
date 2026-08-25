import test from 'node:test';
import assert from 'node:assert/strict';
import { parseDesktopEntry } from '../src/apps/linuxDesktopScanner.js';
import { listLinuxPackages } from '../src/linuxRuntime/packageManager.js';

test('MIME extraction reads every MimeType from an arbitrary Desktop Entry', () => {
  const app = parseDesktopEntry([
    '[Desktop Entry]',
    'Type=Application',
    'Name=Unplanned Editor',
    'Exec=unplanned-editor %F',
    'Categories=Utility;TextEditor;',
    'MimeType=text/plain;application/json;',
  ].join('\n'), {
    distribution: 'kali-linux',
    desktopId: 'unplanned-editor.desktop',
    desktopFile: '/usr/share/applications/unplanned-editor.desktop',
  });

  assert.deepEqual(app?.mimeTypes, ['text/plain', 'application/json']);
});

test('Package Manager propagates scanner metadata without a curated alias', async () => {
  const discovered = {
    id: 'linux-1234567890abcdef1234567890abcdef',
    desktopId: 'unplanned-editor.desktop',
    name: 'Unplanned Editor',
    argv: ['unplanned-editor'],
    category: 'utilities',
    categories: ['Utility', 'TextEditor'],
    comment: 'Editor fixture',
    iconName: 'accessories-text-editor',
    iconUrl: '/__cloudos/linux-runtime/apps/linux-1234567890abcdef1234567890abcdef/icon?distribution=kali-linux',
    mimeTypes: ['text/plain', 'application/json'],
    terminal: false,
  };

  const result = await listLinuxPackages('kali-linux', {
    getWslSnapshot: async () => ({ operational: true, distributions: [{ name: 'kali-linux' }] }),
    scanLinuxDesktopApps: async () => [discovered],
  });

  assert.deepEqual(result.packages.map((app) => app.id), [discovered.id]);
  assert.equal(result.packages[0].installed, true);
  assert.equal(result.packages[0].isDiscovered, true);
  assert.deepEqual(result.packages[0].mimeTypes, discovered.mimeTypes);
  assert.equal(result.packages[0].iconUrl, discovered.iconUrl);
});
