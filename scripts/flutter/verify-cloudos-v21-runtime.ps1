[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$NativeRoot,
    [switch]$AllowDevelopmentLayout
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$presentationRoot = (Resolve-Path -LiteralPath $Root).Path
$nativeRootPath = if ($NativeRoot) {
    (Resolve-Path -LiteralPath $NativeRoot).Path
}
else {
    $presentationRoot
}

$nativeManifestPath = Join-Path $nativeRootPath 'cloudos-native-manifest.json'
if (-not (Test-Path -LiteralPath $nativeManifestPath -PathType Leaf)) {
    throw "Manifesto nativo V21 ausente: $nativeManifestPath"
}

$nativeManifest = Get-Content -LiteralPath $nativeManifestPath -Raw | ConvertFrom-Json
if ($nativeManifest.schema -ne 1 -or
    $nativeManifest.product -ne 'CloudOS Native Shell' -or
    $nativeManifest.shell_authority -ne 'C++/Win32' -or
    $nativeManifest.recovery_authority -ne 'CloudOS.Supervisor.exe V11' -or
    $nativeManifest.broker_authority -ne 'CloudOS.SystemBroker.exe V21' -or
    $nativeManifest.legacy_react_desktop -ne $false) {
    throw 'Manifesto nativo V21 invalido ou com autoridade incorreta.'
}

$nativeNames = @(
    'CloudOS.exe',
    'CloudOS.NativeRuntime.dll',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe'
)
foreach ($name in $nativeNames) {
    $records = @($nativeManifest.files | Where-Object { $_.name -eq $name })
    if ($records.Count -ne 1) {
        throw "Manifesto nativo deve conter exatamente um registro de $name"
    }
    $path = Join-Path $nativeRootPath $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Componente V21 ausente: $path"
    }
    $item = Get-Item -LiteralPath $path
    if ($item.Length -le 0 -or [Int64]$records[0].size -ne [Int64]$item.Length) {
        throw "Tamanho invalido para $name"
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne ([string]$records[0].sha256).ToLowerInvariant()) {
        throw "SHA256 invalido para $name"
    }
}

$flutterExe = Join-Path $presentationRoot 'cloudos_flutter_shell.exe'
if (-not (Test-Path -LiteralPath $flutterExe -PathType Leaf) -or
    (Get-Item -LiteralPath $flutterExe).Length -le 0) {
    throw "Flutter V21 ausente ou vazio: $flutterExe"
}

$integratedManifestPath = Join-Path $presentationRoot 'cloudos-v21-integrated-manifest.json'
if (Test-Path -LiteralPath $integratedManifestPath -PathType Leaf) {
    $integrated = Get-Content -LiteralPath $integratedManifestPath -Raw | ConvertFrom-Json
    if ($integrated.schema -ne 21 -or
        $integrated.product -ne 'CloudOS V21 Integrated Presentation Runtime' -or
        $integrated.shell_authority -ne 'CloudOS.exe C++/Win32' -or
        $integrated.presentation_layer -ne 'Flutter 3.44.7' -or
        $integrated.runtime_mode -ne 'native-authority-with-flutter-presentation') {
        throw 'Manifesto integrado V21 invalido.'
    }

    $nativeManifestHash = (Get-FileHash -LiteralPath $nativeManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($nativeManifestHash -ne ([string]$integrated.native_manifest_sha256).ToLowerInvariant()) {
        throw 'O manifesto nativo nao corresponde ao manifesto integrado V21.'
    }

    $flutterHash = (Get-FileHash -LiteralPath $flutterExe -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($flutterHash -ne ([string]$integrated.flutter_sha256).ToLowerInvariant()) {
        throw 'SHA256 do executavel Flutter nao corresponde ao manifesto integrado V21.'
    }
}
elseif (-not $AllowDevelopmentLayout) {
    throw "Manifesto integrado V21 ausente: $integratedManifestPath"
}

Write-Host "[CloudOS V21] INTEGRITY_OK: NativeShell, Runtime, Supervisor, Broker, Probe e Flutter verificados."
