Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ownership primitives live in cloudos-launcher-common.ps1 so the same identity
# rules are used by launcher, runner and teardown. This file contains only the
# higher-level assertions shared by stop/validation flows.

function Assert-CloudOSSessionProcessesAlive {
    param(
        [Parameter(Mandatory)]$Session,
        [string[]]$RequiredComponents=@()
    )
    $ownership = Get-CloudOSOwnedSessionManifest $Session
    $manifest = $ownership.manifest
    foreach($component in $RequiredComponents){
        $records=@($manifest.processes|Where-Object{[string]$_.component -eq $component})
        if($records.Count -eq 0){throw "SESSION_COMPONENT_RECORD_MISSING:${component}:$($ownership.path)"}
        foreach($record in $records){
            $check=Test-CloudOSProcessOwnership $manifest $record
            if(-not $check.running){throw "SESSION_PROCESS_EXITED:${component}:pid=$($record.pid)"}
            if(-not $check.owned){throw "SESSION_PROCESS_OWNERSHIP_LOST:${component}:pid=$($record.pid):reason=$($check.reason)"}
        }
    }
    return $manifest
}

function Assert-NoCloudOSOwnedProcessesRemain {
    param([Parameter(Mandatory)]$Session)
    $ownership=Get-CloudOSOwnedSessionManifest $Session
    $manifest=$ownership.manifest
    $remaining=[System.Collections.Generic.List[string]]::new()
    foreach($record in @($manifest.processes)){
        $check=Test-CloudOSProcessOwnership $manifest $record
        if($check.running -and $check.owned){$remaining.Add("$($record.component):$($record.pid)")}
    }
    if($remaining.Count -gt 0){throw "ORPHAN_SESSION_PROCESS:$($remaining -join ',')"}
    return $true
}
