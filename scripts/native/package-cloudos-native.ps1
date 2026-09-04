param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',
    [string]$BuildDirectory
)

$ErrorActionPreference = 'Stop'

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$out = Join-Path $rootPath "desktop\CloudOS.NativeShell\bin\$Configuration"
if ($BuildDirectory) { $out = (Resolve-Path -LiteralPath $BuildDirectory).Path }
$artifactDir = Join-Path $rootPath 'desktop\CloudOS.NativeShell\artifacts'
$stage = Join-Path $artifactDir 'CloudOS-Native-Release-x64'
$zip = Join-Path $artifactDir 'CloudOS-Native-Release-x64.zip'
$verify = Join-Path $PSScriptRoot 'verify-native-build-manifest.ps1'

& $verify -Root $rootPath -Configuration $Configuration -BuildDirectory $out -CheckSourceFingerprint

New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$payload = @(
    'CloudOS.exe',
    'CloudOS.NativeRuntime.dll',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe',
    'cloudos-native-manifest.json',
    '.cloudos-build-head',
    '.cloudos-build-fingerprint'
)
foreach ($name in $payload) {
    $source = Join-Path $out $name
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $stage $name) -Force
    }
}

foreach ($name in @(
    'native-health-v9.ps1',
    'collect-native-diagnostics.ps1',
    'get-cloudos-recovery-status-v22.ps1',
    'configure-cloudos-wer-v22.ps1',
    'run-native-soak-v9.ps1',
    'run-native-lifecycle-smoke-v10.ps1',
    'run-native-supervisor-smoke-v11.ps1',
    'run-native-supervisor-smoke-v22.ps1',
    'run-native-install-v22-smoke.ps1',
    'native-performance-v12.ps1',
    'run-native-performance-smoke-v12.ps1',
    'CloudOS.Deployment.V13.psm1',
    'CloudOS.HealthGate.V22.psm1',
    'CloudOS.ManagedTools.V22.psm1',
    'install-cloudos-native-v13.ps1',
    'install-cloudos-native-v22.ps1',
    'update-cloudos-native-v13.ps1',
    'rollback-cloudos-native-v13.ps1',
    'repair-cloudos-native-v13.ps1',
    'repair-cloudos-native-v22.ps1',
    'uninstall-cloudos-native-v13.ps1',
    'get-cloudos-deployment-status-v13.ps1',
    'start-cloudos-installed-v13.ps1',
    'CloudOS.ShellActivation.V14.psm1',
    'CloudOS.ShellEntry.V14.ps1',
    'activate-cloudos-shell-v14.ps1',
    'rollback-cloudos-shell-v14.ps1',
    'repair-cloudos-shell-v14.ps1',
    'get-cloudos-shell-status-v14.ps1',
    'run-native-shell-activation-smoke-v14.ps1',
    'run-system-broker-smoke-v21.ps1',
    'test-system-broker-v21-contract.ps1',
    'test-system-broker-v21-soak.ps1'
)) {
    $source = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Native validation/deployment package tool missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $stage $name) -Force
}

$manifestPath = Join-Path $stage 'cloudos-native-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Staged native manifest missing: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$sumLines = New-Object System.Collections.Generic.List[string]
foreach ($file in @('CloudOS.exe', 'CloudOS.NativeRuntime.dll', 'CloudOS.Supervisor.exe', 'CloudOS.SystemBroker.exe', 'CloudOS.BrokerProbe.exe')) {
    $path = Join-Path $stage $file
    if (-not (Test-Path -LiteralPath $path)) { throw "Staged native payload missing: $path" }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $sumLines.Add("$hash  $file")
}
Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Value $sumLines -Encoding ascii

$packageVerifier = @'
param([string]$Root = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$rootPath = (Resolve-Path -LiteralPath $Root).Path
$manifestPath = Join-Path $rootPath 'cloudos-native-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifesto ausente: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1 -or
    $manifest.product -ne 'CloudOS Native Shell' -or
    $manifest.shell_authority -ne 'C++/Win32' -or
    $manifest.recovery_authority -ne 'CloudOS.Supervisor.exe V11' -or
    [int]$manifest.supervisor_runtime_schema -ne 22 -or
    [int]$manifest.supervisor_compatibility_contract -ne 11 -or
    $manifest.broker_authority -ne 'CloudOS.SystemBroker.exe V21' -or
    $manifest.legacy_react_desktop -ne $false) {
    throw 'Manifesto do pacote CloudOS Native invalido.'
}
foreach ($name in @(
    'CloudOS.exe',
    'CloudOS.NativeRuntime.dll',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe'
)) {
    $records = @($manifest.files | Where-Object { $_.name -eq $name })
    if ($records.Count -ne 1) { throw "Registro de integridade invalido para $name" }
    $path = Join-Path $rootPath $name
    if (-not (Test-Path -LiteralPath $path)) { throw "Arquivo ausente: $name" }
    $item = Get-Item -LiteralPath $path
    if ($item.Length -le 0 -or [Int64]$records[0].size -ne [Int64]$item.Length) { throw "Tamanho invalido: $name" }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne ([string]$records[0].sha256).ToLowerInvariant()) { throw "SHA256 invalido: $name" }
}
if (Test-Path -LiteralPath (Join-Path $rootPath 'ui')) { throw 'Desktop web legado nao e permitido no pacote nativo.' }
Write-Host '[CloudOS] INTEGRITY_OK: Shell, Runtime, Supervisor V22 (ABI V11 compat), System Broker V21 e BrokerProbe conferem.'
'@
Set-Content -LiteralPath (Join-Path $stage 'Verificar Integridade.ps1') -Value $packageVerifier -Encoding utf8

$verifyLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%Verificar Integridade.ps1" -Root "%ROOT%"
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Verificar Integridade.cmd') -Value $verifyLauncher -Encoding ascii

$launcher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
if not exist "%ROOT%Verificar Integridade.ps1" exit /b 4
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%Verificar Integridade.ps1" -Root "%ROOT%"
if errorlevel 1 (
  echo [CloudOS] Integridade do pacote FALHOU. O shell nao sera iniciado.
  exit /b 5
)
if not exist "%ROOT%CloudOS.Supervisor.exe" exit /b 7
pushd "%ROOT%" >nul
start "CloudOS Supervisor V22" /D "%ROOT%" "%ROOT%CloudOS.Supervisor.exe"
set "RC=%ERRORLEVEL%"
popd >nul
exit /b %RC%
'@
Set-Content -LiteralPath (Join-Path $stage 'Iniciar CloudOS.cmd') -Value $launcher -Encoding ascii

$recoveryLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
if not exist "%ROOT%CloudOS.Supervisor.exe" exit /b 7
start "CloudOS Recovery V22" /D "%ROOT%" "%ROOT%CloudOS.Supervisor.exe" --recovery-ui
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Recuperacao CloudOS.cmd') -Value $recoveryLauncher -Encoding ascii

$recoveryStatusLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%get-cloudos-recovery-status-v22.ps1" | more
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Status Recuperacao V22.cmd') -Value $recoveryStatusLauncher -Encoding ascii

$diagnosticsLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%collect-native-diagnostics.ps1" -Root "%ROOT%" -SampleSeconds 60 -IntervalSeconds 5
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Coletar Diagnostico 60s.cmd') -Value $diagnosticsLauncher -Encoding ascii

$installLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%install-cloudos-native-v22.ps1" -PackageRoot "%ROOT%"
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Instalar CloudOS.cmd') -Value $installLauncher -Encoding ascii

$updateLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%update-cloudos-native-v13.ps1" -PackageRoot "%ROOT%"
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Atualizar CloudOS.cmd') -Value $updateLauncher -Encoding ascii

$rollbackLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%rollback-cloudos-native-v13.ps1"
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Rollback CloudOS.cmd') -Value $rollbackLauncher -Encoding ascii

$repairLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%repair-cloudos-native-v22.ps1"
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Reparar CloudOS.cmd') -Value $repairLauncher -Encoding ascii

$uninstallLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%uninstall-cloudos-native-v13.ps1"
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Desinstalar CloudOS.cmd') -Value $uninstallLauncher -Encoding ascii

$shellActivateLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%activate-cloudos-shell-v14.ps1"
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Ativar CloudOS como Shell.cmd') -Value $shellActivateLauncher -Encoding ascii

$shellRollbackLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%rollback-cloudos-shell-v14.ps1"
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Restaurar Explorer.cmd') -Value $shellRollbackLauncher -Encoding ascii

$shellRepairLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%repair-cloudos-shell-v14.ps1"
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Reparar Ativacao do Shell.cmd') -Value $shellRepairLauncher -Encoding ascii

$shellStatusLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%get-cloudos-shell-status-v14.ps1"
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Status do Shell CloudOS.cmd') -Value $shellStatusLauncher -Encoding ascii

$readme = @"
CloudOS Native Shell - $Configuration x64

Shell authority: C++/Win32
Recovery authority: CloudOS.Supervisor.exe V11 compatibility / runtime V22
Broker authority: CloudOS.SystemBroker.exe V21
Git head: $($manifest.git_head)
Source fingerprint SHA256: $($manifest.source_fingerprint_sha256)
Built UTC: $($manifest.built_utc)

Arquivos principais:
- CloudOS.exe
- CloudOS.NativeRuntime.dll
- CloudOS.Supervisor.exe
- CloudOS.SystemBroker.exe
- CloudOS.BrokerProbe.exe
- cloudos-native-manifest.json
- SHA256SUMS.txt
- Iniciar CloudOS.cmd
- Recuperacao CloudOS.cmd
- Status Recuperacao V22.cmd
- Verificar Integridade.cmd

Stability/Readiness V9:
- heartbeat/readiness por memoria compartilhada e soak automatizado.

Lifecycle V10:
- resume, WTS/RDP, display revalidation e single-instance.

Supervisor/Recovery V22:
- CloudOS.Supervisor.exe continua preservando o protocolo/ABI V11 de readiness, heartbeat, graceful exit e fallback Explorer.
- o runtime V22 adiciona estados explicitos, crash-loop em janela limitada, SAFE_MODE, journal atomico e Job Object kill-on-close.
- Iniciar CloudOS.cmd abre o Supervisor V22, que inicia CloudOS.exe --supervised.
- Recuperacao CloudOS.cmd abre a interface manual independente com --recovery-ui.
- Status Recuperacao V22.cmd mostra o estado local de recovery sem upload nem mutacao de politica.

System Broker V21:
- CloudOS.SystemBroker.exe e CloudOS.BrokerProbe.exe fazem parte do runtime assinado.
- Verificar Integridade.ps1 valida tamanho + SHA256 dos cinco componentes nativos.
- o Broker permanece boundary tipada; nao existe passthrough arbitrario de comando.

Performance/Visual V12:
- shell event-driven e smoke de idle/performance preservado no pipeline.

Servicing V22 sobre Deployment V13:
- Instalar CloudOS.cmd usa o entrypoint V22 e exige um probe real de readiness/heartbeat/graceful-exit antes de aceitar a primeira ativacao.
- Atualizar CloudOS.cmd preserva staging imutavel V13, exige runtime gerenciado parado e reverte automaticamente para last-known-good se o Supervisor health gate falhar.
- Reparar CloudOS.cmd valida integridade e saude do runtime; se o ativo falhar, tenta um last-known-good verificado.
- rollback, estado transacional e versoes imutaveis continuam pertencendo ao Deployment V13; V22 nao cria um segundo banco de deploy.
- Authenticode pode ser exigido explicitamente e pacotes finalizados como assinados passam a falhar fechado automaticamente.

Shell Activation V14 (OPT-IN):
- instalar/atualizar NAO ativa CloudOS como shell do Windows automaticamente.
- Ativar CloudOS como Shell.cmd exige um V13 instalado e verificado.
- V14 usa somente HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell; nao escreve HKLM.
- antes da alteracao, salva presenca/tipo/valor exatos e cria journal transacional.
- Restaurar Explorer.cmd restaura exatamente o Shell anterior e e copiado para a raiz instalada.
- se a ativacao for interrompida, Reparar Ativacao do Shell.cmd restaura o snapshot pre-transacao.
- Desinstalar CloudOS.cmd se recusa a apagar a instalacao enquanto V14 estiver ativo.
- V14 nao faz logoff/reboot. A mudanca so aparece num proximo sign-in iniciado pelo operador.
- validacao real de logon/crash/boot deve ser feita primeiro em VM; o CI usa chave HKCU sandbox e nunca troca o shell do runner.

Exemplo de soak de 30 minutos:
  pwsh -File .\run-native-soak-v9.ps1 -Root . -Launch -DurationSeconds 1800

Smoke Lifecycle V10:
  pwsh -File .\run-native-lifecycle-smoke-v10.ps1 -Root .

Smoke Shell Supervisor V11 compatibility:
  pwsh -File .\run-native-supervisor-smoke-v11.ps1 -Root .

Smoke Supervisor/Recovery V22:
  pwsh -File .\run-native-supervisor-smoke-v22.ps1 -Root .

Smoke Transactional Install V22:
  pwsh -File .\run-native-install-v22-smoke.ps1 -PackageRoot .

Os smokes nao substituem validacao de shell de logon, suspend/RDP fisico ou hotplug em VM/hardware.
O frontend React antigo nao faz parte deste pacote. WebView2 e usado somente pelo Navegador CloudOS.
"@
Set-Content -LiteralPath (Join-Path $stage 'LEIA-ME.txt') -Value $readme -Encoding utf8

if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
if (-not (Test-Path -LiteralPath $zip) -or (Get-Item -LiteralPath $zip).Length -le 0) {
    throw "Portable CloudOS archive was not produced correctly: $zip"
}
$zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "[CloudOS] PACKAGE=$zip"
Write-Host "[CloudOS] PACKAGE_SHA256=$zipHash"
