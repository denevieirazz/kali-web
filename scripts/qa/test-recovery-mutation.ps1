$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$testRoot = Join-Path $env:LOCALAPPDATA 'Temp\cloudos_recovery_mutation_test'
if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force }
Copy-Item (Join-Path $repoRoot 'dist\CloudOS') $testRoot -Recurse -Force

Write-Host '--- 1. Verification of pristine sandbox ---' -ForegroundColor Cyan
$recExe = Join-Path $testRoot 'CloudOS.Recovery.exe'
$initial = & $recExe verify | ConvertFrom-Json
Write-Host ("Verified={0}, Corrupt={1}, Missing={2}, SHA256={3}" -f $initial.verified, $initial.corrupt_components, $initial.missing_components, $initial.sha256_verified)

Write-Host '--- 2. Mutating ONE byte in CloudOS.exe ---' -ForegroundColor Cyan
$targetExe = Join-Path $testRoot 'CloudOS.exe'
$bytes = [System.IO.File]::ReadAllBytes($targetExe)
$bytes[512] = [byte]($bytes[512] -bxor 0xFF)
[System.IO.File]::WriteAllBytes($targetExe, $bytes)

$mutated = & $recExe verify | ConvertFrom-Json
Write-Host ("Apos mutacao: Verified={0}, Corrupt={1}, Missing={2}" -f $mutated.verified, $mutated.corrupt_components, $mutated.missing_components)
if ($mutated.corrupt_components -ne 1 -or $mutated.verified -ne $false) {
    throw 'FALHA: Mutacao de 1 byte NAO foi detectada como corrupcao SHA256!'
}
Write-Host '[PASS] Mutacao de 1 byte detectada com precisao criptografica SHA256!' -ForegroundColor Green

Write-Host '--- 3. Deletando arquivo essencial (cloudos_flutter_shell.exe) ---' -ForegroundColor Cyan
$flutterExe = Join-Path $testRoot 'cloudos_flutter_shell.exe'
Remove-Item $flutterExe -Force

$missingRes = & $recExe verify | ConvertFrom-Json
Write-Host ("Apos remocao: Verified={0}, Corrupt={1}, Missing={2}" -f $missingRes.verified, $missingRes.corrupt_components, $missingRes.missing_components)
if ($missingRes.missing_components -ne 1) {
    throw 'FALHA: Remocao de arquivo NAO foi detectada!'
}
Write-Host '[PASS] Arquivo ausente detectado com sucesso!' -ForegroundColor Green

Write-Host '--- 4. Reparando sandbox a partir do pacote canonico ---' -ForegroundColor Cyan
& (Join-Path $repoRoot 'scripts\installer\CloudOS.Maintenance.ps1') -Action repair -InstallDir $testRoot -PackageDir (Join-Path $repoRoot 'dist\CloudOS')

$repaired = & $recExe verify | ConvertFrom-Json
Write-Host ("Apos repair: Verified={0}, Corrupt={1}, Missing={2}, SHA256={3}" -f $repaired.verified, $repaired.corrupt_components, $repaired.missing_components, $repaired.sha256_verified)
if ($repaired.verified -ne $true -or $repaired.corrupt_components -ne 0 -or $repaired.missing_components -ne 0) {
    throw 'FALHA: Repair nao restaurou a integridade completa!'
}
Write-Host '[PASS] Sandbox 100% reparado com SHA256 restaurado!' -ForegroundColor Green

Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "MISSION 32-35 COMPLETE: ALL ASSERTS PASSED." -ForegroundColor Green
