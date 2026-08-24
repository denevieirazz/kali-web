import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = path => fs.readFileSync(new URL(path, import.meta.url), 'utf8').replace(/\r\n?/g, '\n');
const registry = read('../src/core/appRegistry.ts');
const start = read('../src/components/StartMenu/StartMenu.tsx');
const workflowLaunch = read('../src/services/workflowLaunch.ts');
const hubClient = read('../src/services/systemHubClient.ts');
const hub = read('../src/apps/InstallLinux/InstallLinux.tsx');
const linuxSurface = read('../src/apps/LinuxAppWindow/LinuxAppWindow.tsx');

test('one source-aware registry reconciles discovered apps without deleting bundled apps', () => {
  assert.match(registry, /syncDiscoveredApps:/);
  assert.match(registry, /app\.catalogSource !== source/);
  assert.match(registry, /existing && !existing\.catalogSource/);
  assert.match(registry, /state\.apps\[app\.id\]\?\.catalogSource/);
  assert.match(start, /refreshUnifiedAppRegistry/);
  assert.doesNotMatch(start, /\/api\/linux-runtime\/packages/);
  assert.doesNotMatch(start, /setLinuxApps/);
});

test('Start search indexes Desktop Entry metadata and exposes both operating-system origins', () => {
  for (const field of ['genericName', 'comment', 'keywords', 'categories', 'mimeTypes', 'distribution', 'catalogSource']) {
    assert.match(start, new RegExp(`app\\.${field}`));
  }
  assert.match(start, /Linux <b>\{userLinuxApps\.length\}/);
  assert.match(start, /Windows <b>\{windowsApps\.length\}/);
  assert.match(start, /Xpra/);
});

test('Linux launch can only create the embedded runner and its surface requires Xpra clientUrl', () => {
  assert.match(workflowLaunch, /createProcess\('linux-app-runner'/);
  assert.match(workflowLaunch, /appId: 'linux-app-runner'/);
  assert.match(workflowLaunch, /app\.launchMode !== 'xpra-contained'/);
  assert.match(linuxSurface, /!res\?\.session\?\.clientUrl \|\| res\.session\.mode !== 'xpra'/);
  assert.doesNotMatch(linuxSurface, /session\?\.native|WSLg|wslg/i);
});

test('Windows launch has no backend or external fallback when the managed host is unavailable', () => {
  assert.match(hubClient, /NATIVE_CONTAINMENT_REQUIRED/);
  assert.match(hubClient, /!host\.nativeHost \|\| !host\.managedWindows/);
  assert.doesNotMatch(hubClient, /apiClient<NativeLaunchResult>\(`\/api\/apps\/\$\{encodeURIComponent\(id\)\}\/launch/);
  assert.match(hub, /Windows estão bloqueados nesta sessão/);
  assert.match(hub, /Não existe fallback para WSLg, RAIL ou janela externa/);
  assert.doesNotMatch(hub, /foi aberto em uma janela nativa externa/);
});
