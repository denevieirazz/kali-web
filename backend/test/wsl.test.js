import test from 'node:test';
import assert from 'node:assert/strict';
import {
  classifyWslError,
  createInstallArgs,
  parseOnlineCatalogOutput,
  parseWslListOutput,
  parseWslVersionOutput,
  safeChildEnvironment
} from '../src/wsl/distroService.js';

test('WSL: interpreta distribuições, estado, versão e padrão sem consultar o host', () => {
  const parsed = parseWslListOutput(`
  NAME          STATE           VERSION
* kali-linux    Running         2
  Ubuntu Dev    Stopped         2
`);
  assert.deepEqual(parsed, [
    { name: 'kali-linux', state: 'Running', version: 2, isDefault: true },
    { name: 'Ubuntu Dev', state: 'Stopped', version: 2, isDefault: false }
  ]);
});

test('WSL: interpreta catálogo online e ignora cabeçalhos', () => {
  const parsed = parseOnlineCatalogOutput(`
The following is a list of valid distributions that can be installed.
Install using 'wsl.exe --install <Distro>'.

NAME                            FRIENDLY NAME
Ubuntu                          Ubuntu
Debian                          Debian GNU/Linux
kali-linux                      Kali Linux Rolling
`);
  assert.deepEqual(parsed, [
    { id: 'Ubuntu', name: 'Ubuntu' },
    { id: 'Debian', name: 'Debian GNU/Linux' },
    { id: 'kali-linux', name: 'Kali Linux Rolling' }
  ]);
});

test('WSL: interpreta versão localizada e WSLg', () => {
  const parsed = parseWslVersionOutput('Versão do WSL: 2.7.11.0\r\nVersão do kernel: 6.6.87.2\r\nVersão do WSLg: 1.0.73');
  assert.equal(parsed.wslVersion, '2.7.11.0');
  assert.equal(parsed.kernelVersion, '6.6.87.2');
  assert.equal(parsed.wslgVersion, '1.0.73');
});

test('WSL: classifica acesso negado sem confundir com instalação ausente', () => {
  assert.equal(classifyWslError('Código de erro: Wsl/EnumerateDistros/Service/E_ACCESSDENIED'), 'WSL_ACCESS_DENIED');
  assert.equal(classifyWslError('Acesso negado.'), 'WSL_ACCESS_DENIED');
});

test('WSL: builder aceita identificador simples e rejeita injeção', () => {
  assert.deepEqual(createInstallArgs('kali-linux'), ['--install', '--distribution', 'kali-linux', '--no-launch']);
  assert.throws(() => createInstallArgs('kali-linux; calc.exe'), /inválido/);
  assert.throws(() => createInstallArgs('../../../cmd.exe'), /inválido/);
});

test('processos nativos não herdam segredos do agente', () => {
  const previous = process.env.CLOUDOS_TEST_API_TOKEN;
  process.env.CLOUDOS_TEST_API_TOKEN = 'nao-deve-vazar';
  try {
    const environment = safeChildEnvironment({ CLOUDOS: '1' });
    assert.equal(environment.CLOUDOS_TEST_API_TOKEN, undefined);
    assert.equal(environment.CLOUDOS, '1');
  } finally {
    if (previous === undefined) delete process.env.CLOUDOS_TEST_API_TOKEN;
    else process.env.CLOUDOS_TEST_API_TOKEN = previous;
  }
});
