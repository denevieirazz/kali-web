[CmdletBinding()]
param(
  [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$Distribution,
  [string]$OutputDirectory='test-results\linux-system-center-cgroups-physical'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'visible-terminal-wsl-core-common.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
New-Item -ItemType Directory -Force -Path $output | Out-Null
$validation=Join-Path $output 'validation.json'
$visibleReportPath=Join-Path $output 'visible-validation.json'
$controlReportPath=Join-Path $output 'cgroup-control-validation.json'
$wsl=Join-Path ($env:WINDIR ?? 'C:\Windows') 'System32\wsl.exe'
if(-not(Test-Path -LiteralPath $wsl)){throw 'WSL_NOT_FOUND'}
$node=(Get-Command node -ErrorAction Stop).Source
$selected=Get-CloudOSWsl2Distribution -WslExe $wsl -Requested $Distribution

function Get-WslConfigFingerprint {
  $result=Invoke-CloudOSWsl -WslExe $wsl -Arguments @('--list','--verbose')
  $rows=@()
  foreach($raw in $result.Output){
    $line=([string]$raw).Replace([string][char]0,'').Trim(); if(-not $line){continue}
    $isDefault=$line.StartsWith('*'); if($isDefault){$line=$line.Substring(1).TrimStart()}
    if($line -match '^(?<name>[A-Za-z0-9][A-Za-z0-9._-]{0,79})\s+.+?\s+(?<version>[12])$'){$rows += "$(if($isDefault){'*'}else{'-'})|$($Matches.name)|$($Matches.version)"}
  }
  return [string]::Join("`n",@($rows|Sort-Object))
}
function Test-GuestPidAlive([int]$PidValue){
  if($PidValue -le 0){return $false}
  $probe=Invoke-CloudOSWsl -WslExe $wsl -Arguments @('--distribution',$selected,'--exec','/usr/bin/test','-d',"/proc/$PidValue") -AllowFailure
  return $probe.ExitCode -eq 0
}
function Wait-GuestPidsGone([int[]]$Pids,[int]$TimeoutMs=10000){
  $deadline=[DateTime]::UtcNow.AddMilliseconds($TimeoutMs);$alive=@($Pids|Where-Object{Test-GuestPidAlive $_})
  while($alive.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 250;$alive=@($Pids|Where-Object{Test-GuestPidAlive $_})}
  return @($alive)
}
function Get-TemporaryCorePids([string]$CorePath){
  $ps=Invoke-CloudOSWsl -WslExe $wsl -Arguments @('--distribution',$selected,'--exec','/bin/ps','-eo','pid=,args=') -AllowFailure
  $result=@();foreach($raw in $ps.Output){$line=[string]$raw;if($line -match '^\s*(?<pid>\d+)\s+(?<args>.*)$' -and $Matches.args.Contains($CorePath) -and $Matches.args -match '\sserve(?:\s|$)'){$result += [int]$Matches.pid}}
  return @($result)
}

$runId=[Guid]::NewGuid().ToString('N')
$core=$null;$backend=$null;$frontend=$null
$temp=Join-Path ([IO.Path]::GetTempPath()) "cloudos-linux-system-center-$runId";$runtime=Join-Path $temp 'runtime';$data=Join-Path $temp 'data'
New-Item -ItemType Directory -Force -Path $runtime,$data | Out-Null
$realDbBefore=@{backend=Get-CloudOSPathFingerprint -Path (Join-Path $root 'backend\data');root=Get-CloudOSPathFingerprint -Path (Join-Path $root 'data')}
$wslBefore=Get-WslConfigFingerprint
$final=$null
try {
  if(-not(Test-Path -LiteralPath (Join-Path $root 'node_modules\@playwright\test'))){throw 'PLAYWRIGHT_NOT_INSTALLED: execute npm ci no repositório antes da validação.'}
  $core=New-CloudOSTemporaryCore -Root $root -WslExe $wsl -Distribution $selected -RunId $runId
  $frontPort=Get-CloudOSFreePort
  $envMap=@{
    NODE_ENV='development';CLOUDOS_WSL_CORE_FOUNDATION='1';CLOUDOS_WSL_CORE_TERMINAL='1';CLOUDOS_WSL_CORE_TERMINAL_FALLBACK='0';
    CLOUDOS_WSL_CORE_SYSTEM_CENTER='1';CLOUDOS_WSL_CORE_SYSTEM_CENTER_FALLBACK='0';CLOUDOS_WSL_CORE_CGROUP_CONTROL='0';CLOUDOS_WSL_CORE_LINUX_PATH=$core.Path;
    CLOUDOS_RUNTIME_DIR=$runtime;CLOUDOS_DATA_DIR=$data;DATABASE_PATH=(Join-Path $data 'cloudos.json');PORT='0';CLOUDOS_FRONTEND_PORT=[string]$frontPort;CLOUDOS_FRONTEND_STRICT_PORT='1';CORS_ORIGIN="http://127.0.0.1:$frontPort"
  }
  $backend=Start-CloudOSNodeProcess -NodeExe $node -Script (Join-Path $root 'backend\src\server.js') -WorkingDirectory (Join-Path $root 'backend') -Environment $envMap
  $backendRuntime=Wait-CloudOSJsonFile -Path (Join-Path $runtime 'backend-port.json') -TimeoutSeconds 30
  $backendUrl="http://127.0.0.1:$($backendRuntime.backendPort)"
  $username="scprobe$($runId.Substring(0,8))";$password="CloudOS-System-$($runId.Substring(0,12))!9z"
  $setupBody=@{username=$username;displayName='Linux System Center Probe';password=$password;confirmPassword=$password}|ConvertTo-Json
  [void](Invoke-RestMethod -Method Post -Uri "$backendUrl/api/setup/admin" -ContentType 'application/json' -Body $setupBody -TimeoutSec 15)
  $frontend=Start-CloudOSNodeProcess -NodeExe $node -Script (Join-Path $root 'frontend\scripts\dev-server.js') -WorkingDirectory (Join-Path $root 'frontend') -Environment $envMap
  $frontRuntime=Wait-CloudOSJsonFile -Path (Join-Path $runtime 'frontend-port.json') -TimeoutSeconds 30

  & $node (Join-Path $root 'scripts\probe-linux-system-center-cgroups.mjs') --url ([string]$frontRuntime.url) --distro $selected --core $core.Path --username $username --password $password --output $visibleReportPath
  if($LASTEXITCODE -ne 0){throw "SYSTEM_CENTER_VISIBLE_PROBE_FAILED:exit=$LASTEXITCODE"}
  $visible=Get-Content -LiteralPath $visibleReportPath -Raw|ConvertFrom-Json
  if($visible.passed -ne $true -or $visible.mode -ne 'wsl-core-v2' -or $visible.cgroupReadOnlyValidated -ne $true){throw 'SYSTEM_CENTER_VISIBLE_REPORT_FAILED'}

  Stop-CloudOSOwnedProcess $frontend;$frontend=$null
  Stop-CloudOSOwnedProcess $backend;$backend=$null
  $visibleTracked=@($visible.trackedGuestPids|ForEach-Object{[int]$_});$remaining=Wait-GuestPidsGone -Pids $visibleTracked -TimeoutMs 10000
  if($remaining.Count -gt 0){throw "VISIBLE_STAGE_GUEST_ORPHANS:$([string]::Join(',', $remaining))"}

  $env:CLOUDOS_WSL_CORE_FOUNDATION='1'
  & $node (Join-Path $root 'scripts\probe-cgroup-control.mjs') --distro $selected --core $core.Path --output $controlReportPath
  if($LASTEXITCODE -ne 0){throw "CGROUP_CONTROL_PROBE_FAILED:exit=$LASTEXITCODE"}
  $control=Get-Content -LiteralPath $controlReportPath -Raw|ConvertFrom-Json
  if($control.passed -ne $true){throw 'CGROUP_CONTROL_REPORT_FAILED'}
  if($control.cgroupControlAvailable -eq $true -and $control.cgroupControlValidated -ne $true){throw 'CGROUP_CONTROL_AVAILABLE_BUT_NOT_VALIDATED'}
  $controlledPid=[int]($control.controlledPid ?? 0);if($controlledPid -gt 0){$remainingControl=Wait-GuestPidsGone -Pids @($controlledPid) -TimeoutMs 8000;if($remainingControl.Count -gt 0){throw 'CGROUP_CONTROL_CHILD_ORPHAN'}}
  $coreRoots=Get-TemporaryCorePids -CorePath $core.Path;if($coreRoots.Count -gt 0){$remainingCore=Wait-GuestPidsGone -Pids $coreRoots -TimeoutMs 8000;if($remainingCore.Count -gt 0){throw 'CLOUDOS_CORE_ORPHAN'}}

  $realDbAfter=@{backend=Get-CloudOSPathFingerprint -Path (Join-Path $root 'backend\data');root=Get-CloudOSPathFingerprint -Path (Join-Path $root 'data')}
  $realDatabaseUntouched=($realDbBefore.backend -eq $realDbAfter.backend -and $realDbBefore.root -eq $realDbAfter.root);if(-not $realDatabaseUntouched){throw 'REAL_DATABASE_TOUCHED'}
  $wslAfter=Get-WslConfigFingerprint;$wslMutated=$wslBefore -ne $wslAfter;if($wslMutated){throw 'WSL_STATE_CHANGED'}
  $final=[ordered]@{
    passed=$true;physicalValidation=$true;visibleSystemCenter=$true;distribution=$selected;mode='wsl-core-v2';protocol=2;protection='aes-256-gcm-seq';
    processSignalsValidated=$true;searchFilterRefreshValidated=$true;cgroupReadOnlyValidated=$true;cgroupV2Mounted=[bool]$visible.cgroupV2Mounted;
    cgroupControlAvailable=[bool]$control.cgroupControlAvailable;cgroupControlValidated=[bool]$control.cgroupControlValidated;
    noOrphansVerified=$true;realDatabaseUntouched=$true;databaseTouched=$false;wslMutated=$false;elevationRequested=$false;legacyFallbackUsed=$false;
    visibleChecks=@($visible.checks);cgroupControlChecks=@($control.checks);cgroupControlReason=[string]($control.cgroupCapabilities.reason ?? '')
  }
} catch {
  $message=[string]$_.Exception.Message
  $final=[ordered]@{passed=$false;physicalValidation=$true;visibleSystemCenter=$true;distribution=$selected;protocol=2;protection='aes-256-gcm-seq';errorCode=$message.Substring(0,[Math]::Min(180,$message.Length));databaseTouched=$false;wslMutated=$false;elevationRequested=$false}
  throw
} finally {
  Stop-CloudOSOwnedProcess $frontend;Stop-CloudOSOwnedProcess $backend
  if($core){Remove-CloudOSTemporaryCore -WslExe $wsl -Distribution $selected -Core $core}
  if($null -ne $final){$final|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $validation -Encoding utf8}
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "PASS CloudOS Linux System Center + cgroups v2 physical validation: $validation"
