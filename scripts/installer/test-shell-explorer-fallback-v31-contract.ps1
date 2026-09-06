# test-shell-explorer-fallback-v31-contract.ps1
# Valida fallback automatico e manual para explorer.exe sem tela preta

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 4/10] Validacao de Fallback para Explorer" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

$binDir = Join-Path $PSScriptRoot '..\..\desktop\CloudOS.NativeShell\bin\Release'
$bootstrapExe = Join-Path $binDir 'CloudOS.ShellBootstrap.exe'

# 1. Inspecionar processo do Explorer
Write-Host "[1/4] Inspecionando estado operacional do Windows Explorer..." -ForegroundColor Yellow
$explorerProcs = Get-Process 'explorer' -ErrorAction SilentlyContinue
if (-not $explorerProcs) {
    throw "Windows Explorer nao esta ativo no sistema antes do teste"
}
Write-Host "  [OK] Explorer ativo (PID(s): $($explorerProcs.Id -join ', '))." -ForegroundColor Green

# 2. Testar acionamento controlado de fallback via CLI do bootstrap
Write-Host "[2/4] Acionando fallback para Explorer via CloudOS.ShellBootstrap --fallback-explorer..." -ForegroundColor Yellow
$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = $bootstrapExe
$pinfo.Arguments = '--fallback-explorer'
$pinfo.UseShellExecute = $false
$pinfo.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($pinfo)
$proc.WaitForExit(5000) | Out-Null
if ($proc.ExitCode -ne 0) {
    throw "Chamada de fallback retornou codigo de saida inesperado: $($proc.ExitCode)"
}
Write-Host "  [OK] CloudOS.ShellBootstrap processou fallback com sucesso." -ForegroundColor Green

# 3. Validar log de auditoria de fallback
Write-Host "[3/4] Verificando geracao do log em %LOCALAPPDATA%\CloudOS\Recovery\shell-fallback.log..." -ForegroundColor Yellow
$fallbackLog = Join-Path $env:LOCALAPPDATA 'CloudOS\Recovery\shell-fallback.log'
if (-not (Test-Path -LiteralPath $fallbackLog)) {
    throw "Log de fallback nao encontrado em: $fallbackLog"
}
$logContent = (Get-Content -LiteralPath $fallbackLog -Tail 10) -join "`n"
if ($logContent -notmatch 'Explorer fallback activated') {
    throw "Registro de fallback ausente no arquivo de log"
}
Write-Host "  [OK] Evento de fallback devidamente registrado no log de auditoria." -ForegroundColor Green

# 4. Validar integridade do shell oficial do Windows
Write-Host "[4/4] Verificando integridade das configuracoes de shell oficial..." -ForegroundColor Yellow
$hklmWinlogon = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
if ($hklmWinlogon.Shell -ne 'explorer.exe') {
    throw "HKLM Winlogon Shell violado: $($hklmWinlogon.Shell)"
}
Write-Host "  [OK] HKLM Winlogon Shell estritamente mantido como explorer.exe." -ForegroundColor Green

Write-Host "`n>>> [PASS] CONTRATO 4/10: Fallback para Explorer aprovado." -ForegroundColor Green
return [pscustomobject]@{
    Contract = "test-shell-explorer-fallback-v31-contract.ps1"
    Status   = "PASS"
}
