import test from 'node:test';
import assert from 'node:assert/strict';
import { buildIsolatedWindowsAppArguments, buildWindowsScriptLaunchArguments, parseWindowsAppDiscovery, parseWindowsShortcutArguments } from '../src/apps/appCatalog.js';

test('launcher de script Windows preserva caminho com espaços sob cmd /s /c', () => {
  const scriptPath = 'C:\\Users\\Runner User\\CloudOS Fixtures\\Launch GUI.cmd';
  assert.deepEqual(
    buildWindowsScriptLaunchArguments(scriptPath),
    ['/d', '/s', '/v:off', '/c', 'call', scriptPath]
  );
});

test('navegadores conhecidos recebem perfil CloudOS isolado para não delegar à instância externa', () => {
  assert.deepEqual(
    buildIsolatedWindowsAppArguments('C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe', 'C:\\CloudOS'),
    ['--user-data-dir=C:\\CloudOS\\profiles\\windows\\brave.exe', '--no-first-run', '--new-window']
  );
  assert.deepEqual(
    buildIsolatedWindowsAppArguments('C:\\Program Files\\Mozilla Firefox\\firefox.exe', 'C:\\CloudOS'),
    ['-profile', 'C:\\CloudOS\\profiles\\windows\\firefox.exe', '-no-remote', '-new-instance']
  );
  assert.deepEqual(buildIsolatedWindowsAppArguments('C:\\Tools\\Editor.exe', 'C:\\CloudOS'), []);
});

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
  assert.equal(apps.find((app) => app.name === 'Editor Exemplo')?.runtimeClass, 'win32-direct-candidate');
  assert.equal(apps.find((app) => app.name === 'Browser com perfil')?.kind, 'windows-shortcut-argv');
  assert.deepEqual(apps.find((app) => app.name === 'Browser com perfil')?.args, ['--profile', 'Profile 1', '--safe']);
  assert.equal(apps.find((app) => app.name === 'Atalho com argumento inválido')?.kind, 'windows-shortcut');
  assert.equal(apps.find((app) => app.name === 'Atalho com argumento inválido')?.runtimeClass, 'win32-shortcut-unresolved');
  assert.equal(apps.find((app) => app.name === 'Automação GUI')?.kind, 'windows-script-direct');
  assert.equal(apps.find((app) => app.name === 'Automação com argumentos crus')?.kind, 'windows-shortcut');
  assert.equal(apps.find((app) => app.name === 'Calculadora')?.kind, 'windows-start-app');
  assert.equal(apps.find((app) => app.name === 'Calculadora')?.runtimeClass, 'brokered-start-app');
  assert.equal(apps.some((app) => app.name === 'Script bloqueado'), false);
  assert.equal(apps.filter((app) => app.name === 'Bloco de Notas do Windows').length, 1);
});

test('catálogo Windows usa target + argv como identidade de atalho', () => {
  const targetPath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
  const apps = parseWindowsAppDiscovery({
    Shortcuts: [
      {
        Name: 'Google Chrome',
        ShortcutPath: 'C:\\Start\\Chrome-A.lnk',
        TargetPath: targetPath,
        Arguments: '--profile=A'
      },
      {
        Name: 'Google Chrome',
        ShortcutPath: 'C:\\Start\\Chrome-B.lnk',
        TargetPath: targetPath,
        Arguments: '--profile=B'
      },
      {
        Name: 'Chrome A duplicado',
        ShortcutPath: 'C:\\Start\\Chrome-A-copy.lnk',
        TargetPath: targetPath,
        Arguments: '--profile=A'
      }
    ],
    StartApps: [
      { Name: 'Google Chrome', AppID: 'Google.Chrome' }
    ]
  });

  const chrome = apps.filter((app) => app.targetPath === targetPath);
  assert.equal(chrome.length, 2);
  assert.deepEqual(chrome.map((app) => app.args), [['--profile=A'], ['--profile=B']]);
  assert.deepEqual(chrome.map((app) => app.shortcutPath), ['C:\\Start\\Chrome-A.lnk', 'C:\\Start\\Chrome-B.lnk']);
  assert.equal(apps.some((app) => app.kind === 'windows-start-app' && app.name === 'Google Chrome'), false);
});

test('App Paths complementa o catálogo com executável direto sem duplicar atalho existente', () => {
  const editorPath = 'C:\\Program Files\\Editor\\Editor.exe';
  const toolsPath = 'C:\\Program Files\\Tools\\Tools.exe';
  const apps = parseWindowsAppDiscovery({
    Shortcuts: [
      {
        Name: 'Editor preferido',
        ShortcutPath: 'C:\\Start\\Editor.lnk',
        TargetPath: editorPath
      }
    ],
    AppPaths: [
      {
        Name: 'Editor.exe',
        Executable: editorPath,
        RegistryPath: 'HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\Editor.exe'
      },
      {
        Name: 'Tools',
        Executable: toolsPath,
        RegistryPath: 'HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\Tools.exe'
      },
      {
        Name: 'Tools duplicado',
        Executable: 'c:\\program files\\tools\\tools.exe',
        RegistryPath: 'HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\Tools.exe'
      }
    ],
    StartApps: [
      { Name: 'Tools', AppID: 'Vendor.Tools_abc!App' }
    ]
  });

  assert.equal(apps.filter((app) => app.kind === 'windows-executable').length, 1);
  const tools = apps.find((app) => app.kind === 'windows-executable');
  assert.equal(tools?.name, 'Tools');
  assert.equal(tools?.executable, toolsPath);
  assert.equal(tools?.workingDirectory, 'C:\\Program Files\\Tools');
  assert.deepEqual(tools?.args, []);
  assert.equal(tools?.discoverySource, 'registry-app-paths');
  assert.equal(tools?.runtimeClass, 'win32-direct-candidate');
  assert.equal(apps.filter((app) => app.name === 'Editor preferido').length, 1);
  assert.equal(apps.some((app) => app.name === 'Editor.exe'), false);
  assert.equal(apps.some((app) => app.kind === 'windows-start-app' && app.name === 'Tools'), false);
});

test('App Paths rejeita launchers perigosos e entradas que não sejam executável absoluto', () => {
  const apps = parseWindowsAppDiscovery({
    AppPaths: [
      { Name: 'PowerShell', Executable: 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe' },
      { Name: 'Explorer', Executable: 'C:\\Windows\\explorer.exe' },
      { Name: 'Painel de Controle', Executable: 'C:\\Windows\\System32\\control.exe' },
      { Name: 'Relativo', Executable: 'Tools.exe' },
      { Name: 'Documento', Executable: 'C:\\Tools\\readme.txt' },
      { Name: 'Quebra', Executable: 'C:\\Tools\\Bad\nApp.exe' },
      { Name: 'Seguro', Executable: 'C:\\Tools\\Safe.exe' }
    ]
  });

  assert.deepEqual(apps.map((app) => app.name), ['Seguro']);
  assert.equal(apps[0].kind, 'windows-executable');
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
