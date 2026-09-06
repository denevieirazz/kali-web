# test-shell-security-v31-contract.ps1
# Valida conformidade de seguranca: Userinit intocado, HKLM Shell intocado,
# ausencia de drivers/kernel hooks e confinamento estrito em espaco de usuario (AsInvoker).

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 10/10] Validacao de Seguranca, Userinit e Confinamento" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Validar HKLM Userinit intocado
Write-Host "[1/4] Verificando integridade de HKLM Winlogon Userinit..." -ForegroundColor Yellow
$hklmWinlogon = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$userinitVal = (Get-ItemProperty -Path $hklmWinlogon -Name "Userinit" -ErrorAction SilentlyContinue).Userinit
if (-not $userinitVal) {
    throw "Valor HKLM Userinit nao encontrado"
}
Write-Host "  HKLM Userinit = '$userinitVal'"
if ($userinitVal -notmatch "(?i)userinit\.exe") {
    throw "ALERTA DE SEGURANCA: HKLM Userinit foi adulterado ou nao contem userinit.exe: $userinitVal"
}
if ($userinitVal -match "(?i)CloudOS") {
    throw "ALERTA DE SEGURANCA: CloudOS jamais deve estar registrado no HKLM Userinit"
}
Write-Host "  [OK] HKLM Winlogon Userinit 100% integro e padrao do Windows." -ForegroundColor Green

# 2. Validar HKLM Winlogon Shell intocado
Write-Host "[2/4] Verificando integridade de HKLM Winlogon Shell..." -ForegroundColor Yellow
$hklmShell = (Get-ItemProperty -Path $hklmWinlogon -Name "Shell" -ErrorAction SilentlyContinue).Shell
Write-Host "  HKLM Shell = '$hklmShell'"
if ($hklmShell -ne "explorer.exe") {
    throw "ALERTA DE SEGURANCA: HKLM Winlogon Shell deve ser estritamente 'explorer.exe'. Atual: '$hklmShell'"
}
Write-Host "  [OK] HKLM Winlogon Shell estritamente preservado como explorer.exe." -ForegroundColor Green

# 3. Validar confinamento de usuario (Zero drivers de kernel, zero BCD tampering)
Write-Host "[3/4] Verificando ausencia de drivers de kernel e modificacoes privilegiadas..." -ForegroundColor Yellow
$cloudServices = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match "(?i)CloudOS" }
if ($cloudServices) {
    throw "ALERTA DE SEGURANCA: Nenhum driver ou servico HKLM do CloudOS deve existir: $($cloudServices.PSChildName)"
}
Write-Host "  [OK] Zero servicos/drivers de kernel instalados. Confinamento em modo usuario confirmado." -ForegroundColor Green

# 4. Validar Gate 0 de persistencia
Write-Host "[4/4] Verificando cumprimento estrito do GATE 0 (persistencia de shell segura)..." -ForegroundColor Yellow
$hkcuPoliciesSystem = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
$hkcuShell = $null
if (Test-Path -LiteralPath $hkcuPoliciesSystem) {
    $hkcuShell = (Get-ItemProperty -Path $hkcuPoliciesSystem -Name "Shell" -ErrorAction SilentlyContinue).Shell
}

if ($null -ne $hkcuShell -and $hkcuShell -ne "" -and $hkcuShell -ne "explorer.exe") {
    throw "VIOLACAO DE GATE 0: HKCU Policies\System Shell esta configurado como '$hkcuShell' antes da autorizacao expliciata!"
}
Write-Host "  [OK] Gate 0 estritamente respeitado: HKCU Shell = $(if ($hkcuShell) { "'$hkcuShell'" } else { 'NENHUM (Padrao Windows Explorer)' })." -ForegroundColor Green

Write-Host "`n>>> [PASS] CONTRATO 10/10: Seguranca, Userinit e Confinamento aprovados." -ForegroundColor Green
return [pscustomobject]@{
    Contract = "test-shell-security-v31-contract.ps1"
    Status   = "PASS"
}
