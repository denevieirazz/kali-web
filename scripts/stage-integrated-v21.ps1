$ErrorActionPreference = 'Stop'
$root = if ($PSScriptRoot) { (Resolve-Path (Join-Path $PSScriptRoot '..')).Path } else { (Get-Location).Path }
$release = Join-Path $root 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release'
$nativeStage = Join-Path $root 'desktop\CloudOS.NativeShell\bin\Release'
$artifactsDir = Join-Path $root 'desktop\CloudOS.NativeShell\artifacts\CloudOS-Native-Release-x64'

foreach ($name in @(
    'CloudOS.exe',
    'CloudOS.NativeRuntime.dll',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe',
    'cloudos-native-manifest.json',
    '.cloudos-build-head',
    '.cloudos-build-fingerprint'
)) {
    $source = Join-Path $nativeStage $name
    if (-not (Test-Path -LiteralPath $source)) { throw "Integrated V21 payload missing: $source" }
    Copy-Item -LiteralPath $source -Destination $release -Force
    if (Test-Path -LiteralPath $artifactsDir) {
        Copy-Item -LiteralPath $source -Destination $artifactsDir -Force
    }
}

foreach ($extra in @('CloudOS.ShellBootstrap.exe', 'CloudOS.Recovery.exe')) {
    $src = Join-Path $nativeStage $extra
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination $release -Force
        if (Test-Path -LiteralPath $artifactsDir) {
            Copy-Item -LiteralPath $src -Destination $artifactsDir -Force
        }
    }
}
$recDoc = Join-Path $root 'CLOUDOS_SHELL_RECOVERY.txt'
if (Test-Path -LiteralPath $recDoc) {
    Copy-Item -LiteralPath $recDoc -Destination $release -Force
    if (Test-Path -LiteralPath $artifactsDir) {
        Copy-Item -LiteralPath $recDoc -Destination $artifactsDir -Force
    }
}

Copy-Item -LiteralPath (Join-Path $root 'scripts\flutter\verify-cloudos-v21-runtime.ps1') -Destination $release -Force
Copy-Item -LiteralPath (Join-Path $root 'scripts\flutter\start-cloudos-v21-integrated.ps1') -Destination $release -Force

$exe = Join-Path $release 'cloudos_flutter_shell.exe'
$nativeManifest = Join-Path $release 'cloudos-native-manifest.json'
$flutterSha = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant()
$nativeManifestSha = (Get-FileHash $nativeManifest -Algorithm SHA256).Hash.ToLowerInvariant()

$integrated = [ordered]@{
    schema = 21
    product = 'CloudOS V21 Integrated Presentation Runtime'
    git_sha = (git rev-parse HEAD).Trim()
    runtime_mode = 'native-authority-with-flutter-presentation'
    shell_authority = 'CloudOS.exe C++/Win32'
    recovery_authority = 'CloudOS.Supervisor.exe V11'
    broker_authority = 'CloudOS.SystemBroker.exe V21'
    presentation_layer = 'Flutter 3.44.7'
    native_bridge_channel = 'cloudos/native/v19'
    native_broker_ipc = 'NamedPipe v21'
    native_manifest = 'cloudos-native-manifest.json'
    native_manifest_sha256 = $nativeManifestSha
    flutter_executable = 'cloudos_flutter_shell.exe'
    flutter_sha256 = $flutterSha
    arbitrary_command_api = $false
    winlogon_modified = $false
}
$integratedPath = Join-Path $release 'cloudos-v21-integrated-manifest.json'
$integrated | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $integratedPath -Encoding UTF8

& (Join-Path $release 'verify-cloudos-v21-runtime.ps1') -Root $release
Write-Host "STAGE_AND_VERIFY_SUCCESS"
