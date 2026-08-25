import test from 'node:test';
import assert from 'node:assert/strict';
import { parseWindowsAppDiscovery, parseWindowsShortcutArguments } from '../src/apps/appCatalog.js';

test('parser de argumentos Windows preserva limites argv convencionais e falha fechado', () => {
  assert.deepEqual(parseWindowsShortcutArguments('--profile "Profile 1" --safe'), ['--profile', 'Profile 1', '--safe']);
  assert.deepEqual(parseWindowsShortcutArguments('"C:\\Path With Spaces\\file.txt" plain'), ['C:\\Path With Spaces\\file.txt', 'plain']);
  assert.deepEqual(parseWindowsShortcutArguments('"" --empty-ok'), ['', '--empty-ok']);
  assert.equal(parseWindowsShortcutArguments('"unterminated'), null);
  assert.equal(parseWindowsShortcutArguments('bad\nargument'), null);
});

test('catálogo Windows prefere atalhos descobertos com alvo rastreável', () => {
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
        Name: 'Browser com perfil',
        ShortcutPath: 'C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Browser.lnk',
        TargetPath: 'C:\\Program Files\\Browser\\Browser.exe',
        Arguments: '--profile "Profile 1" --safe'
      },
      {
        Name: 'Atalho com argumento inválido',
        ShortcutPath: 'C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Broken.lnk',
        TargetPath: 'C:\\Program Files\\Broken\\Broken.exe',
        Arguments: '"unterminated'
      },
      {
        Name: 'Script bloqueado',
        ShortcutPath: 'C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Script.lnk',
        TargetPath: 'C:\\Windows\\System32\\cmd.exe'
      },
      {
        Name: 'Automação GUI',
        ShortcutPath: 'C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Automacao.lnk',
        TargetPath: 'C:\\Tools\\LaunchGui.cmd'
      },
      {
        Name: 'Automação com argumentos crus',
        ShortcutPath: 'C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\AutomacaoArgs.lnk',
        TargetPath: 'C:\\Tools\\LaunchGui.bat',
        Arguments: '--unsafe raw arguments'
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
  assert.equal(apps.find((app) => app.name === 'Browser com perfil')?.kind, 'windows-shortcut-argv');
  assert.deepEqual(apps.find((app) => app.name === 'Browser com perfil')?.args, ['--profile', 'Profile 1', '--safe']);
  assert.equal(apps.find((app) => app.name === 'Atalho com argumento inválido')?.kind, 'windows-shortcut');
  assert.equal(apps.find((app) => app.name === 'Automação GUI')?.kind, 'windows-script-direct');
  assert.equal(apps.find((app) => app.name === 'Automação com argumentos crus')?.kind, 'windows-shortcut');
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

test('catálogo Windows rejeita caminhos que não sejam atalho e alvo suportado absolutos', () => {
  const apps = parseWindowsAppDiscovery({
    Shortcuts: [
      { Name: 'Relativo', ShortcutPath: '..\\Relativo.lnk', TargetPath: 'app.exe' },
      { Name: 'URL', ShortcutPath: 'C:\\Start\\Site.url', TargetPath: 'C:\\Browser.exe' },
      { Name: 'Documento', ShortcutPath: 'C:\\Start\\Doc.lnk', TargetPath: 'C:\\Doc.txt' },
      { Name: 'Script com expansão', ShortcutPath: 'C:\\Start\\BadScript.lnk', TargetPath: 'C:\\Tools\\100%done.cmd' }
    ]
  });
  assert.deepEqual(apps, []);
});
