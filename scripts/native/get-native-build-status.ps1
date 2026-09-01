param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$out = Join-Path $rootPath 'desktop\CloudOS.NativeShell\bin\Release'
$fingerprintScript = Join-Path $PSScriptRoot 'get-native-build-fingerprint.ps1'
$verifyScript = Join-Path $PSScriptRoot 'verify-native-build-manifest.ps1'
$manifestPath = Join-Path $out 'cloudos-native-manifest.json'
$stampPath = Join-Path $out '.cloudos-build-fingerprint'
$exePath = Join-Path $out 'CloudOS.exe'
$dllPath = Join-Path $out 'CloudOS.NativeRuntime.dll'
$supervisorPath = Join-Path $out 'CloudOS.Supervisor.exe'
$brokerPath = Join-Path $out 'CloudOS.SystemBroker.exe'
$probePath = Join-Path $out 'CloudOS.BrokerProbe.exe'

$currentFingerprint = $null
try { $currentFingerprint = (& $fingerprintScript -Root $rootPath | Select-Object -Last 1).Trim() } catch {}

$builtFingerprint = $null
if (Test-Path -LiteralPath $stampPath) { $builtFingerprint = (Get-Content -LiteralPath $stampPath -Raw).Trim() }

$manifest = $null
if (Test-Path -LiteralPath $manifestPath) {
    try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } catch {}
}

$integrity = $false
$integrityMessage = 'build ausente ou nao verificado'
if ((Test-Path -LiteralPath $verifyScript) -and (Test-Path -LiteralPath $manifestPath)) {
    try {
        & $verifyScript -Root $rootPath -Configuration Release -CheckSourceFingerprint *> $null
        $integrity = $true
        $integrityMessage = 'OK'
    }
    catch { $integrityMessage = $_.Exception.Message }
}

$gitHead = $null
if (Get-Command git.exe -ErrorAction SilentlyContinue) {
    $candidate = (& git.exe -C $rootPath rev-parse HEAD 2>$null | Select-Object -Last 1)
    if ($candidate) { $gitHead = $candidate.Trim() }
}

$status = [ordered]@{
    shell = 'C++/Win32 native'
    recovery = 'CloudOS.Supervisor.exe V11'
    broker = 'CloudOS.SystemBroker.exe V21'
    configuration = 'Release x64'
    git_head = $gitHead
    current_source_fingerprint = $currentFingerprint
    built_source_fingerprint = $builtFingerprint
    source_matches_build = [bool]($currentFingerprint -and $builtFingerprint -and $currentFingerprint -eq $builtFingerprint)
    integrity_ok = $integrity
    integrity_message = $integrityMessage
    exe_exists = Test-Path -LiteralPath $exePath
    runtime_exists = Test-Path -LiteralPath $dllPath
    supervisor_exists = Test-Path -LiteralPath $supervisorPath
    broker_exists = Test-Path -LiteralPath $brokerPath
    probe_exists = Test-Path -LiteralPath $probePath
    manifest_exists = Test-Path -LiteralPath $manifestPath
    manifest_built_utc = if ($manifest) { $manifest.built_utc } else { $null }
    manifest_git_head = if ($manifest) { $manifest.git_head } else { $null }
    ready_to_run = [bool]($integrity -and $currentFingerprint -eq $builtFingerprint)
}

if ($Json) { $status | ConvertTo-Json -Depth 5; exit 0 }

Write-Host 'CloudOS Native - Build Status'
Write-Host '-----------------------------'
foreach ($entry in $status.GetEnumerator()) { Write-Host ("{0,-28}: {1}" -f $entry.Key, $entry.Value) }

if (-not $status.ready_to_run) {
    Write-Host ''
    Write-Host 'Acao recomendada: scripts\native\start-cloudos-native.cmd --force-rebuild'
    exit 1
}

Write-Host ''
Write-Host 'READY: Shell, Runtime, Supervisor V11, System Broker V21 e BrokerProbe correspondem as fontes atuais e passaram na verificacao SHA256.'
