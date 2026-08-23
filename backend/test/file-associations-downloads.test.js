import test from 'node:test';
import assert from 'node:assert/strict';
import { scanDiscoveredLinuxApps } from '../src/linuxRuntime/desktopScanner.js';
import { listLinuxPackages } from '../src/linuxRuntime/packageManager.js';
import { startXpraPoc } from '../src/linuxRuntime/xpraPoc.js';

test('MIME extraction: .desktop scanner extrai MimeType com sucesso', async () => {
  const apps = await scanDiscoveredLinuxApps('kali-linux');
  assert.ok(Array.isArray(apps), 'Deve retornar lista de apps');
  const geany = apps.find(a => a.id === 'geany' || a.name.toLowerCase().includes('geany'));
  if (geany) {
    assert.ok(Array.isArray(geany.mimeTypes), 'geany deve conter array de mimeTypes');
  }
});

test('Package Manager: propaga mimeTypes e flags de curação', async () => {
  const result = await listLinuxPackages('kali-linux');
  assert.ok(result.operational, 'WSL deve estar operacional');
  assert.ok(Array.isArray(result.packages), 'Deve retornar pacotes');
  const userApp = result.packages.find(p => p.installed && p.isUserApp);
  assert.ok(userApp, 'Deve conter pelo menos um app de usuário instalado');
  assert.ok(Array.isArray(userApp.mimeTypes), 'Deve conter mimeTypes');
});
