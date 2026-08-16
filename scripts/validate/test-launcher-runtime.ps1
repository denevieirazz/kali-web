[CmdletBinding()]
param([switch]$AllowNonCi)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if(-not $IsWindows){throw 'WINDOWS_RUNTIME_LAUNCHER_TEST_REQUIRED'}
if($env:CI -ne 'true' -and -not $AllowNonCi){throw 'LAUNCHER_RUNTIME_TEST_REQUIRES_CI_OR_ALLOWNONCI'}

$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'scripts\launch\cloudos-launcher-common.ps1')
. (Join-Path $root 'scripts\launch\cloudos-owned-processes.ps1')
$pwsh=(Get-Command pwsh -ErrorAction Stop).Source
$stateFile=Join-Path $root '.cloudos-runtime\current-session.json'
$evidenceRoot=if($env:CLOUDOS_RESULT_DIR){Join-Path $root "$env:CLOUDOS_RESULT_DIR\launcher-runtime"}else{Join-Path ([IO.Path]::GetTempPath()) "cloudos-launcher-runtime-$([guid]::NewGuid().ToString('N'))"}
New-Item -ItemType Directory -Force -Path $evidenceRoot|Out-Null

function Quote-TestArgument([string]$Value){if($Value -notmatch '[\s"]'){return $Value};return '"'+($Value -replace '([\\]*)"','$1$1\"')+'"'}
function Invoke-ShortLauncher([string]$Name,[string[]]$Arguments,[int]$TimeoutSeconds){
 $out=Join-Path $evidenceRoot "$Name.stdout.log";$err=Join-Path $evidenceRoot "$Name.stderr.log";New-Item -ItemType File -Force -Path $out,$err|Out-Null
 $quoted=@($Arguments|ForEach-Object{Quote-TestArgument ([string]$_)})
 $sw=[Diagnostics.Stopwatch]::StartNew();$p=Start-Process -FilePath $pwsh -ArgumentList $quoted -WorkingDirectory $root -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
 try{if(-not $p.WaitForExit($TimeoutSeconds*1000)){try{Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}catch{};throw "RUNTIME_LAUNCHER_TIMEOUT:${Name}:$TimeoutSeconds"};$sw.Stop();if($p.ExitCode -ne 0){$tail=((Get-Content $err -Tail 30 -ErrorAction SilentlyContinue)+(Get-Content $out -Tail 30 -ErrorAction SilentlyContinue))-join ' | ';throw "RUNTIME_LAUNCHER_FAILED:${Name}:exit=$($p.ExitCode):$tail"};return $sw.Elapsed.TotalSeconds}finally{$p.Dispose()}
}
function Read-RunningManifest([string]$Mode){
 if(-not(Test-Path -LiteralPath $stateFile)){throw "RUNTIME_STATE_MISSING:$Mode"};$state=Get-Content $stateFile -Raw|ConvertFrom-Json
 if([string]$state.mode -ne $Mode -or [string]$state.status -ne 'running'){throw "RUNTIME_SESSION_NOT_RUNNING:${Mode}:$($state.status)"}
 $path=Join-Path ([string]$state.logDirectory) 'manifest.json';$manifest=Get-Content $path -Raw|ConvertFrom-Json
 if([string]$manifest.id -ne [string]$state.id -or [string]$manifest.readiness.status -ne 'ready'){throw "RUNTIME_MANIFEST_NOT_READY:$Mode"}
 return $manifest
}
function Assert-ComponentOwned($Session,[string]$Component){$record=@($Session.processes|Where-Object{[string]$_.component -eq $Component}|Select-Object -First 1);if($record.Count -eq 0){throw "RUNTIME_COMPONENT_MISSING:$Component"};$check=Test-CloudOSProcessOwnership $Session $record[0];if(-not $check.running -or -not $check.owned){throw "RUNTIME_COMPONENT_NOT_OWNED:${Component}:$($check.reason)"};return $record[0]}
function Assert-Http([string]$Uri){$r=Invoke-WebRequest -Uri $Uri -TimeoutSec 5 -SkipHttpErrorCheck;if([int]$r.StatusCode -lt 200 -or [int]$r.StatusCode -ge 400){throw "RUNTIME_HTTP_NOT_READY:${Uri}:$($r.StatusCode)"}}
function Copy-SessionEvidence($Session,[string]$Mode){$target=Join-Path $evidenceRoot $Mode;New-Item -ItemType Directory -Force -Path $target|Out-Null;foreach($name in @('manifest.json','launch-result.json','teardown-result.json','result.json','backend.stdout.log','backend.stderr.log','frontend.stdout.log','frontend.stderr.log','host.log','host.stderr.log','launcher.log')){$source=Join-Path ([string]$Session.logDirectory) $name;if(Test-Path $source){Copy-Item $source (Join-Path $target $name) -Force}}}
function Assert-NoActiveSessionBeforeTest {
 if(-not(Test-Path $stateFile)){return};try{$s=Get-Content $stateFile -Raw|ConvertFrom-Json}catch{return};if([string]$s.status -notin @('starting','running')){return};foreach($record in @($s.processes)){$check=Test-CloudOSProcessOwnership $s $record;if($check.running -and $check.owned){throw "ACTIVE_SESSION_BEFORE_RUNTIME_TEST:$($s.id):$($record.component):$($record.pid)"}}
}

Assert-NoActiveSessionBeforeTest
$results=[System.Collections.Generic.List[object]]::new()
foreach($mode in @('WebOnly','Full')){
 $session=$null;$started=$false
 try{
  $timeout=if($mode -eq 'Full'){150}else{90}
  $elapsed=Invoke-ShortLauncher "${mode}-start" @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'scripts\launch\start-cloudos.ps1'),'-Mode',$mode,'-NoOpen') $timeout
  if($elapsed -ge $timeout){throw "LAUNCHER_DID_NOT_RETURN_AFTER_READINESS:${mode}:$elapsed"}
  $started=$true;$session=Read-RunningManifest $mode
  if($mode -eq 'WebOnly'){
   $backend=Assert-ComponentOwned $session 'backend';$frontend=Assert-ComponentOwned $session 'frontend'
   Assert-Http "$($session.readiness.backendApiBase)/api/health";Assert-Http ([string]$session.readiness.frontendUrl)
   foreach($name in @('backend.stdout.log','backend.stderr.log','frontend.stdout.log','frontend.stderr.log')){if(-not(Test-Path (Join-Path ([string]$session.logDirectory) $name))){throw "RUNTIME_LOG_MISSING:$name"}}
   if((Get-Item (Join-Path ([string]$session.logDirectory) 'backend.stdout.log')).Length -eq 0){throw 'BACKEND_STDOUT_EMPTY_AFTER_LAUNCHER_EXIT'}
   if((Get-Item (Join-Path ([string]$session.logDirectory) 'frontend.stdout.log')).Length -eq 0){throw 'FRONTEND_STDOUT_EMPTY_AFTER_LAUNCHER_EXIT'}
  }else{
   $hostRuntime=Assert-ComponentOwned $session 'host-runtime';[void](Assert-ComponentOwned $session 'backend-hosted')
   $hostProcess=Get-Process -Id ([int]$hostRuntime.pid) -ErrorAction Stop
   if(-not ([string]$hostRuntime.executablePath -match '(?i)CloudOS\.Host\.exe$')){throw "FULL_HOST_RUNTIME_NOT_DIRECT_EXECUTABLE:$($hostRuntime.executablePath)"}
   if($hostProcess.MainWindowHandle -eq [IntPtr]::Zero){throw 'FULL_CHECKPOINT_SHELL_WINDOW_NOT_READY'}
   if($null -ne $session.readiness.hostLauncherPid){throw "FULL_WRAPPER_PID_SHOULD_BE_NULL:$($session.readiness.hostLauncherPid)"}
   Assert-Http "$($session.readiness.backendApiBase)/api/health"
   Set-Content -LiteralPath (Join-Path $evidenceRoot 'full-checkpoint.txt') -Value "FULL_CHECKPOINT_REACHED session=$($session.id) hostRuntimePid=$($hostRuntime.pid)" -Encoding UTF8
   Write-Host 'FULL_CHECKPOINT_REACHED'
  }
  $results.Add([ordered]@{mode=$mode;sessionId=$session.id;launcherReturnedSeconds=$elapsed;readiness=$session.readiness;startPassed=$true})
 }finally{
  if($started){
   try{[void](Invoke-ShortLauncher "${mode}-stop" @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'scripts\launch\stop-cloudos.ps1')) 60)}finally{
    Start-Sleep -Milliseconds 500
    if($session){[void](Assert-NoCloudOSOwnedProcessesRemain $session);$final=Get-Content (Join-Path ([string]$session.logDirectory) 'manifest.json') -Raw|ConvertFrom-Json;if([string]$final.status -ne 'stopped'){throw "RUNTIME_SESSION_NOT_STOPPED:${mode}:$($final.status)"};if(@($final.failures).Count -gt 0){throw "RUNTIME_TEARDOWN_FAILURES:${mode}:$(@($final.failures).Count)"};if($mode -eq 'Full'){$hostStop=@($final.stoppedProcesses|Where-Object{[string]$_.component -eq 'host-runtime'}|Select-Object -First 1);if($hostStop.Count -eq 0){throw 'FULL_HOST_RUNTIME_TEARDOWN_RESULT_MISSING'};if([string]$hostStop[0].method -eq 'forced-after-ownership-recheck'){throw 'FULL_HOST_RUNTIME_REQUIRED_FORCE_INSTEAD_OF_GRACEFUL'}};Copy-SessionEvidence $final $mode}
   }
  }
 }
}
$results|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $evidenceRoot 'launcher-runtime-results.json') -Encoding UTF8
Write-Host 'LAUNCHER_RUNTIME_WEBONLY_FULL_OK'
