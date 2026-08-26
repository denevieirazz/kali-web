import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeStartMenuCatalog, searchStartMenuCatalog } from '../src/components/StartMenu/startMenuCatalog.js';

test('menu Iniciar combina apps CloudOS, Windows e Linux sem IDs duplicados', () => {
  const result = mergeStartMenuCatalog(
    [{ id: 'settings', name: 'Configurações', icon: 'C' }],
    [
      { id: 'native-win', name: 'Bloco de Notas', icon: 'W', source: 'windows', distribution: null },
      { id: 'native-linux', name: 'Editor', icon: 'L', source: 'wsl', distribution: 'Ubuntu' },
      { id: 'settings', name: 'Duplicado', icon: 'X', source: 'windows', distribution: null },
    ],
  );

  assert.deepEqual(result.map((app) => app.id), ['settings', 'native-win', 'native-linux']);
  assert.equal(result[0].launcher, 'cloud');
  assert.equal(result[1].launcher, 'native');
  assert.equal(result[1].defaultWidth, 960);
});

test('menu substitui app nativo brokerado pela versão integrada do CloudOS', () => {
  const result = mergeStartMenuCatalog(
    [{ id: 'calculator', name: 'Calculadora', icon: '+' }],
    [{ id: 'native-calc', name: 'Calculadora do Windows', icon: 'W', source: 'windows', fallbackAppId: 'calculator' }],
  );
  assert.deepEqual(result.map((app) => app.id), ['calculator']);
});

test('pesquisa do Iniciar encontra plataforma, distribuição e texto sem acento', () => {
  const catalog = mergeStartMenuCatalog(
    [{ id: 'settings', name: 'Configurações', icon: 'C' }],
    [{ id: 'native-linux', name: 'Editor', icon: 'L', source: 'wsl', distribution: 'Ubuntu' }],
  );

  assert.deepEqual(searchStartMenuCatalog(catalog, 'configuracoes').map((app) => app.id), ['settings']);
  assert.deepEqual(searchStartMenuCatalog(catalog, 'linux').map((app) => app.id), ['native-linux']);
  assert.deepEqual(searchStartMenuCatalog(catalog, 'ubuntu').map((app) => app.id), ['native-linux']);
});
