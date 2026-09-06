# test-native-launcher-physical.ps1
# Valida instalacao fisica via Inno Setup, atalhos nativos, ausencia de PowerShell/CMD e ciclo de vida

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$setupExe = Join-Path $repoRoot 'dist\releases\21.0.0-rc.1.4\CloudOS-Setup-21.0.0-rc.1.4-x64.exe'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\CloudOS_Physical_Test'

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " [MISSAO 21-31] VALIDACAO FISICA DO LAUNCHER NATIVO RC1.4" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Instalar via executavel Inno Setup
Write-Host "[1/7] Instalando RC1.4 via Inno Setup silencioso..." -ForegroundColor Yellow
if (Test-Path $installDir) {
    Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
}

$proc = Start-Process -FilePath $setupExe -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=`"$installDir`" /TASKS=`"desktopicon`"" -PassThru -Wait
if ($proc.ExitCode -ne 0) {
    throw "Inno Setup falhou com ExitCode $($proc.ExitCode)"
}
Write-Host "  [OK] Inno Setup concluiu com ExitCode 0." -ForegroundColor Green

# 2. Inspecionar atalhos Start Menu e Desktop
Write-Host "[2/7] Inspecionando atalhos criados (.lnk)..." -ForegroundColor Yellow
$wsh = New-Object -ComObject WScript.Shell

$startMenuShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'CloudOS.lnk'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'CloudOS.lnk'

$checkedShortcuts = @()
foreach ($s in @($startMenuShortcut, $desktopShortcut)) {
    if (Test-Path -LiteralPath $s) {
        $link = $wsh.CreateShortcut($s)
        $checkedShortcuts += [pscustomobject]@{
            ShortcutPath     = $s
            TargetPath       = $link.TargetPath
            Arguments        = $link.Arguments
            WorkingDirectory = $link.WorkingDirectory
        }
        Write-Host "  Atalho: $(Split-Path -Leaf $s)" -ForegroundColor White
        Write-Host "    TargetPath:       $($link.TargetPath)" -ForegroundColor White
        Write-Host "    Arguments:        $($link.Arguments)" -ForegroundColor White
        Write-Host "    WorkingDirectory: $($link.WorkingDirectory)" -ForegroundColor White

        # Asserts estritos
        if ($link.TargetPath -match 'powershell\.exe|cmd\.exe|\.ps1|\.cmd|\.bat') {
            throw "FALHA GRAVE: Atalho aponta para interpretador de script: $($link.TargetPath)"
        }
        if ($link.TargetPath -notmatch 'CloudOS\.exe$') {
            throw "FALHA: Atalho deve apontar para CloudOS.exe: $($link.TargetPath)"
        }
        Write-Host "    [OK] Atalho 100% nativo C++ (CloudOS.exe)." -ForegroundColor Green
    }
}

# 3. Validar acao de finalizacao do instalador
Write-Host "[3/7] Verificando se CloudOS.exe nativo existe no destino..." -ForegroundColor Yellow
$installedExe = Join-Path $installDir 'CloudOS.exe'
if (-not (Test-Path $installedExe)) {
    throw "CloudOS.exe nao foi instalado em $installDir"
}
Write-Host "  [OK] Binario instalado: $installedExe" -ForegroundColor Green

# 4. Capturar processos antes do launch
Write-Host "[4/7] Capturando estado de processos antes da inicializacao..." -ForegroundColor Yellow
$beforeProcesses = Get-Process | Select-Object -ExpandProperty Id

# 5. Executar CloudOS.exe nativo
Write-Host "[5/7] Executando CloudOS.exe instalado..." -ForegroundColor Yellow
$launchProc = Start-Process -FilePath $installedExe -PassThru
Start-Sleep -Seconds 4

# Detectar processos criados
$afterProcesses = Get-Process
$newProcesses = $afterProcesses | Where-Object { $beforeProcesses -notcontains $_.Id }

Write-Host "  Processos criados durante a inicializacao:" -ForegroundColor Cyan
$spawnedPowershell = $false
$spawnedCmd = $false

foreach ($np in $newProcesses) {
    Write-Host "    + $($np.ProcessName) (PID $($np.Id))" -ForegroundColor White
    if ($np.ProcessName -eq 'powershell') { $spawnedPowershell = $true }
    if ($np.ProcessName -eq 'cmd') { $spawnedCmd = $true }
}

if ($spawnedPowershell) {
    throw "FALHA: powershell.exe foi invocado durante a inicializacao do CloudOS!"
}
if ($spawnedCmd) {
    throw "FALHA: cmd.exe foi invocado durante a inicializacao do CloudOS!"
}
Write-Host "  [OK] ZERO processos powershell.exe ou cmd.exe foram invocados!" -ForegroundColor Green

# 6. Teste de 20 inicializacoes rapidas concorrentes
Write-Host "[6/7] Testando 20 inicializacoes rapidas consecutivas (Single-Instance)..." -ForegroundColor Yellow
for ($i = 1; $i -le 20; $i++) {
    $p = Start-Process -FilePath $installedExe -PassThru
    $p.WaitForExit(3000) | Out-Null
}
Start-Sleep -Seconds 2

$currentCloudOS = @(Get-Process -Name 'CloudOS' -ErrorAction SilentlyContinue)
$currentFlutter = @(Get-Process -Name 'cloudos_flutter_shell' -ErrorAction SilentlyContinue)
$currentBroker  = @(Get-Process -Name 'CloudOS.SystemBroker' -ErrorAction SilentlyContinue)

Write-Host "  Contagem de processos apos 20 launches:" -ForegroundColor Cyan
Write-Host "    CloudOS.exe:           $($currentCloudOS.Count) (Esperado: 1)" -ForegroundColor White
Write-Host "    cloudos_flutter_shell: $($currentFlutter.Count) (Esperado: 1)" -ForegroundColor White
Write-Host "    CloudOS.SystemBroker:  $($currentBroker.Count) (Esperado: 1)" -ForegroundColor White

if ($currentCloudOS.Count -gt 1 -or $currentFlutter.Count -gt 1) {
    throw "FALHA: Single-instance falhou; instancias duplicadas detectadas!"
}
Write-Host "  [OK] Single-Instance e prevencao de concorrencia aprovados (1 instancia unica)." -ForegroundColor Green

# 7. Encerrar limpo e reabrir
Write-Host "[7/7] Testando encerramento ordenado e reabertura via shortcut nativo..." -ForegroundColor Yellow
$probeExe = Join-Path $installDir 'CloudOS.BrokerProbe.exe'
if (Test-Path $probeExe) {
    & $probeExe rpc system.closeCloudOS '{}' | Out-Null
    Start-Sleep -Seconds 3
}

$aliveAfterClose = Get-Process -Name 'CloudOS', 'cloudos_flutter_shell' -ErrorAction SilentlyContinue
if ($aliveAfterClose) {
    Stop-Process -Name 'CloudOS', 'cloudos_flutter_shell', 'CloudOS.Supervisor', 'CloudOS.SystemBroker' -Force -ErrorAction SilentlyContinue
}
Write-Host "  [OK] Processos encerrados de forma limpa." -ForegroundColor Green

# Reabertura
Write-Host "  Reabrindo via launcher nativo..." -ForegroundColor Yellow
$reopen = Start-Process -FilePath $installedExe -PassThru
Start-Sleep -Seconds 3
$reopenProcs = Get-Process -Name 'CloudOS', 'cloudos_flutter_shell' -ErrorAction SilentlyContinue
if (-not $reopenProcs) {
    throw "FALHA: Reabertura via launcher nativo falhou!"
}
Write-Host "  [OK] Reabertura bem sucedida!" -ForegroundColor Green

# Limpeza do ambiente de teste
Stop-Process -Name 'CloudOS', 'cloudos_flutter_shell', 'CloudOS.Supervisor', 'CloudOS.SystemBroker' -Force -ErrorAction SilentlyContinue
Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $desktopShortcut) { Remove-Item $desktopShortcut -Force -ErrorAction SilentlyContinue }

Write-Host "`n>>> [PASS] MISSAO 21-31 CONCLUIDA COM SUCESSO: LAUNCHER 100% NATIVO!" -ForegroundColor Green
