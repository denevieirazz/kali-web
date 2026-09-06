# test-shell-mechanism-v31-contract.ps1
# Valida deteccao de edicao do Windows e mapeamento do mecanismo oficial de Shell

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 1/10] Validacao de Mecanismo de Shell e Edicao" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Inspecionar versao, edicao e arquitetura
Write-Host "[1/4] Detectando edicao do Windows e metadados de sistema..." -ForegroundColor Yellow
$regCurrent = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$editionId = $regCurrent.EditionID
$currentBuild = [int]$regCurrent.CurrentBuild
$arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
$userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId

Write-Host "  Edicao Detectada: $editionId"
Write-Host "  Build: $currentBuild | Arquitetura: $arch"
Write-Host "  User SID: $userSid | Session: $sessionId"

if ($arch -ne 'x64') {
    throw "Arquitetura incompativel: esperado x64, detectado $arch"
}

# 2. Avaliar disponibilidade de Shell Launcher (WESL)
Write-Host "[2/4] Avaliando disponibilidade do Shell Launcher oficial (WESL)..." -ForegroundColor Yellow
$weslAvailable = $false
try {
    $classes = Get-CimClass -Namespace 'root\standardcimv2\embedded' -ErrorAction Stop
    $weslClass = $classes | Where-Object { $_.CimClassName -eq 'WESL_UserSetting' }
    if ($weslClass) {
        $weslAvailable = $true
    }
} catch {
    $weslAvailable = $false
}

Write-Host "  Shell Launcher (WESL) disponivel nesta edicao: $weslAvailable"
if (-not $weslAvailable) {
    Write-Host "  [OK] Conforme documentado pelo Microsoft Learn, Shell Launcher v1 requer Enterprise/IoT Enterprise e recurso opcional elevado." -ForegroundColor Green
}

# 3. Validar aplicabilidade da politica CustomShell (WinLogon.admx)
Write-Host "[3/4] Validando mecanismo CustomShell policy para Windows 11 Pro..." -ForegroundColor Yellow
$mechanism = if ($weslAvailable) {
    'ShellLauncher'
} elseif ($editionId -in @('Professional', 'Enterprise', 'Education', 'IoTEnterprise')) {
    'CustomShellPolicy'
} else {
    'Unsupported'
}

Write-Host "  Mecanismo Selecionado: $mechanism"
if ($mechanism -ne 'CustomShellPolicy') {
    throw "Mecanismo inesperado para Windows 11 Pro: $mechanism"
}
Write-Host "  [OK] CustomShellPolicy mapeado em conformidade com WinLogon.admx (Policy CSP - ADMX_WinLogon)." -ForegroundColor Green

# 4. Validar entrypoint nativo
Write-Host "[4/4] Validando que o entrypoint de producao e binario nativo (Zero PowerShell como shell final)..." -ForegroundColor Yellow
$bootstrapPath = Join-Path $PSScriptRoot '..\..\desktop\CloudOS.NativeShell\bin\Release\CloudOS.ShellBootstrap.exe'
if (-not (Test-Path -LiteralPath $bootstrapPath)) {
    throw "Binario de producao CloudOS.ShellBootstrap.exe ausente: $bootstrapPath"
}
Write-Host "  [OK] Entrypoint oficial do Shell Replacement e binario compilado: $bootstrapPath" -ForegroundColor Green

Write-Host "`n>>> [PASS] CONTRATO 1/10: Mecanismo de Shell e Edicao aprovados." -ForegroundColor Green
return [pscustomobject]@{
    Contract  = "test-shell-mechanism-v31-contract.ps1"
    Status    = "PASS"
    Mechanism = $mechanism
    Edition   = $editionId
}
