param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$out = Join-Path $rootPath "desktop\CloudOS.NativeShell\bin\$Configuration"
$artifactDir = Join-Path $rootPath 'desktop\CloudOS.NativeShell\artifacts'
$stage = Join-Path $artifactDir 'CloudOS-Native-Release-x64'
$zip = Join-Path $artifactDir 'CloudOS-Native-Release-x64.zip'
$verify = Join-Path $PSScriptRoot 'verify-native-build-manifest.ps1'

& $verify -Root $rootPath -Configuration $Configuration -CheckSourceFingerprint

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

$launcher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
if not exist "%ROOT%CloudOS.exe" (
  echo [CloudOS] CloudOS.exe ausente neste pacote.
  exit /b 2
)
if not exist "%ROOT%CloudOS.NativeRuntime.dll" (
  echo [CloudOS] CloudOS.NativeRuntime.dll ausente neste pacote.
  exit /b 3
)
taskkill /F /IM CloudOS.exe >nul 2>&1
timeout /t 1 /nobreak >nul 2>&1
pushd "%ROOT%" >nul
start "" /D "%ROOT%" "%ROOT%CloudOS.exe"
set "RC=%ERRORLEVEL%"
popd >nul
exit /b %RC%
'@
Set-Content -LiteralPath (Join-Path $stage 'Iniciar CloudOS.cmd') -Value $launcher -Encoding ascii

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
- Iniciar CloudOS.cmd

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
