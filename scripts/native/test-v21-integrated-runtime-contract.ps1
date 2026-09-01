# test-v21-integrated-runtime-contract.ps1
# CloudOS V21 — integrated NativeShell + Flutter presentation packaging contract.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = (Get-Item "$PSScriptRoot\..\..").FullName

$writeManifestPath = Join-Path $root 'scripts\native\write-native-build-manifest.ps1'
$verifyNativePath = Join-Path $root 'scripts\native\verify-native-build-manifest.ps1'
$verifyIntegratedPath = Join-Path $root 'scripts\flutter\verify-cloudos-v21-runtime.ps1'
$startIntegratedPath = Join-Path $root 'scripts\flutter\start-cloudos-v21-integrated.ps1'
$workflowPath = Join-Path $root '.github\workflows\cloudos-flutter-ui.yml'
$integratedLauncherPath = Join-Path $root 'Abrir CloudOS V21 Flutter com System Broker.cmd'
$previewLauncherPath = Join-Path $root 'Abrir CloudOS Flutter Preview.cmd'
$docPath = Join-Path $root 'desktop\CloudOS.FlutterShell\docs\ai\INTEGRATED_RUNTIME.md'

foreach ($path in @(
    $writeManifestPath,
    $verifyNativePath,
    $verifyIntegratedPath,
    $startIntegratedPath,
    $workflowPath,
    $integratedLauncherPath,
    $previewLauncherPath,
    $docPath
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Integrated V21 contract dependency missing: $path"
    }
}

$writeManifest = Get-Content -LiteralPath $writeManifestPath -Raw
$verifyNative = Get-Content -LiteralPath $verifyNativePath -Raw
$verifyIntegrated = Get-Content -LiteralPath $verifyIntegratedPath -Raw
$startIntegrated = Get-Content -LiteralPath $startIntegratedPath -Raw
$workflow = Get-Content -LiteralPath $workflowPath -Raw
$integratedLauncher = Get-Content -LiteralPath $integratedLauncherPath -Raw
$previewLauncher = Get-Content -LiteralPath $previewLauncherPath -Raw
$doc = Get-Content -LiteralPath $docPath -Raw

$fiveNativeComponents = @(
    'CloudOS.exe',
    'CloudOS.NativeRuntime.dll',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe'
)
foreach ($name in $fiveNativeComponents) {
    if ($writeManifest -notmatch [regex]::Escape($name)) {
        throw "Native build manifest writer does not sign integrated component: $name"
    }
    if ($verifyNative -notmatch [regex]::Escape($name)) {
        throw "Native build verifier does not verify integrated component: $name"
    }
    if ($verifyIntegrated -notmatch [regex]::Escape($name)) {
        throw "Integrated runtime verifier does not verify component: $name"
    }
    if ($workflow -notmatch [regex]::Escape($name)) {
        throw "Flutter integrated workflow does not stage/package component: $name"
    }
}

if ($writeManifest -notmatch "broker_authority\s*=\s*'CloudOS.SystemBroker.exe V21'") {
    throw 'Native manifest must explicitly identify System Broker V21 authority.'
}
if ($verifyNative -notmatch "broker_authority") {
    throw 'Native manifest verifier must enforce broker authority metadata.'
}

foreach ($required in @(
    'cloudos-v21-integrated-manifest.json',
    'native_manifest_sha256',
    'flutter_sha256',
    'native-authority-with-flutter-presentation'
)) {
    if ($verifyIntegrated -notmatch [regex]::Escape($required) -or
        $workflow -notmatch [regex]::Escape($required)) {
        throw "Integrated composition integrity contract is missing: $required"
    }
}

if ($workflow -notmatch 'build-cloudos-native\.cmd Release') {
    throw 'Flutter V21 artifact must build the authoritative native runtime, not Broker-only binaries.'
}
if ($workflow -notmatch 'package-cloudos-native\.ps1') {
    throw 'Flutter V21 artifact must stage from the verified native package boundary.'
}
if ($workflow -notmatch 'verify-cloudos-v21-runtime\.ps1') {
    throw 'Flutter V21 artifact must verify the composed runtime before packaging.'
}
if ($workflow -notmatch "desktop/CloudOS.NativeShell/\*\*" -or
    $workflow -notmatch "desktop/CloudOS.NativeCommon/\*\*") {
    throw 'Flutter V21 workflow path filters must include its native authority dependencies.'
}

if ($startIntegrated -notmatch 'CloudOS\.NativeShell\.Activation\.v21' -or
    $startIntegrated -notmatch 'FindWindowEx') {
    throw 'Integrated launcher must wait for the typed NativeShell V21 activation endpoint.'
}
if ($startIntegrated -notmatch 'Assert-AuthorityPath' -or
    $startIntegrated -notmatch 'Outra autoridade NativeShell V21 ja esta ativa') {
    throw 'Integrated launcher must reject an activation endpoint owned by a different CloudOS binary.'
}
if ($startIntegrated -notmatch 'CloudOS\.BrokerProbe\.exe' -or
    $startIntegrated -notmatch 'health\.ping|ping') {
    throw 'Integrated launcher must prove Broker readiness through BrokerProbe.'
}
if ($startIntegrated -notmatch 'CloudOS\.Supervisor\.exe') {
    throw 'Integrated launcher must start NativeShell through Supervisor V11.'
}
if ($startIntegrated -match 'Winlogon|HKCU\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon') {
    throw 'Integrated presentation launcher must not modify or depend on Winlogon shell activation.'
}

if ($integratedLauncher -notmatch 'start-cloudos-v21-integrated\.ps1' -or
    $integratedLauncher -match 'start\s+""\s+"%APP_DIR%\\CloudOS\.SystemBroker\.exe"') {
    throw 'Top-level V21 launcher must delegate to the verified integrated launcher instead of starting Broker directly.'
}

if ($previewLauncher -notmatch 'preview-cloudos-flutter-v19\.ps1' -or
    $previewLauncher -match 'start-cloudos-v21-integrated\.ps1') {
    throw 'Flutter Preview launcher must remain explicitly separate from the integrated NativeShell runtime.'
}

if ($doc -notmatch 'Preview' -or
    $doc -notmatch 'Integrado' -or
    $doc -notmatch 'CloudOS\.exe' -or
    $doc -notmatch 'Flutter') {
    throw 'Integrated runtime documentation must explain Preview vs Integrated authority.'
}

Write-Host '[PASS] CloudOS V21 integrated runtime packaging contract passed.'
