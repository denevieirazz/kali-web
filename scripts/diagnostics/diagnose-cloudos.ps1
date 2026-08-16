param([switch]$Open)
. (Join-Path $PSScriptRoot '..\launch\cloudos-launcher-common.ps1')
$session = Read-CloudOSCurrentSession
if (-not $session) {
    $latest = Get-ChildItem (Join-Path $script:CloudOSRoot 'logs') -Directory -Filter 'session-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $latest) { Write-Host 'Nenhuma sessão de logs encontrada.'; exit 1 }
    $manifestPath = Join-Path $latest.FullName 'manifest.json'
    if (-not (Test-Path $manifestPath)) { Write-Host "Sessão sem manifest: $($latest.FullName)"; exit 1 }
    $session = Get-Content $manifestPath -Raw | ConvertFrom-Json
}
Write-Host '=== CloudOS diagnóstico ==='
Write-Host "Sessão: $($session.id)"
Write-Host "Modo: $($session.mode)"
Write-Host "Status: $($session.status)"
Write-Host "Branch/SHA: $($session.git.branch) $($session.git.sha)"
Write-Host "Logs: $($session.logDirectory)"
foreach($record in @($session.processes)) {
    $p = Get-Process -Id ([int]$record.pid) -ErrorAction SilentlyContinue
    $alive = $false
    if ($p) {
        try { $alive = $p.StartTime.ToUniversalTime().ToString('o') -eq [string]$record.startedAt } catch { }
    }
    Write-Host ("{0,-10} pid={1,-7} alive={2}" -f $record.component,$record.pid,$alive)
}
$resultPath = Join-Path $session.logDirectory 'result.json'
if (Test-Path $resultPath) {
    $result = Get-Content $resultPath -Raw | ConvertFrom-Json
    if ($result.errorCode) { Write-Host "Erro: $($result.errorCode) — $($result.message)" -ForegroundColor Red }
}
foreach($name in @('backend.stderr.log','frontend.stderr.log','host.stderr.log')) {
    $path = Join-Path $session.logDirectory $name
    if (Test-Path $path) {
        $tail = @(Get-Content $path -Tail 8 -ErrorAction SilentlyContinue)
        if ($tail.Count) { Write-Host "--- $name ---"; $tail | ForEach-Object { Write-Host $_ } }
    }
}
if ($Open) { Start-Process explorer.exe -ArgumentList @($session.logDirectory) | Out-Null }
