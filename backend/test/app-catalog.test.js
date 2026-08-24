import test from 'node:test';
import assert from 'node:assert/strict';
import { parseWindowsAppDiscovery } from '../src/apps/appCatalog.js';

test('catálogo Windows prefere atalhos descobertos com executável rastreável', () => {
  const existing = [{
    id: 'native-existing',
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
  }, existing);

  assert.equal(apps[0], existing[0]);
  assert.equal(apps.filter((app) => app.name === 'Editor Exemplo').length, 1);
  assert.equal(apps.find((app) => app.name === 'Editor Exemplo')?.kind, 'windows-shortcut-direct');
  assert.equal(apps.find((app) => app.name === 'Calculadora')?.kind, 'windows-start-app');
  assert.equal(apps.some((app) => app.name === 'Script bloqueado'), false);
  assert.equal(apps.filter((app) => app.name === 'Bloco de Notas do Windows').length, 1);
});

test('catálogo Windows ignora aliases WSLg para impedir bypass do Xpra', () => {
  const apps = parseWindowsAppDiscovery({
    WslDistributions: ['Ubuntu'],
    StartApps: [
      { Name: 'Firefox Linux', AppID: 'TheDebianProject.DebianGNULinux_xxx!firefox' },
      { Name: 'Ubuntu', AppID: 'CanonicalGroupLimited.Ubuntu_xxx!ubuntu' },
      { Name: 'Editor Windows', AppID: 'Vendor.Editor_xxx!App' },
    ],
  });

  assert.deepEqual(apps.map((app) => app.name), ['Editor Windows']);
  assert.equal(apps[0].source, 'windows');
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
