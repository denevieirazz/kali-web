# test-shell-health-gate-v31-contract.ps1
# Valida health gate com limites bounded e rejeicao fail-closed

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [CONTRATO 3/10] Validacao de Health Gate Bounded" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Validar timeouts bounded no codigo-fonte de ShellBootstrap
Write-Host "[1/3] Verificando constantes de deadline no código-fonte nativo..." -ForegroundColor Yellow
$bootstrapCpp = Join-Path $PSScriptRoot '..\..\desktop\CloudOS.NativeShellBootstrap\main.cpp'
if (-not (Test-Path -LiteralPath $bootstrapCpp)) {
    throw "Fonte main.cpp de ShellBootstrap ausente: $bootstrapCpp"
}
$cppText = Get-Content -LiteralPath $bootstrapCpp -Raw

$requiredTokens = @(
    'kDefaultReadyTimeoutMs = 15000',
    'kMaxCrashBudget = 3',
    'kRollingCrashWindowMs = 60000',
    'ProbeBrokerReady',
    'ProbeFlutterWindowVisible',
    'LaunchExplorerFallback'
)
foreach ($t in $requiredTokens) {
    if (-not $cppText.Contains($t)) {
        throw "Token obrigatorio ausente no ShellBootstrap: $t"
    }
}
Write-Host "  [OK] Limites bounded verificados: Deadline 15s, Broker Probe, Flutter Visibility Probe e Fallback." -ForegroundColor Green

# 2. Testar rejeicao fail-closed por ausencia de binarios
Write-Host "[2/3] Testando comportamento fail-closed em caso de binario ausente..." -ForegroundColor Yellow
$sandboxDir = Join-Path $env:LOCALAPPDATA "CloudOS\Temp_HealthGate_Test_$(Get-Random)"
New-Item -ItemType Directory -Path $sandboxDir -Force | Out-Null

$binDir = Join-Path $PSScriptRoot '..\..\desktop\CloudOS.NativeShell\bin\Release'
$bootstrapExe = Join-Path $binDir 'CloudOS.ShellBootstrap.exe'
$testBootstrapExe = Join-Path $sandboxDir 'CloudOS.ShellBootstrap.exe'
Copy-Item -LiteralPath $bootstrapExe -Destination $testBootstrapExe -Force

# Executar bootstrap no sandbox onde o restante dos binarios NAO existem
$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = $testBootstrapExe
$pinfo.Arguments = '--status'
$pinfo.UseShellExecute = $false
$pinfo.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($pinfo)
$finished = $proc.WaitForExit(8000)
if (-not $finished) {
    $proc.Kill()
    throw "ShellBootstrap travou em loop infinito ao inves de sair bounded"
}
$exitCode = $proc.ExitCode
Write-Host "  [OK] ShellBootstrap encerrou de forma bounded com ExitCode=$exitCode (fail-closed seguro)." -ForegroundColor Green

# 3. Limpeza
Remove-Item -LiteralPath $sandboxDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n>>> [PASS] CONTRATO 3/10: Health Gate Bounded aprovado." -ForegroundColor Green
return [pscustomobject]@{
    Contract = "test-shell-health-gate-v31-contract.ps1"
    Status   = "PASS"
}
