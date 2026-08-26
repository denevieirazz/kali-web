import test from 'node:test';
import assert from 'node:assert/strict';
import { parseWindowsAppDiscovery } from '../src/apps/appCatalog.js';

test('catálogo Windows prefere atalhos com executável rastreável', () => {
  const curated = [{
    id: 'native-curated',
    name: 'Bloco de Notas do Windows',
    executable: 'C:\\Windows\\System32\\notepad.exe',
    source: 'windows'
  }];
  const apps = parseWindowsAppDiscovery({
    Shortcuts: [
      {
        Name: 'Editor Exemplo',
        ShortcutPath: 'C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Editor.lnk',
        TargetPath: 'C:\\Program Files\\Editor\\Editor.exe'
      },
      {
        Name: 'Script bloqueado',
        ShortcutPath: 'C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Script.lnk',
        TargetPath: 'C:\\Windows\\System32\\cmd.exe'
      },
      {
        Name: 'Bloco de Notas do Windows',
        ShortcutPath: 'C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Notepad.lnk',
        TargetPath: 'C:\\Windows\\System32\\notepad.exe'
      }
    ],
    StartApps: [
      { Name: 'Editor Exemplo', AppID: 'Vendor.Editor_abc!App' },
      { Name: 'Calculadora', AppID: 'Microsoft.WindowsCalculator_abc!App' }
    ]
  }, curated);

  assert.equal(apps[0], curated[0]);
  assert.equal(apps.filter((app) => app.name === 'Editor Exemplo').length, 1);
  assert.equal(apps.find((app) => app.name === 'Editor Exemplo')?.kind, 'windows-shortcut');
  assert.equal(apps.find((app) => app.name === 'Calculadora')?.kind, 'windows-start-app');
  assert.equal(apps.find((app) => app.name === 'Calculadora')?.fallbackAppId, 'calculator');
  assert.equal(apps.some((app) => app.name === 'Script bloqueado'), false);
  assert.equal(apps.filter((app) => app.name === 'Bloco de Notas do Windows').length, 1);
});

test('catálogo Windows deduplica atalhos por target + arguments e preserva perfis distintos', () => {
  const chrome = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
  const curated = [{
    id: 'native-chrome-default',
    name: 'Google Chrome',
    executable: chrome,
    args: [],
    source: 'windows'
  }];
  const apps = parseWindowsAppDiscovery({
    Shortcuts: [
      {
        Name: 'Chrome padrão duplicado',
        ShortcutPath: 'C:\\Start\\Chrome Default.lnk',
        TargetPath: chrome,
        Arguments: ''
      },
      {
        Name: 'Chrome Perfil A',
        ShortcutPath: 'C:\\Start\\Chrome A.lnk',
        TargetPath: chrome,
        Arguments: '--profile=A'
      },
      {
        Name: 'Chrome Perfil B',
        ShortcutPath: 'C:\\Start\\Chrome B.lnk',
        TargetPath: chrome,
        Arguments: '--profile=B'
      },
      {
        Name: 'Chrome Perfil A duplicado',
        ShortcutPath: 'C:\\Start\\Chrome A Copy.lnk',
        TargetPath: chrome,
        Arguments: '--profile=A'
      }
    ]
  }, curated);

  const shortcuts = apps.filter((app) => app.kind === 'windows-shortcut');
  assert.equal(shortcuts.length, 2);
  assert.deepEqual(shortcuts.map((app) => app.arguments), ['--profile=A', '--profile=B']);
  assert.notEqual(shortcuts[0].id, shortcuts[1].id);
  assert.equal(shortcuts[0].shortcutPath, 'C:\\Start\\Chrome A.lnk');
  assert.equal(shortcuts[1].shortcutPath, 'C:\\Start\\Chrome B.lnk');
  assert.equal(apps.some((app) => app.name === 'Chrome padrão duplicado'), false);
  assert.equal(apps.some((app) => app.name === 'Chrome Perfil A duplicado'), false);
});

test('catálogo marca Paint brokerado para bloqueio antes do lançamento', () => {
  const apps = parseWindowsAppDiscovery({
    Shortcuts: [{
      Name: 'Paint',
      ShortcutPath: 'C:\\Start\\Paint.lnk',
      TargetPath: 'C:\\Windows\\System32\\mspaint.exe'
    }]
  });
  assert.equal(apps[0].availability, 'blocked');
  assert.match(apps[0].blockedReason, /broker/i);
});

test('catálogo Windows rejeita caminhos que não sejam atalho e executável absolutos', () => {
  const apps = parseWindowsAppDiscovery({
    Shortcuts: [
      { Name: 'Relativo', ShortcutPath: '..\\Relativo.lnk', TargetPath: 'app.exe' },
      { Name: 'URL', ShortcutPath: 'C:\\Start\\Site.url', TargetPath: 'C:\\Browser.exe' },
      { Name: 'Documento', ShortcutPath: 'C:\\Start\\Doc.lnk', TargetPath: 'C:\\Doc.txt' }
    ]
  });
  assert.deepEqual(apps, []);
});
