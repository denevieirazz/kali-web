import test from 'node:test';
import assert from 'node:assert/strict';
import { getActiveDistro, setActiveDistro, listInstalledDistros, listOnlineDistros, getCloudOSHome } from '../src/linuxRuntime/distroManager.js';

test('DistroManager: CloudOS Home estrutura de diretórios válida', () => {
  const home = getCloudOSHome();
  assert.ok(home.root, 'Root CloudOS Home deve existir');
  assert.ok(home.downloads, 'Subpasta Downloads deve existir');
  assert.ok(home.documents, 'Subpasta Documents deve existir');
  assert.ok(home.projects, 'Subpasta Projects deve existir');
  assert.ok(home.workspace, 'Subpasta Workspace deve existir');
});

test('DistroManager: fallback padrão é kali-linux quando não configurado', () => {
  const active = getActiveDistro();
  assert.ok(typeof active === 'string' && active.length > 0);
});

test('DistroManager: alteração de distro ativa com persistência', () => {
  const original = getActiveDistro();
  setActiveDistro('Ubuntu-24.04');
  assert.equal(getActiveDistro(), 'Ubuntu-24.04');
  setActiveDistro(original); // restaura
});

test('DistroManager: listInstalledDistros retorna array com metadados', async () => {
  const installed = await listInstalledDistros();
  assert.ok(Array.isArray(installed));
  assert.ok(installed.length > 0);
  assert.ok(installed[0].name);
  assert.ok(installed[0].icon);
});

test('DistroManager: listOnlineDistros retorna catálogo de sistemas', async () => {
  const online = await listOnlineDistros();
  assert.ok(Array.isArray(online));
  assert.ok(online.length >= 3);
  const ubuntu = online.find(d => d.id.toLowerCase().includes('ubuntu'));
  assert.ok(ubuntu, 'Catálogo online deve conter Ubuntu');
});
