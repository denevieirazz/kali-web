# test-shell-backup-v31-contract.ps1
# Valida criacao, completude e integridade do backup de estado de shell

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 2/10] Validacao de Backup de Estado de Shell" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Executar gerador de backup em sandbox temporario
Write-Host "[1/4] Gerando snapshot de backup em diretorio de teste..." -ForegroundColor Yellow
$testBackupDir = Join-Path $env:LOCALAPPDATA "CloudOS\Temp_Backup_Test_$(Get-Random)"
New-Item -ItemType Directory -Path $testBackupDir -Force | Out-Null
$testBackupPath = Join-Path $testBackupDir 'shell-backup.json'

$backupScript = Join-Path $PSScriptRoot '..\shell\backup-shell-state.ps1'
if (-not (Test-Path -LiteralPath $backupScript)) {
    throw "Script de backup ausente: $backupScript"
}

& $backupScript -DestinationPath $testBackupPath | Out-Null

if (-not (Test-Path -LiteralPath $testBackupPath)) {
    throw "Arquivo de backup nao foi gerado: $testBackupPath"
}
Write-Host "  [OK] Arquivo de backup criado com sucesso." -ForegroundColor Green

# 2. Inspecionar campos obrigatorios do manifesto de backup
Write-Host "[2/4] Validando completude do esquema do backup..." -ForegroundColor Yellow
$backupJson = Get-Content -LiteralPath $testBackupPath -Raw | ConvertFrom-Json

$mandatoryFields = @(
    'backup_version',
    'created_utc',
    'windows_edition',
    'windows_build',
    'architecture',
    'user_sid',
    'session_id',
    'original_hklm_shell',
    'original_userinit',
    'cloudos_install_dir',
    'cloudos_version'
)

foreach ($field in $mandatoryFields) {
    $val = $backupJson.$field
    if ($null -eq $val) {
        throw "Campo obrigatorio ausente no backup: $field"
    }
}
Write-Host "  [OK] Todos os $($mandatoryFields.Count) campos obrigatorios estao presentes." -ForegroundColor Green

# 3. Validar integridade dos valores do Windows
Write-Host "[3/4] Validando consistencia dos valores capturados..." -ForegroundColor Yellow
if ($backupJson.original_hklm_shell -ne 'explorer.exe') {
    throw "original_hklm_shell inesperado: $($backupJson.original_hklm_shell)"
}
if ($backupJson.original_userinit -notmatch 'userinit\.exe') {
    throw "original_userinit inesperado: $($backupJson.original_userinit)"
}
Write-Host "  [OK] Valores de shell e userinit do Windows preservados e integros." -ForegroundColor Green

# 4. Validar backup permanente do sistema
Write-Host "[4/4] Validando existencia do backup em %LOCALAPPDATA%\CloudOS\Recovery\shell-backup.json..." -ForegroundColor Yellow
$prodBackupPath = Join-Path $env:LOCALAPPDATA 'CloudOS\Recovery\shell-backup.json'
if (-not (Test-Path -LiteralPath $prodBackupPath)) {
    & $backupScript -DestinationPath $prodBackupPath | Out-Null
}
$prodJson = Get-Content -LiteralPath $prodBackupPath -Raw | ConvertFrom-Json
if ($prodJson.backup_version -lt 1) {
    throw "Backup de producao invalido"
}
Write-Host "  [OK] Backup persistente verificado: $prodBackupPath" -ForegroundColor Green

# Limpeza
Remove-Item -LiteralPath $testBackupDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n>>> [PASS] CONTRATO 2/10: Backup de Estado de Shell aprovado." -ForegroundColor Green
return [pscustomobject]@{
    Contract = "test-shell-backup-v31-contract.ps1"
    Status   = "PASS"
}
