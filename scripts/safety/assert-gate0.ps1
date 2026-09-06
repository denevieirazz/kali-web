[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$recoveryExe = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.Recovery.exe'

Write-Host "[SAFETY ASSERTION] Validando condicao estrita do GATE 0..." -ForegroundColor Cyan

if (Test-Path -LiteralPath $recoveryExe) {
    $rawOutput = & $recoveryExe status
    if ($LASTEXITCODE -ne 0) {
        throw "CloudOS.Recovery.exe retornou erro $LASTEXITCODE ao consultar status."
    }

    $status = $rawOutput | ConvertFrom-Json

    # 1. Effective shell deve ser explorer.exe
    if ($status.effective_shell -ne 'explorer.exe') {
        throw "GATE 0 VIOLATION: effective_shell e '$($status.effective_shell)', esperava 'explorer.exe'."
    }

    # 2. HKLM Winlogon shell deve ser explorer.exe
    if ($status.hklm_winlogon_shell -ne 'explorer.exe') {
        throw "GATE 0 VIOLATION: hklm_winlogon_shell e '$($status.hklm_winlogon_shell)', esperava 'explorer.exe'."
    }

    # 3. Userinit deve estar intacto
    if (-not $status.userinit_intact) {
        throw "GATE 0 VIOLATION: userinit_intact e falso. Userinit: $($status.userinit)"
    }

    # 4. HKCU Policy shell e Winlogon shell devem ser vazios
    if (-not [string]::IsNullOrEmpty($status.hkcu_policy_shell)) {
        throw "GATE 0 VIOLATION: hkcu_policy_shell configurado: '$($status.hkcu_policy_shell)'."
    }
    if (-not [string]::IsNullOrEmpty($status.hkcu_winlogon_shell)) {
        throw "GATE 0 VIOLATION: hkcu_winlogon_shell configurado: '$($status.hkcu_winlogon_shell)'."
    }

    # 5. Explorer deve estar em execucao (em ambiente interativo)
    if (-not $env:GITHUB_ACTIONS -and -not $env:CI) {
        if (-not $status.explorer_running) {
            throw "GATE 0 VIOLATION: explorer.exe nao esta em execucao no sistema."
        }
    }

    Write-Host "  [OK] effective_shell:    $($status.effective_shell)" -ForegroundColor Green
    Write-Host "  [OK] hklm_winlogon:     $($status.hklm_winlogon_shell)" -ForegroundColor Green
    Write-Host "  [OK] userinit_intact:    $($status.userinit_intact)" -ForegroundColor Green
    Write-Host "  [OK] hkcu_policy_shell:  (Vazio / Nao configurado)" -ForegroundColor Green
    Write-Host "  [OK] hkcu_winlogon_shell:(Vazio / Nao configurado)" -ForegroundColor Green
    Write-Host "  [OK] explorer_running:   $($status.explorer_running)" -ForegroundColor Green
} else {
    Write-Host "  [INFO] CloudOS.Recovery.exe ainda nao compilado (ambiente pre-build CI). Validando chaves de registro diretamente..." -ForegroundColor Yellow
    $hklmWinlogon = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
    $hklmShell = if ($hklmWinlogon -and $hklmWinlogon.Shell) { $hklmWinlogon.Shell } else { 'explorer.exe' }
    if ($hklmShell -ne 'explorer.exe') {
        throw "GATE 0 VIOLATION: HKLM Winlogon Shell e '$hklmShell', esperava 'explorer.exe'."
    }

    $hkcuWinlogon = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
    if ($hkcuWinlogon -and -not [string]::IsNullOrEmpty($hkcuWinlogon.Shell)) {
        throw "GATE 0 VIOLATION: HKCU Winlogon Shell configurado: '$($hkcuWinlogon.Shell)'."
    }

    $hkcuPolicy = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue
    if ($hkcuPolicy -and -not [string]::IsNullOrEmpty($hkcuPolicy.Shell)) {
        throw "GATE 0 VIOLATION: HKCU Policy Shell configurado: '$($hkcuPolicy.Shell)'."
    }

    Write-Host "  [OK] HKLM Winlogon Shell: $hklmShell" -ForegroundColor Green
    Write-Host "  [OK] HKCU Winlogon Shell: (Vazio)" -ForegroundColor Green
    Write-Host "  [OK] HKCU Policy Shell:   (Vazio)" -ForegroundColor Green
}

Write-Host "[GATE 0 INTACT] Windows Explorer e o shell oficial ativo e sem persistencia CloudOS." -ForegroundColor Green
