$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$paths = @{
    Fingerprint = Join-Path $PSScriptRoot 'get-native-build-fingerprint.ps1'
    Writer = Join-Path $PSScriptRoot 'write-native-build-manifest.ps1'
    Verifier = Join-Path $PSScriptRoot 'verify-native-build-manifest.ps1'
    Packager = Join-Path $PSScriptRoot 'package-cloudos-native.ps1'
    Status = Join-Path $PSScriptRoot 'get-native-build-status.ps1'
    Build = Join-Path $PSScriptRoot 'build-cloudos-native.cmd'
    ContractSuite = Join-Path $PSScriptRoot 'test-native-contract-suite.ps1'
    Start = Join-Path $PSScriptRoot 'start-cloudos-native.cmd'
    RootStart = Join-Path $root 'Iniciar CloudOS Nativo.cmd'
    RootBuild = Join-Path $root 'Compilar CloudOS Nativo.cmd'
    RootVerify = Join-Path $root 'Verificar CloudOS Nativo.cmd'
    RootPackage = Join-Path $root 'Empacotar CloudOS Nativo.cmd'
    Workflow = Join-Path $root '.github\workflows\cloudos-native-full-system.yml'
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw "Native release pipeline contract path missing [$($entry.Key)]: $($entry.Value)"
    }
}
$content = @{}
foreach ($entry in $paths.GetEnumerator()) { $content[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw }

function Require([string]$Name, [string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) { throw "$Name contract missing: $token" }
    }
}

Require 'Deterministic native fingerprint' $content.Fingerprint @(
    'desktop\CloudOS.NativeCommon',
    'desktop\CloudOS.NativeRuntime',
    'desktop\CloudOS.NativeShell',
    'desktop\CloudOS.NativeRecovery',
    'desktop\CloudOS.SystemBroker',
    'desktop\CloudOS.BrokerProbe',
    'scripts\native',
    "'bin', 'obj', 'packages', '.vs'",
    'Get-FileHash',
    'SHA256',
    'Sort-Object'
)

Require 'Native provenance manifest writer' $content.Writer @(
    'cloudos-native-manifest.json',
    '.cloudos-build-head',
    '.cloudos-build-fingerprint',
    "shell_authority = 'C++/Win32'",
    "recovery_authority = 'CloudOS.Supervisor.exe V11'",
    "broker_authority = 'CloudOS.SystemBroker.exe V21'",
    "legacy_react_desktop = `$false",
    'source_fingerprint_sha256',
    'CloudOS.exe',
    'CloudOS.NativeRuntime.dll',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe',
    'Get-FileHash'
)

Require 'Native integrity verifier' $content.Verifier @(
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe',
    'broker_authority',
    'Native binary SHA256 mismatch',
    'Native binary size mismatch',
    'Obsolete web-desktop output',
    'CheckSourceFingerprint',
    'Native binary is stale for the current source tree'
)

Require 'Portable native self-verifying packager' $content.Packager @(
    'CloudOS-Native-Release-x64.zip',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe',
    'verify-native-build-manifest.ps1',
    'SHA256SUMS.txt',
    'Verificar Integridade.ps1',
    'Verificar Integridade.cmd',
    'Iniciar CloudOS.cmd',
    'Recuperacao CloudOS.cmd',
    '--recovery-ui',
    'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass',
    'Integridade do pacote FALHOU',
    'INTEGRITY_OK',
    'Get-FileHash',
    'broker_authority',
    'legacy_react_desktop',
    'LEIA-ME.txt',
    'Compress-Archive',
    'PACKAGE_SHA256'
)

Require 'Native build status diagnostics' $content.Status @(
    'current_source_fingerprint',
    'built_source_fingerprint',
    'source_matches_build',
    'integrity_ok',
    'supervisor_exists',
    'broker_exists',
    'probe_exists',
    "broker = 'CloudOS.SystemBroker.exe V21'",
    'ready_to_run',
    '--force-rebuild'
)

Require 'Native build entrypoint provenance' $content.Build @(
    'test-native-contract-suite.ps1',
    'CloudOS.NativeRecovery\CloudOS.NativeRecovery.vcxproj',
    'CloudOS.SystemBroker\CloudOS.SystemBroker.vcxproj',
    'CloudOS.BrokerProbe\CloudOS.BrokerProbe.vcxproj',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe',
    'write-native-build-manifest.ps1',
    'verify-native-build-manifest.ps1',
    'cloudos-native-manifest.json',
    '.cloudos-build-fingerprint',
    'Microsoft.Web.WebView2 ja restaurado; reutilizando cache local'
)
Require 'Central contract suite contains release pipeline contract' $content.ContractSuite @('test-native-release-pipeline-contract.ps1')

Require 'Native launcher integrity gate' $content.Start @(
    'get-native-build-fingerprint.ps1',
    'verify-native-build-manifest.ps1',
    '.cloudos-build-fingerprint',
    'SOURCE_FINGERPRINT',
    '--force-rebuild',
    '--no-build',
    'tasklist /FI "IMAGENAME eq CloudOS.exe"',
    'tasklist /FI "IMAGENAME eq CloudOS.SystemBroker.exe"',
    'CloudOS.SystemBroker.exe ausente',
    'CloudOS.BrokerProbe.exe ausente',
    'encerre a instancia aberta normalmente',
    'CloudOS.Supervisor.exe',
    'Shell Supervisor V11'
)

if ($content.Start -match '(?i)taskkill\s+/F' -or $content.Packager -match '(?i)taskkill\s+/F') {
    throw 'Launchers must not force-close user sessions.'
}

Require 'Root start shortcut forwards flags' $content.RootStart @('start-cloudos-native.cmd', '%*')
Require 'Root verified build shortcut' $content.RootBuild @('build-cloudos-native.cmd', 'Release', 'BUILD OK')
Require 'Root build verification shortcut' $content.RootVerify @('get-native-build-status.ps1', '--force-rebuild', 'Build pronto para executar')
Require 'Root portable package shortcut' $content.RootPackage @('get-native-build-status.ps1', 'build-cloudos-native.cmd', 'package-cloudos-native.ps1', 'CloudOS-Native-Release-x64.zip')

Require 'CI release artifact and dependency cache' $content.Workflow @(
    'actions/cache@v4',
    'Cache pinned WebView2 SDK',
    'desktop/CloudOS.NativeShell/packages/Microsoft.Web.WebView2.1.0.4078.44',
    'cloudos-webview2-1.0.4078.44-windows-v1',
    'build-cloudos-native.cmd',
    'run-native-supervisor-smoke-v11.ps1',
    'verify-native-build-manifest.ps1',
    'package-cloudos-native.ps1',
    'CloudOS.Supervisor.exe',
    'CloudOS-Native-Release-x64.zip',
    'actions/upload-artifact@v4',
    'cloudos-native-manifest.json'
)

Write-Host 'PASS: deterministic fingerprint includes Broker/Probe sources, five-binary V21 integrity/status, Supervisor V11 launch authority, self-verifying portable package, root workflow shortcuts, WebView2 CI cache and verified release artifact contracts are protected.'
