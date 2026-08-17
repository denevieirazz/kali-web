Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'RC_ORPHAN_CHECK_WINDOWS_ONLY'}
$orphans=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{
    $_.Name -in @('CloudOS.Host.exe','CloudOS.Bootstrap.exe','CloudOS.WslCore.exe') -or
    ($_.Name -eq 'node.exe' -and $_.CommandLine -and $_.CommandLine -match '(?i)CloudOS.+agent[\\/]backend|agent[\\/]backend.+src[\\/]server\.js')
}|ForEach-Object{[pscustomobject]@{pid=$_.ProcessId;name=$_.Name;path=$_.ExecutablePath}})
if($orphans.Count -gt 0){throw ('RC_ORPHAN_PROCESS_FOUND:'+($orphans|ConvertTo-Json -Compress))}
Write-Host 'PRODUCTIZATION_RC_ORPHANS_OK count=0'
