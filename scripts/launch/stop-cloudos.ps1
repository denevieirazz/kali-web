[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'cloudos-launcher-common.ps1')
. (Join-Path $PSScriptRoot 'cloudos-owned-processes.ps1')

$session = Read-CloudOSCurrentSession
if (-not $session) { Write-Host 'Nenhuma sessão CloudOS registrada.'; exit 0 }

Write-CloudOSLog $session "Encerrando sessão $($session.id) com ownership fail-closed."
$teardown=$null
try {
    $teardown=Stop-CloudOSRecordedProcesses $session
    $status=if(@($teardown.failures).Count -eq 0){'stopped'}else{'teardown_failed'}
    $message=if($status -eq 'stopped'){'Sessão encerrada com teardown verificado.'}else{'Uma ou mais decisões de teardown falharam; consulte teardown-result.json.'}
    [void](Complete-CloudOSSession -Session $session -Status $status -ErrorCode $(if($status -eq 'stopped'){''}else{'TEARDOWN_FAILED'}) -Message $message -TeardownResult $teardown -PersistCurrentState:$true)
    if($status -ne 'stopped') { throw "SESSION_TEARDOWN_INCOMPLETE:failures=$(@($teardown.failures).Count):log=$(Join-Path $session.logDirectory 'teardown-result.json')" }
    [void](Assert-NoCloudOSOwnedProcessesRemain $session)
    Write-Host "Logs preservados em: $($session.logDirectory)"
    Write-Output (([ordered]@{status='stopped';sessionId=$session.id;logDirectory=$session.logDirectory;teardownResult=(Join-Path $session.logDirectory 'teardown-result.json')})|ConvertTo-Json -Compress)
    $global:LASTEXITCODE=0
    exit 0
} catch {
    if(-not $teardown){
        $teardown=[pscustomobject][ordered]@{status='failed';stoppedProcesses=@();preservedProcesses=@();failures=@([ordered]@{component='teardown';pid=$null;error=$_.Exception.Message});finishedAt=(Get-Date).ToUniversalTime().ToString('o')}
    }
    try{[void](Complete-CloudOSSession -Session $session -Status 'teardown_failed' -ErrorCode 'TEARDOWN_FAILED' -Message $_.Exception.Message -TeardownResult $teardown -PersistCurrentState:$true)}catch{}
    throw
}
