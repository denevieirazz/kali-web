Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CloudOSOwnedSessionManifest {
    param([Parameter(Mandatory)]$Session)
    if (-not $Session.id) { throw 'SESSION_OWNERSHIP_ID_MISSING' }
    if (-not $Session.logDirectory) { throw 'SESSION_OWNERSHIP_LOG_DIRECTORY_MISSING' }
    $manifestPath = Join-Path ([string]$Session.logDirectory) 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "SESSION_OWNERSHIP_MANIFEST_MISSING:$manifestPath" }
    try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
    catch { throw "SESSION_OWNERSHIP_MANIFEST_INVALID:${manifestPath}:$($_.Exception.Message)" }
    if ([string]$manifest.id -ne [string]$Session.id) { throw "SESSION_OWNERSHIP_MANIFEST_ID_MISMATCH:expected=$($Session.id):actual=$($manifest.id)" }
    if ([string]$manifest.logDirectory -ne [string]$Session.logDirectory) { throw 'SESSION_OWNERSHIP_MANIFEST_LOG_DIRECTORY_MISMATCH' }
    return [ordered]@{ path=$manifestPath; manifest=$manifest }
}

function Stop-CloudOSRecordedProcesses {
    param([Parameter(Mandatory)]$Session)
    $ownership = Get-CloudOSOwnedSessionManifest $Session
    $manifest = $ownership.manifest
    foreach ($record in @($manifest.processes) | Sort-Object { [int]$_.pid } -Descending) {
        if (-not $record.pid -or -not $record.startedAt -or -not $record.component) { throw "SESSION_OWNERSHIP_RECORD_INCOMPLETE:$($ownership.path)" }
        $process = Get-Process -Id ([int]$record.pid) -ErrorAction SilentlyContinue
        if (-not $process) { continue }
        try { $actualStart = $process.StartTime.ToUniversalTime().ToString('o') } catch [System.InvalidOperationException] { continue }
        if ($actualStart -ne [string]$record.startedAt) {
            Write-CloudOSLog $Session "PID $($record.pid) existe, mas StartTime nao pertence a sessao; processo preservado." 'WARN'
            continue
        }
        Write-CloudOSLog $Session "Encerrando processo pertencente a sessao component=$($record.component) pid=$($record.pid) manifest=$($ownership.path)."
        try {
            Stop-Process -Id $process.Id -ErrorAction Stop
            if (-not $process.WaitForExit(5000)) {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                if (-not $process.WaitForExit(3000)) { throw "OWNED_PROCESS_DID_NOT_EXIT:$($record.component):$($record.pid)" }
            }
        } catch { throw "SESSION_TEARDOWN_FAILED:$($record.component):$($record.pid):$($_.Exception.Message)" }
    }
}
