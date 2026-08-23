import test from 'node:test';
import assert from 'node:assert/strict';
import { scanDiscoveredLinuxApps } from '../src/linuxRuntime/desktopScanner.js';
import { listLinuxPackages } from '../src/linuxRuntime/packageManager.js';

test('MIME extraction: .desktop scanner extrai MimeType com sucesso', async () => {
  const apps = await scanDiscoveredLinuxApps('kali-linux');
  assert.ok(Array.isArray(apps), 'Deve retornar lista de apps');
  const geany = apps.find(a => a.id === 'geany' || a.name.toLowerCase().includes('geany'));
  if (geany) {
    assert.ok(Array.isArray(geany.mimeTypes), 'geany deve conter array de mimeTypes');
  }
});

test('Package Manager: propaga mimeTypes e flags de curação sem depender de WSL físico', async () => {
  const discoveredFirefox = {
    id: 'firefox-esr',
    desktopId: 'firefox-esr',
    name: 'Firefox ESR',
    command: 'firefox-esr',
    category: 'internet',
    categories: ['Network', 'WebBrowser'],
    comment: 'Browser fixture',
    iconName: 'firefox-esr',
    iconUrl: '/__cloudos/linux-runtime/icons/firefox-esr?distro=kali-linux',
    emojiFallback: '🦊',
    mimeTypes: ['text/html', 'application/xhtml+xml'],
    terminal: false,
    isUserApp: true,
    isTechnical: false,
  };

  const result = await listLinuxPackages('kali-linux', {
    getWslSnapshot: async () => ({
      installed: true,
      operational: true,
      preferred: 'kali-linux',
      default: 'kali-linux',
    }),
    scanDiscoveredLinuxApps: async () => [discoveredFirefox],
    execFileAsync: async () => ({ stdout: 'firefox-esr\x1f1\n', stderr: '' }),
  });

  assert.equal(result.operational, true);
  assert.ok(Array.isArray(result.packages), 'Deve retornar pacotes');

  const firefox = result.packages.find(p => p.id === 'firefox');
  assert.ok(firefox, 'Firefox curado deve continuar presente');
  assert.equal(firefox.installed, true, 'Alias firefox-esr deve marcar Firefox como instalado');
  assert.equal(firefox.isCurated, true);
  assert.equal(firefox.isUserApp, true);
  assert.equal(firefox.isTechnical, false);
  assert.deepEqual(firefox.mimeTypes, ['text/html', 'application/xhtml+xml']);
  assert.equal(firefox.iconUrl, discoveredFirefox.iconUrl);
  assert.equal(result.packages.filter(p => p.id === 'firefox-esr').length, 0, 'Alias descoberto não deve duplicar o app curado');
});
