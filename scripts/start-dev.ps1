$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$Root = Split-Path -Parent $PSScriptRoot
$RuntimeDir = Join-Path $Root 'runtime'
$LogDir = Join-Path $Root 'logs'

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
if (-not (Test-Path $RuntimeDir)) { New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null }

Write-Host '=========================================' -ForegroundColor Cyan
Write-Host '  CloudOS-Unified - Iniciando (Windows)  ' -ForegroundColor Cyan
Write-Host '=========================================' -ForegroundColor Cyan

$NodeExe = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
if (-not $NodeExe) { $NodeExe = 'C:\Users\dougl\AppData\Local\hermes\node\node.exe' }

# 1. Prevenção de duplicação: verificar se backend já está rodando
$BackendPortFile = Join-Path $RuntimeDir 'backend-port.json'
$BackendRunning = $false
if (Test-Path $BackendPortFile) {
    try {
        $bExisting = Get-Content $BackendPortFile | ConvertFrom-Json
        if ($bExisting.pid) {
            $p = Get-Process -Id $bExisting.pid -ErrorAction Stop
            Write-Host "AVISO: Backend ja esta rodando (PID $($bExisting.pid), Porta $($bExisting.backendPort)). Nao duplicando." -ForegroundColor Yellow
            $BackendRunning = $true
        }
    } catch {
        Remove-Item $BackendPortFile -Force -ErrorAction SilentlyContinue
    }
}

if (-not $BackendRunning) {
    Write-Host '[1/4] Iniciando Backend...' -ForegroundColor Yellow
    $bSrv = Join-Path $Root 'backend\src\server.js'
    $bDir = Join-Path $Root 'backend'
    $bCmd = """$NodeExe"" ""$bSrv"""
    $bProc = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=$bCmd; CurrentDirectory=$bDir}

    # Aguardar runtime file do backend
    $Elapsed = 0
    while (-not (Test-Path $BackendPortFile) -and ($Elapsed -lt 15)) {
        Start-Sleep -Seconds 1
        $Elapsed++
    }

    if (-not (Test-Path $BackendPortFile)) {
        Write-Host 'ERRO: Backend nao gerou runtime em 15s.' -ForegroundColor Red
        exit 1
    }
}

$BackendInfo = Get-Content $BackendPortFile | ConvertFrom-Json
$bPort = $BackendInfo.backendPort
$bPid = $BackendInfo.pid
Write-Host "  Backend ativo: http://127.0.0.1:$bPort (PID $bPid)" -ForegroundColor Green

# 2. Health check real do backend
try {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:$bPort/api/health" -Method Get -TimeoutSec 5
    Write-Host "  Health check: $($health.status)" -ForegroundColor Green
} catch {
    Write-Host "  AVISO: Health check falhou: $_" -ForegroundColor Yellow
}

# 3. Prevenção de duplicação: verificar frontend
$FrontendPortFile = Join-Path $RuntimeDir 'frontend-port.json'
$FrontendRunning = $false
if (Test-Path $FrontendPortFile) {
    try {
        $fExisting = Get-Content $FrontendPortFile | ConvertFrom-Json
        if ($fExisting.pid) {
            $p = Get-Process -Id $fExisting.pid -ErrorAction Stop
            Write-Host "AVISO: Frontend ja esta rodando (PID $($fExisting.pid), Porta $($fExisting.port)). Nao duplicando." -ForegroundColor Yellow
            $FrontendRunning = $true
        }
    } catch {
        Remove-Item $FrontendPortFile -Force -ErrorAction SilentlyContinue
    }
}

if (-not $FrontendRunning) {
    Write-Host '[2/4] Iniciando Frontend Vite...' -ForegroundColor Yellow
    $fDev = Join-Path $Root 'frontend\scripts\dev-server.js'
    $fDir = Join-Path $Root 'frontend'
    $fCmd = """$NodeExe"" ""$fDev"""
    $fProc = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=$fCmd; CurrentDirectory=$fDir}

    # Aguardar runtime file do frontend
    $Elapsed = 0
    while (-not (Test-Path $FrontendPortFile) -and ($Elapsed -lt 20)) {
        Start-Sleep -Seconds 1
        $Elapsed++
    }
}

$FrontendPort = 15173
if (Test-Path $FrontendPortFile) {
    $FrontendInfo = Get-Content $FrontendPortFile | ConvertFrom-Json
    $FrontendPort = $FrontendInfo.port
    $fPid = $FrontendInfo.pid
    Write-Host "  Frontend ativo: http://127.0.0.1:$FrontendPort (PID $fPid)" -ForegroundColor Green
} else {
    Write-Host '  AVISO: Frontend runtime nao detectado, usando porta padrao' -ForegroundColor Yellow
}

# 4. Verificar resposta HTTP do Frontend
Write-Host '[3/4] Verificando resposta HTTP do Frontend...' -ForegroundColor Yellow
$Elapsed = 0
$FrontendReady = $false
while (-not $FrontendReady -and ($Elapsed -lt 10)) {
    try {
        $res = Invoke-WebRequest -Uri "http://127.0.0.1:$FrontendPort" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        if ($res.StatusCode -eq 200) {
            $FrontendReady = $true
        }
    } catch {
        Start-Sleep -Seconds 1
        $Elapsed++
    }
}

if ($FrontendReady) {
    Write-Host "  Frontend respondendo HTTP 200 OK" -ForegroundColor Green
} else {
    Write-Host '  AVISO: Frontend demorou para responder' -ForegroundColor Yellow
}

# 5. Abrir navegador
Write-Host '[4/4] Abrindo navegador...' -ForegroundColor Green
Start-Process "http://127.0.0.1:$FrontendPort"

Write-Host '=========================================' -ForegroundColor Cyan
Write-Host '  CloudOS-Unified iniciado com sucesso!  ' -ForegroundColor Cyan
Write-Host '=========================================' -ForegroundColor Cyan
