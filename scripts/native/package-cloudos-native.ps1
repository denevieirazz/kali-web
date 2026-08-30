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
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$payload = @(
    'CloudOS.exe',
    'CloudOS.NativeRuntime.dll',
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

# Stability/Readiness V9 tooling is intentionally script-only and local. It
# reads allowlisted health/process counters and never uploads diagnostics.
foreach ($name in @(
    'native-health-v9.ps1',
    'collect-native-diagnostics.ps1',
    'run-native-soak-v9.ps1'
)) {
    $source = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Stability V9 package tool missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $stage $name) -Force
}

$manifestPath = Join-Path $stage 'cloudos-native-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Staged native manifest missing: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$sumLines = New-Object System.Collections.Generic.List[string]
foreach ($file in @('CloudOS.exe', 'CloudOS.NativeRuntime.dll')) {
    $path = Join-Path $stage $file
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Staged native payload missing: $path"
    }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $sumLines.Add("$hash  $file")
}
Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Value $sumLines -Encoding ascii

$packageVerifier = @'
param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$rootPath = (Resolve-Path -LiteralPath $Root).Path
$manifestPath = Join-Path $rootPath 'cloudos-native-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifesto ausente: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1 -or
    $manifest.product -ne 'CloudOS Native Shell' -or
    $manifest.shell_authority -ne 'C++/Win32' -or
    $manifest.legacy_react_desktop -ne $false) {
    throw 'Manifesto do pacote CloudOS Native invalido.'
}

foreach ($name in @('CloudOS.exe', 'CloudOS.NativeRuntime.dll')) {
    $records = @($manifest.files | Where-Object { $_.name -eq $name })
    if ($records.Count -ne 1) {
        throw "Registro de integridade invalido para $name"
    }

    $path = Join-Path $rootPath $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Arquivo ausente: $name"
    }

    $item = Get-Item -LiteralPath $path
    if ($item.Length -le 0 -or [Int64]$records[0].size -ne [Int64]$item.Length) {
        throw "Tamanho invalido: $name"
    }

    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne ([string]$records[0].sha256).ToLowerInvariant()) {
        throw "SHA256 invalido: $name"
    }
}

if (Test-Path -LiteralPath (Join-Path $rootPath 'ui')) {
    throw 'Desktop web legado nao e permitido no pacote nativo.'
}

Write-Host '[CloudOS] INTEGRITY_OK: EXE, runtime e manifesto conferem.'
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
if not exist "%ROOT%Verificar Integridade.ps1" (
  echo [CloudOS] Verificador de integridade ausente neste pacote.
  exit /b 4
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%Verificar Integridade.ps1" -Root "%ROOT%"
if errorlevel 1 (
  echo [CloudOS] Integridade do pacote FALHOU. O shell nao sera iniciado.
  exit /b 5
)
tasklist /FI "IMAGENAME eq CloudOS.exe" /NH 2>nul | findstr /I /C:"CloudOS.exe" >nul
if not errorlevel 1 (
  echo [CloudOS] Ja existe uma instancia aberta. Salve seu trabalho e encerre-a normalmente antes de iniciar esta versao.
  exit /b 6
)
pushd "%ROOT%" >nul
start "" /D "%ROOT%" "%ROOT%CloudOS.exe"
set "RC=%ERRORLEVEL%"
popd >nul
exit /b %RC%
'@
Set-Content -LiteralPath (Join-Path $stage 'Iniciar CloudOS.cmd') -Value $launcher -Encoding ascii

$diagnosticsLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%collect-native-diagnostics.ps1" -Root "%ROOT%" -SampleSeconds 60 -IntervalSeconds 5
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $stage 'Coletar Diagnostico 60s.cmd') -Value $diagnosticsLauncher -Encoding ascii

$readme = @"
CloudOS Native Shell - $Configuration x64

Shell authority: C++/Win32
Git head: $($manifest.git_head)
Source fingerprint SHA256: $($manifest.source_fingerprint_sha256)
Built UTC: $($manifest.built_utc)

Arquivos principais:
- CloudOS.exe
- CloudOS.NativeRuntime.dll
- cloudos-native-manifest.json
- SHA256SUMS.txt
- Verificar Integridade.ps1
- Verificar Integridade.cmd
- Iniciar CloudOS.cmd

Stability/Readiness V9:
- native-health-v9.ps1: leitor do heartbeat/readiness em memoria compartilhada.
- collect-native-diagnostics.ps1: coleta local allowlisted, sem upload.
- Coletar Diagnostico 60s.cmd: coleta rapida de CPU/RAM/threads/handles/GDI/USER/heartbeat.
- run-native-soak-v9.ps1: soak automatizado com deteccao de crash/hang e orcamentos de crescimento.

Exemplo de soak de 30 minutos em uma instancia isolada:
  pwsh -File .\run-native-soak-v9.ps1 -Root . -Launch -DurationSeconds 1800

`Iniciar CloudOS.cmd` valida automaticamente tamanho e SHA256 de CloudOS.exe e CloudOS.NativeRuntime.dll antes de executar. Para verificar sem iniciar, use `Verificar Integridade.cmd`.

O frontend React antigo nao faz parte deste pacote. WebView2 e usado somente pelo Navegador CloudOS.
"@
Set-Content -LiteralPath (Join-Path $stage 'LEIA-ME.txt') -Value $readme -Encoding utf8

if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal

if (-not (Test-Path -LiteralPath $zip) -or (Get-Item -LiteralPath $zip).Length -le 0) {
    throw "Portable CloudOS archive was not produced correctly: $zip"
}

$zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "[CloudOS] PACKAGE=$zip"
Write-Host "[CloudOS] PACKAGE_SHA256=$zipHash"
