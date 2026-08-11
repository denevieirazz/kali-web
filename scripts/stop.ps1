$Root = Split-Path -Parent $PSScriptRoot
$RuntimeDir = Join-Path $Root "runtime"

Write-Host "Encerrando instâncias do CloudOS-Unified..." -ForegroundColor Yellow

$BackendPortFile = Join-Path $RuntimeDir "backend-port.json"
if (Test-Path $BackendPortFile) {
    try {
        $data = Get-Content $BackendPortFile | ConvertFrom-Json
        if ($data.pid) {
            Stop-Process -Id $data.pid -Force -ErrorAction SilentlyContinue
            Write-Host "Backend encerrado (PID: $($data.pid))." -ForegroundColor Green
        }
    } catch {}
    Remove-Item $BackendPortFile -Force -ErrorAction SilentlyContinue
}

$FrontendPortFile = Join-Path $RuntimeDir "frontend-port.json"
if (Test-Path $FrontendPortFile) {
    try {
        $data = Get-Content $FrontendPortFile | ConvertFrom-Json
        if ($data.pid) {
            Stop-Process -Id $data.pid -Force -ErrorAction SilentlyContinue
            Write-Host "Frontend encerrado (PID: $($data.pid))." -ForegroundColor Green
        }
    } catch {}
    Remove-Item $FrontendPortFile -Force -ErrorAction SilentlyContinue
}

Write-Host "Processos finalizados." -ForegroundColor Cyan
