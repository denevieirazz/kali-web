$Root = Split-Path -Parent $PSScriptRoot
$RuntimeDir = Join-Path $Root "runtime"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   Diagnóstico de Saúde CloudOS-Unified  " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$BackendPortFile = Join-Path $RuntimeDir "backend-port.json"
if (Test-Path $BackendPortFile) {
    $bData = Get-Content $BackendPortFile | ConvertFrom-Json
    Write-Host "Backend registrado em: http://$($bData.host):$($bData.backendPort) (PID: $($bData.pid))" -ForegroundColor Green
    try {
        $res = Invoke-RestMethod -Uri "http://$($bData.host):$($bData.backendPort)/api/health" -Method Get -TimeoutSec 3
        Write-Host "  -> Health Check: OK ($($res.service))" -ForegroundColor Green
    } catch {
        Write-Host "  -> Health Check: FALHOU ($($_.Exception.Message))" -ForegroundColor Red
    }
} else {
    Write-Host "Backend não está rodando (arquivo runtime ausente)." -ForegroundColor Yellow
}

$FrontendPortFile = Join-Path $RuntimeDir "frontend-port.json"
if (Test-Path $FrontendPortFile) {
    $fData = Get-Content $FrontendPortFile | ConvertFrom-Json
    Write-Host "Frontend registrado em: http://$($fData.host):$($fData.port) (PID: $($fData.pid))" -ForegroundColor Green
} else {
    Write-Host "Frontend não está rodando." -ForegroundColor Yellow
}
