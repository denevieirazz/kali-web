[CmdletBinding()]
param(
    [string]$SourceDir,
    [string]$OutputDir,
    [switch]$CreateZip
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path

if (-not $SourceDir) {
    $SourceDir = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release'
}
$sourcePath = (Resolve-Path -LiteralPath $SourceDir).Path

if (-not $OutputDir) {
    $OutputDir = Join-Path $repoRoot 'dist\CloudOS'
}

Write-Host "[CloudOS Package Builder] Origem: $sourcePath" -ForegroundColor Cyan
Write-Host "[CloudOS Package Builder] Destino: $OutputDir" -ForegroundColor Cyan

# 1. Verificar se a origem contem os arquivos essenciais
$requiredExecutables = @(
    'CloudOS.exe',
    'cloudos_flutter_shell.exe',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe'
)
$requiredDlls = @(
    'CloudOS.NativeRuntime.dll',
    'flutter_windows.dll',
    'webview_flutter_windows_plugin.dll',
    'WebView2Loader.dll'
)

foreach ($exe in $requiredExecutables) {
    $p = Join-Path $sourcePath $exe
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw "Executavel obrigatorio ausente no release: $p"
    }
}
foreach ($dll in $requiredDlls) {
    $p = Join-Path $sourcePath $dll
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw "DLL obrigatoria ausente no release: $p"
    }
}

$dataPath = Join-Path $sourcePath 'data'
if (-not (Test-Path -LiteralPath $dataPath -PathType Container)) {
    throw "Diretorio data/ ausente no release: $dataPath"
}

# 2. Preparar diretorio de saida limpo
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutputDir 'data') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutputDir 'manifests') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutputDir 'scripts') -Force | Out-Null

# 3. Copiar binarios e DLLs raiz
foreach ($exe in $requiredExecutables) {
    Copy-Item -LiteralPath (Join-Path $sourcePath $exe) -Destination (Join-Path $OutputDir $exe) -Force
}
foreach ($dll in $requiredDlls) {
    Copy-Item -LiteralPath (Join-Path $sourcePath $dll) -Destination (Join-Path $OutputDir $dll) -Force
}

$shellComponents = @('CloudOS.ShellBootstrap.exe', 'CloudOS.Recovery.exe', 'CLOUDOS_SHELL_RECOVERY.txt')
foreach ($sc in $shellComponents) {
    $scSrc = Join-Path $sourcePath $sc
    if (-not (Test-Path -LiteralPath $scSrc)) {
        $scSrc = Join-Path $repoRoot "desktop\CloudOS.NativeShell\bin\Release\$sc"
    }
    if (-not (Test-Path -LiteralPath $scSrc)) {
        $scSrc = Join-Path $repoRoot $sc
    }
    if (Test-Path -LiteralPath $scSrc) {
        Copy-Item -LiteralPath $scSrc -Destination (Join-Path $OutputDir $sc) -Force
    }
}

if (Test-Path -LiteralPath (Join-Path $sourcePath 'native_assets.json')) {
    Copy-Item -LiteralPath (Join-Path $sourcePath 'native_assets.json') -Destination (Join-Path $OutputDir 'native_assets.json') -Force
}

# 4. Copiar data/ (excluindo qualquer arquivo temporario ou pdb se houver)
Copy-Item -LiteralPath $dataPath -Destination $OutputDir -Recurse -Force

# 5. Copiar version.json
$versionFile = Join-Path $repoRoot 'version.json'
if (Test-Path -LiteralPath $versionFile) {
    Copy-Item -LiteralPath $versionFile -Destination (Join-Path $OutputDir 'version.json') -Force
}

# 6. Copiar manifestos nativos e integrados
$nativeManifest = Join-Path $sourcePath 'cloudos-native-manifest.json'
if (Test-Path -LiteralPath $nativeManifest) {
    Copy-Item -LiteralPath $nativeManifest -Destination (Join-Path $OutputDir 'manifests\cloudos-native-manifest.json') -Force
    Copy-Item -LiteralPath $nativeManifest -Destination (Join-Path $OutputDir 'cloudos-native-manifest.json') -Force
}
$integratedManifest = Join-Path $sourcePath 'cloudos-v21-integrated-manifest.json'
if (Test-Path -LiteralPath $integratedManifest) {
    Copy-Item -LiteralPath $integratedManifest -Destination (Join-Path $OutputDir 'manifests\cloudos-v21-integrated-manifest.json') -Force
    Copy-Item -LiteralPath $integratedManifest -Destination (Join-Path $OutputDir 'cloudos-v21-integrated-manifest.json') -Force
}

# 7. Copiar scripts auxiliares de inicializacao e verificacao
foreach ($s in @('verify-cloudos-v21-runtime.ps1', 'start-cloudos-v21-integrated.ps1', 'Iniciar CloudOS.cmd')) {
    $src = Join-Path $sourcePath $s
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $OutputDir "scripts\$s") -Force
        Copy-Item -LiteralPath $src -Destination (Join-Path $OutputDir $s) -Force
    }
}

# 8. Remover estritamente qualquer lixo de build que possa ter entrado
Get-ChildItem -Path $OutputDir -Recurse -Include @('*.pdb', '*.ilk', '*.obj', '*.exp', '*.lib', '*.iobj', '*.ipdb') | Remove-Item -Force

# 9. Gerar o manifesto de integridade canônico de todos os arquivos do pacote
$versionData = if (Test-Path -LiteralPath (Join-Path $OutputDir 'version.json')) {
    Get-Content -LiteralPath (Join-Path $OutputDir 'version.json') -Raw | ConvertFrom-Json
} else {
    [pscustomobject]@{ productVersion = '21.0.0'; build = 29; gitSha = 'c0836754'; protocolVersion = 21; architecture = 'x64' }
}

$allFiles = Get-ChildItem -Path $OutputDir -Recurse -File | Where-Object { $_.Name -ne 'cloudos-package-manifest.json' } | Sort-Object FullName
$manifestItems = [System.Collections.Generic.List[object]]::new()
$totalBytes = 0

foreach ($file in $allFiles) {
    # Relativo ao OutputDir
    $rel = $file.FullName.Substring($OutputDir.Length).TrimStart('\', '/') -replace '\\', '/'
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifestItems.Add([ordered]@{
        path   = $rel
        size   = $file.Length
        sha256 = $hash
    })
    $totalBytes += $file.Length
}

$resolvedBuild = if ($versionData.PSObject.Properties['build']) { [int]$versionData.build } elseif ($versionData.PSObject.Properties['buildNumber']) { [int]$versionData.buildNumber } else { 32 }

$packageManifest = [ordered]@{
    schema           = 1
    product          = 'CloudOS Canonical Distribution Package'
    version          = [string]$versionData.productVersion
    build            = $resolvedBuild
    gitSha           = [string]$versionData.gitSha
    protocolVersion  = [int]$versionData.protocolVersion
    architecture     = [string]$versionData.architecture
    generatedAt      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    totalFiles       = $manifestItems.Count
    totalBytes       = $totalBytes
    files            = $manifestItems
}

$manifestJson = $packageManifest | ConvertTo-Json -Depth 5
$pkgManifestDest1 = Join-Path $OutputDir 'manifests\cloudos-package-manifest.json'
$pkgManifestDest2 = Join-Path $OutputDir 'cloudos-package-manifest.json'
[System.IO.File]::WriteAllText($pkgManifestDest1, $manifestJson, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($pkgManifestDest2, $manifestJson, [System.Text.Encoding]::UTF8)

Write-Host "[CloudOS Package Builder] Pacote montado com sucesso!" -ForegroundColor Green
Write-Host "  Arquivos: $($manifestItems.Count) | Tamanho Total: $([math]::Round($totalBytes / 1MB, 2)) MB" -ForegroundColor Green

if ($CreateZip) {
    $zipDir = Split-Path -Parent $OutputDir
    $zipPath = Join-Path $zipDir "CloudOS-v$($versionData.productVersion)-x64.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $OutputDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Host "[CloudOS Package Builder] Arquivo compactado gerado: $zipPath" -ForegroundColor Green
}

return [pscustomobject]@{
    OutputDir   = $OutputDir
    TotalFiles  = $manifestItems.Count
    TotalBytes  = $totalBytes
    ManifestPath = $pkgManifestDest1
}
