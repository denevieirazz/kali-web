param()
. (Join-Path $PSScriptRoot 'cloudos-launcher-common.ps1')
$session = Read-CloudOSCurrentSession
if (-not $session) { Write-Host 'Nenhuma sessão CloudOS registrada.'; exit 0 }
Write-CloudOSLog $session "Encerrando sessão $($session.id)."
Stop-CloudOSRecordedProcesses $session
Complete-CloudOSSession $session 'stopped' '' 'Sessão encerrada pelo usuário.'
Write-Host "Logs preservados em: $($session.logDirectory)"
