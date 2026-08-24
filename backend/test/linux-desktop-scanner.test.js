import test from 'node:test';
import assert from 'node:assert/strict';
import {
  expandDesktopExec,
  invalidateLinuxDesktopAppCache,
  parseDesktopEntry,
  parseLinuxDesktopDiscovery,
  readLinuxDesktopIcon,
  resolveLinuxDesktopApp,
  scanLinuxDesktopApps,
  toPublicLinuxDesktopApp,
  tokenizeDesktopExec
} from '../src/apps/linuxDesktopScanner.js';

const DISTRO = 'Kali Test';

function fixtureRecord({
  desktopId = 'org.example.Editor.desktop',
  desktopFile = '/home/test/.local/share/applications/org.example.Editor.desktop',
  content,
  tryExecAvailable = null
}) {
  return {
    desktopId,
    desktopFile,
    contentBase64: Buffer.from(content, 'utf8').toString('base64'),
    tryExecAvailable
  };
}

const EDITOR_DESKTOP = `[Desktop Entry]
Type=Application
Name=Example Editor
Name[pt]=Editor Exemplo
Name[pt_BR]=Editor de Texto Exemplo
GenericName[pt_BR]=Editor de arquivos
Comment=Edit files
Comment[pt_BR]=Edite\\sarquivos
Keywords=editor;text;
Keywords[pt_BR]=editor;texto;anotações;
Exec=/opt/example/bin/editor --new-window %F --title "%c" --desktop=%k %%
TryExec=/opt/example/bin/editor
Icon=org.example.Editor
Terminal=false
Categories=Utility;TextEditor;
MimeType=text/plain;application/json;
`;

test('Desktop Entry usa localização, metadados e categoria padronizada sem catálogo manual', () => {
  const app = parseDesktopEntry(EDITOR_DESKTOP, {
    distribution: DISTRO,
    desktopId: 'org.example.Editor.desktop',
    desktopFile: '/usr/share/applications/org.example.Editor.desktop',
    locale: 'pt_BR.UTF-8',
    tryExecAvailable: true
  });

  assert.ok(app);
  assert.equal(app.name, 'Editor de Texto Exemplo');
  assert.equal(app.genericName, 'Editor de arquivos');
  assert.equal(app.comment, 'Edite arquivos');
  assert.deepEqual(app.keywords, ['editor', 'texto', 'anotações']);
  assert.deepEqual(app.categories, ['Utility', 'TextEditor']);
  assert.equal(app.category, 'utilities');
  assert.deepEqual(app.mimeTypes, ['text/plain', 'application/json']);
  assert.equal(app.iconName, 'org.example.Editor');
  assert.equal(app.terminal, false);
  assert.equal(app.launchMode, 'xpra-contained');
  assert.match(app.id, /^linux-[a-f0-9]{32}$/);
});

test('Exec vira argv e metacaracteres nunca são interpretados como shell', () => {
  const template = tokenizeDesktopExec('editor "a;$(touch /tmp/pwn)" %F %i --name=%c %%');
  const argv = expandDesktopExec(template, {
    name: 'Meu Editor',
    icon: 'editor-icon',
    files: ['/tmp/um arquivo.txt', '/tmp/dois.txt']
  });

  assert.deepEqual(argv, [
    'editor',
    'a;$(touch /tmp/pwn)',
    '/tmp/um arquivo.txt',
    '/tmp/dois.txt',
    '--icon',
    'editor-icon',
    '--name=Meu Editor',
    '%'
  ]);
  assert.throws(() => tokenizeDesktopExec('editor "sem fim'), /Aspas não finalizadas/u);
  assert.throws(() => expandDesktopExec(['editor', '%Z']), /Código de campo/u);
  assert.throws(() => expandDesktopExec(['editor', 'prefix-%F']), /não pode ser combinado/u);
});

test('filtros respeitam Type, Hidden, NoDisplay e TryExec', () => {
  const base = {
    distribution: DISTRO,
    desktopId: 'fixture.desktop',
    desktopFile: '/usr/share/applications/fixture.desktop'
  };
  assert.equal(parseDesktopEntry('[Desktop Entry]\nType=Link\nName=Link\nExec=link', base), null);
  assert.equal(parseDesktopEntry('[Desktop Entry]\nType=Application\nHidden=true\nName=X\nExec=x', base), null);
  assert.equal(parseDesktopEntry('[Desktop Entry]\nType=Application\nNoDisplay=true\nName=X\nExec=x', base), null);
  assert.equal(parseDesktopEntry('[Desktop Entry]\nType=Application\nName=X\nExec=x\nTryExec=x', {
    ...base,
    tryExecAvailable: false
  }), null);
});

test('ID é estável, depende da distribuição e precedência XDG preserva tombstone Hidden', () => {
  const userHidden = fixtureRecord({
    content: '[Desktop Entry]\nType=Application\nName=Oculto\nExec=oculto\nHidden=true\n'
  });
  const systemVisible = fixtureRecord({
    desktopFile: '/usr/share/applications/org.example.Editor.desktop',
    content: EDITOR_DESKTOP,
    tryExecAvailable: true
  });
  assert.deepEqual(parseLinuxDesktopDiscovery([userHidden, systemVisible], { distribution: DISTRO }), []);

  const first = parseLinuxDesktopDiscovery([systemVisible], { distribution: DISTRO, locale: 'pt_BR' })[0];
  const same = parseLinuxDesktopDiscovery([systemVisible], { distribution: DISTRO, locale: 'en' })[0];
  const otherDistro = parseLinuxDesktopDiscovery([systemVisible], { distribution: 'Ubuntu', locale: 'pt_BR' })[0];
  assert.equal(first.id, same.id);
  assert.notEqual(first.id, otherDistro.id);
  assert.notEqual(first.id, 'org.example.Editor.desktop');
});

test('forma pública não expõe Exec, desktop path nem TryExec', () => {
  const app = parseLinuxDesktopDiscovery([
    fixtureRecord({ content: EDITOR_DESKTOP, tryExecAvailable: true })
  ], { distribution: DISTRO, locale: 'pt_BR' })[0];
  const publicApp = toPublicLinuxDesktopApp(app);

  assert.equal(publicApp.name, 'Editor de Texto Exemplo');
  assert.equal(publicApp.source, 'linux');
  assert.equal(publicApp.launchMode, 'xpra-contained');
  assert.match(publicApp.iconUrl, new RegExp(`${app.id}/icon`));
  for (const privateKey of ['launchArgv', 'execTemplate', 'desktopFile', 'desktopId', 'tryExec']) {
    assert.equal(Object.hasOwn(publicApp, privateKey), false, `${privateKey} não deve sair para o cliente`);
  }
  assert.equal(JSON.stringify(publicApp).includes('/opt/example/bin/editor'), false);
});

test('scanner usa WSL com argumentos separados, cacheia inclusive resultado e force atualiza', async () => {
  invalidateLinuxDesktopAppCache();
  let calls = 0;
  const record = fixtureRecord({ content: EDITOR_DESKTOP, tryExecAvailable: true });
  const execStub = async (executable, args, options) => {
    calls += 1;
    assert.equal(executable, 'wsl-test.exe');
    assert.deepEqual(args.slice(0, 4), ['--distribution', DISTRO, '--exec', 'python3']);
    assert.equal(args[4], '-c');
    assert.equal(typeof args[5], 'string');
    assert.equal(options.windowsHide, true);
    return { stdout: JSON.stringify([record]), stderr: '' };
  };

  const first = await scanLinuxDesktopApps(DISTRO, { execFileAsync: execStub, wslExecutable: 'wsl-test.exe' });
  const cached = await scanLinuxDesktopApps(DISTRO, { execFileAsync: execStub, wslExecutable: 'wsl-test.exe' });
  const refreshed = await scanLinuxDesktopApps(DISTRO, { execFileAsync: execStub, wslExecutable: 'wsl-test.exe', force: true });
  assert.equal(first.length, 1);
  assert.equal(cached[0].id, first[0].id);
  assert.equal(refreshed[0].id, first[0].id);
  assert.equal(calls, 2);
});

test('lookup só aceita ID opaco e ícone é lido pelo nome interno sem caminho fornecido pelo cliente', async () => {
  invalidateLinuxDesktopAppCache();
  const record = fixtureRecord({ content: EDITOR_DESKTOP, tryExecAvailable: true });
  const scanStub = async () => ({ stdout: JSON.stringify([record]), stderr: '' });
  const apps = await scanLinuxDesktopApps(DISTRO, { execFileAsync: scanStub, wslExecutable: 'wsl-test.exe', force: true });
  const found = await resolveLinuxDesktopApp(apps[0].id, DISTRO);
  assert.equal(found?.id, apps[0].id);
  assert.equal(await resolveLinuxDesktopApp('org.example.Editor.desktop', DISTRO), null);

  const iconBytes = Buffer.from('safe-icon');
  const iconStub = async (_executable, args) => {
    assert.deepEqual(args.slice(0, 5), ['--distribution', DISTRO, '--exec', 'python3', '-c']);
    assert.equal(args[6], 'org.example.Editor');
    return {
      stdout: JSON.stringify({
        path: '/usr/share/icons/hicolor/48x48/apps/org.example.Editor.png',
        mimeType: 'image/png',
        contentBase64: iconBytes.toString('base64')
      }),
      stderr: ''
    };
  };
  const icon = await readLinuxDesktopIcon(found, DISTRO, { execFileAsync: iconStub, wslExecutable: 'wsl-test.exe' });
  assert.equal(icon.mimeType, 'image/png');
  assert.deepEqual(icon.data, iconBytes);
});

