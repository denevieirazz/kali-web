<#
.SYNOPSIS
    Contrato de Validacao do Layout Canonico do Instalador do CloudOS (Etapa 9).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$packageScript = Join-Path $PSScriptRoot 'build-cloudos-package.ps1'

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 1/5] Validacao de Layout Canonico do Pacote" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Executar gerador do pacote
$buildResult = & $packageScript
$distDir = $buildResult.OutputDir

if (-not (Test-Path -LiteralPath $distDir -PathType Container)) {
    throw "FALHA: Diretorio dist/CloudOS nao foi gerado."
}

# 2. Verificar presenca de executaveis e DLLs essenciais
$expectedExecutables = @(
    'CloudOS.exe',
    'cloudos_flutter_shell.exe',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe'
)
foreach ($exe in $expectedExecutables) {
    $p = Join-Path $distDir $exe
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw "FALHA: Executavel essencial ausente no pacote: $exe"
    }
}
Write-Host "[OK] Todos os 5 executaveis essenciais estao presentes." -ForegroundColor Green

$expectedDlls = @(
    'CloudOS.NativeRuntime.dll',
    'flutter_windows.dll',
    'webview_flutter_windows_plugin.dll',
    'WebView2Loader.dll'
)
foreach ($dll in $expectedDlls) {
    $p = Join-Path $distDir $dll
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw "FALHA: DLL essencial ausente no pacote: $dll"
    }
}
Write-Host "[OK] Todas as 4 DLLs de runtime estao presentes." -ForegroundColor Green

# 3. Verificar data/ e assets
$dataDir = Join-Path $distDir 'data'
if (-not (Test-Path -LiteralPath (Join-Path $dataDir 'app.so')) -or
    -not (Test-Path -LiteralPath (Join-Path $dataDir 'icudtl.dat')) -or
    -not (Test-Path -LiteralPath (Join-Path $dataDir 'flutter_assets'))) {
    throw "FALHA: Conteudo essencial de data/ ausente (app.so, icudtl.dat ou flutter_assets)."
}
Write-Host "[OK] Diretorio data/ contem app.so, icudtl.dat e flutter_assets." -ForegroundColor Green

# 4. Validar que nenhum lixo de build (.pdb, .ilk, .obj) esta no pacote de producao
$debugJunk = @(Get-ChildItem -Path $distDir -Recurse -Include @('*.pdb', '*.ilk', '*.obj', '*.exp', '*.lib'))
if ($debugJunk.Count -gt 0) {
    throw "FALHA: O pacote de producao contem lixo de build nao permitido: $($debugJunk | Select-Object -ExpandProperty Name -First 5 -join ', ')"
}
Write-Host "[OK] Zero arquivos de debug (.pdb/.ilk/.obj) presentes no pacote." -ForegroundColor Green

# 5. Validar o manifesto canônico cloudos-package-manifest.json
$pkgManifest = Join-Path $distDir 'manifests\cloudos-package-manifest.json'
if (-not (Test-Path -LiteralPath $pkgManifest)) {
    throw "FALHA: cloudos-package-manifest.json ausente no pacote."
}
$manifest = Get-Content -LiteralPath $pkgManifest -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1 -or -not $manifest.version -or -not $manifest.files) {
    throw "FALHA: Schema do cloudos-package-manifest.json e invalido."
}

# 6. Validar SHA256 de cada arquivo listado no manifesto
foreach ($entry in $manifest.files) {
    $itemPath = Join-Path $distDir $entry.path
    if (-not (Test-Path -LiteralPath $itemPath -PathType Leaf)) {
        throw "FALHA: Arquivo no manifesto nao existe no disco: $($entry.path)"
    }
    $actualHash = (Get-FileHash -LiteralPath $itemPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne ([string]$entry.sha256).ToLowerInvariant()) {
        throw "FALHA: Hash SHA256 adulterado para $($entry.path)"
    }
}
Write-Host "[OK] Hash SHA256 de todos os $($manifest.files.Count) arquivos do manifesto conferem perfeitamente." -ForegroundColor Green

Write-Host ">> CONTRATO 1/5 APROVADO COM SUCESSO (Layout Canonico Valido)." -ForegroundColor Green
return $true
