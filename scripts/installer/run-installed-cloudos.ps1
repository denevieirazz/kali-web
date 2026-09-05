[CmdletBinding()]
param()

$installDir = Join-Path $env:LOCALAPPDATA 'Programs\CloudOS'
$cloudosExe = Join-Path $installDir 'CloudOS.exe'
$probeExe   = Join-Path $installDir 'CloudOS.BrokerProbe.exe'

if (-not (Test-Path -LiteralPath $cloudosExe)) {
    throw "CloudOS.exe nao encontrado em $installDir"
}

Write-Host "Iniciando CloudOS a partir de $cloudosExe..." -ForegroundColor Cyan
$proc = Start-Process -FilePath $cloudosExe -WorkingDirectory $installDir -PassThru

Start-Sleep -Seconds 4

$processes = Get-Process -Name 'CloudOS*', 'cloudos*' -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, Path
Write-Host "Processos ativos do CloudOS:" -ForegroundColor Green
$processes | Format-Table -AutoSize

Write-Host "`nTestando handshake com o Broker probe..." -ForegroundColor Cyan
$probeOutput = & $probeExe ping
Write-Host "Broker ping output: $probeOutput" -ForegroundColor Green

return [pscustomobject]@{
    LaunchedProcessId = $proc.Id
    RunningCount = ($processes | Measure-Object).Count
    BrokerPing = $probeOutput
}
