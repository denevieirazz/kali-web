import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = path => fs.readFileSync(new URL(path, import.meta.url), 'utf8');
const launcher = read('../../scripts/launch/start-cloudos.ps1');
const hostOptions = read('../../desktop/CloudOS.Host/HostOptions.cs');
const bootstrapReporter = read('../../desktop/CloudOS.Host/Runtime/BootstrapReporter.cs');
const bridge = read('../../desktop/CloudOS.Host/Bridge/WebMessageBridge.cs');

const has = (text, expression, message) => assert.match(text, expression, message);

test('RC Defect #001 makes Full startup observable instead of one silent compile state', () => {
  has(launcher, /\$script:FullLaunchStepCount = 11/);
  has(launcher, /launch-progress\.json/);
  has(launcher, /Write-CloudOSLaunchHeartbeat/);
  has(launcher, /Get-CloudOSFileUri/);
  has(launcher, /Logs desta sessão:/);

  for (const stage of [
    'prerequisites',
    'node-dependencies',
    'frontend-build',
    'host-restore',
    'host-build',
    'host-start',
    'host-window',
    'host-backend',
    'backend-health',
    'webview-shell',
    'ready',
  ]) has(launcher, new RegExp(`-Stage '${stage}'`));

  assert.doesNotMatch(launcher, /Compilando frontend e Host nativo antes do start desacoplado/);
});

test('RC Defect #001 separates frontend build, dotnet restore and host build with explicit timeouts', () => {
  has(launcher, /-Name 'frontend-build'[\s\S]*-TimeoutSeconds 300[\s\S]*-TimeoutCode 'FRONTEND_BUILD_TIMEOUT'/);
  has(launcher, /-Name 'host-restore'[\s\S]*@\('restore',\$hostProject,'--nologo'\)[\s\S]*-TimeoutCode 'HOST_RESTORE_TIMEOUT'/);
  has(launcher, /-Name 'host-build'[\s\S]*@\('build',\$hostProject,'-c','Release','--no-restore'/);
  has(launcher, /-TimeoutCode 'HOST_BUILD_TIMEOUT'/);
  has(launcher, /\.Kill\(\$true\)/);
  has(launcher, /frontend-build\.stderr\.log/);
  has(launcher, /host-restore\.stderr\.log/);
  has(launcher, /host-build\.stderr\.log/);
});

test('RC Defect #001 has bounded Host backend health and WebView2 waits', () => {
  has(launcher, /Wait-NativeHostWindow[\s\S]*TimeoutSeconds=45/);
  has(launcher, /Wait-NativeHostBackendRuntime[\s\S]*TimeoutSeconds=45/);
  has(launcher, /Wait-CloudOSHttpReadyVisible[\s\S]*TimeoutSeconds=20/);
  has(launcher, /Wait-NativeHostShellReady[\s\S]*TimeoutSeconds=60/);
  has(launcher, /NATIVE_HOST_SHELL_READINESS_TIMEOUT/);
  has(launcher, /hostPid=.*aguardando WebView2 \+ bridge\.handshake/);
});

test('RC Defect #001 reuses the existing Host bootstrap readiness protocol', () => {
  has(launcher, /'--bootstrap-pipe',\$bootstrapPipe\.name/);
  has(hostOptions, /case "--bootstrap-pipe":/);
  has(bootstrapReporter, /@event = "ready"/);
  has(bootstrapReporter, /pid = Environment\.ProcessId/);
  has(bridge, /case "bridge\.handshake":/);
  has(bridge, /if \(_onHandshake is not null\) await _onHandshake\(\)/);
  has(launcher, /shellHandshakeReady=\$true/);
  has(launcher, /CloudOS Full pronto: Host, backend e WebView2\/shell confirmados/);
});

test('RC Defect #001 always leaves an actionable final state', () => {
  has(launcher, /Write-CloudOSLaunchProgressRecord -Session \$session -Status 'completed'/);
  has(launcher, /Write-CloudOSLaunchProgressRecord -Session \$session -Status 'failed'/);
  has(launcher, /CloudOS não iniciou\./);
  has(launcher, /Etapa final:/);
  has(launcher, /Código técnico:/);
  has(launcher, /Abrir pasta de logs:/);
});
