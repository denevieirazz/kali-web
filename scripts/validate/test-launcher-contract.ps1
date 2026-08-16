$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$required=@(
 'Iniciar CloudOS.cmd','Diagnosticar CloudOS.cmd','Parar CloudOS.cmd',
 'scripts/launch/cloudos-launcher-common.ps1','scripts/launch/cloudos-owned-processes.ps1',
 'scripts/launch/start-cloudos.ps1','scripts/launch/stop-cloudos.ps1',
 'scripts/validate/run-stabilization-batch1.ps1','scripts/validate/test-launcher-runtime.ps1','scripts/diagnostics/diagnose-cloudos.ps1'
)
foreach($relative in $required){if(-not(Test-Path(Join-Path $root $relative))){throw "LAUNCHER_FILE_MISSING:$relative"}}
foreach($relative in $required|Where-Object{$_.EndsWith('.ps1')}){
 $tokens=$null;$errors=$null
 [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw "POWERSHELL_PARSE_FAILED:${relative}:$($errors[0].Message)"}
}

$common=Get-Content (Join-Path $root 'scripts/launch/cloudos-launcher-common.ps1') -Raw
$owned=Get-Content (Join-Path $root 'scripts/launch/cloudos-owned-processes.ps1') -Raw
$start=Get-Content (Join-Path $root 'scripts/launch/start-cloudos.ps1') -Raw
$stop=Get-Content (Join-Path $root 'scripts/launch/stop-cloudos.ps1') -Raw
$runner=Get-Content (Join-Path $root 'scripts/validate/run-stabilization-batch1.ps1') -Raw

function Get-ComponentSetFromMatches {
 param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)][string[]]$Patterns)
 $set=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($pattern in $Patterns){
  foreach($match in [regex]::Matches($Text,$pattern)){if($match.Groups.Count -gt 1 -and $match.Groups[1].Value){[void]$set.Add([string]$match.Groups[1].Value)}}
 }
 return $set
}
function Format-ComponentSet([System.Collections.Generic.HashSet[string]]$Set){return (@($Set)|Sort-Object)-join ','}

# Component contract: launcher registrations are the source of truth. Runner and teardown may only consume those names.
$launcherSession=[regex]::Escape('$session')
$runnerSession=[regex]::Escape('$Session')
$launcherComponents=Get-ComponentSetFromMatches $start @(
 "Start-CloudOSLoggedProcess\s+$launcherSession\s+'([^']+)'",
 "Add-CloudOSProcessRecord\b[^\r\n]*-Session\s+$launcherSession\b[^\r\n]*-Component\s+'([^']+)'"
)
$runnerComponents=Get-ComponentSetFromMatches $runner @(
 "(?:Assert-RunnerOwnedProcessAlive|Wait-RunnerHttpReady)\s+$runnerSession\s+'([^']+)'"
)
$teardownMatch=[regex]::Match($common,'(?s)function Stop-CloudOSRecordedProcesses\s*\{.*?(?=\r?\nfunction Complete-CloudOSSession)')
if(-not $teardownMatch.Success){throw 'COMPONENT_CONTRACT_TEARDOWN_FUNCTION_MISSING'}
$teardownBlock=$teardownMatch.Value
if($teardownBlock -notmatch '\$manifest\.processes'){throw 'COMPONENT_CONTRACT_TEARDOWN_NOT_MANIFEST_DRIVEN'}
$componentExpr=[regex]::Escape('$component')
$recordComponentExpr=[regex]::Escape('$record.component')
$teardownComponents=Get-ComponentSetFromMatches $teardownBlock @(
 "(?:$componentExpr|$recordComponentExpr)\s+-eq\s+'([^']+)'"
)
foreach($inMatch in [regex]::Matches($teardownBlock,"$componentExpr\s+-in\s+@\(([^)]*)\)")){
 foreach($literal in [regex]::Matches($inMatch.Groups[1].Value,"'([^']+)'")){[void]$teardownComponents.Add([string]$literal.Groups[1].Value)}
}
if($launcherComponents.Count -eq 0){throw 'COMPONENT_CONTRACT_LAUNCHER_REGISTRATIONS_EMPTY'}
if($runnerComponents.Count -eq 0){throw 'COMPONENT_CONTRACT_RUNNER_REQUIREMENTS_EMPTY'}
if($teardownComponents.Count -eq 0){throw 'COMPONENT_CONTRACT_TEARDOWN_COMPONENTS_EMPTY'}
$runnerMissing=@($runnerComponents|Where-Object{-not $launcherComponents.Contains($_)}|Sort-Object)
if($runnerMissing.Count){throw "COMPONENT_CONTRACT_RUNNER_REQUIRES_UNREGISTERED:$($runnerMissing -join ','):launcher=$(Format-ComponentSet $launcherComponents)"}
$teardownMissing=@($launcherComponents|Where-Object{-not $teardownComponents.Contains($_)}|Sort-Object)
$teardownExtra=@($teardownComponents|Where-Object{-not $launcherComponents.Contains($_)}|Sort-Object)
if($teardownMissing.Count -or $teardownExtra.Count){throw "COMPONENT_CONTRACT_TEARDOWN_SET_MISMATCH:missing=$($teardownMissing -join ','):extra=$($teardownExtra -join ','):launcher=$(Format-ComponentSet $launcherComponents):teardown=$(Format-ComponentSet $teardownComponents)"}
$canonicalHost='host-runtime'
$legacyHost=('ho'+'st')
foreach($entry in @(@{name='launcher';set=$launcherComponents},@{name='runner';set=$runnerComponents},@{name='teardown';set=$teardownComponents})){
 if(-not $entry.set.Contains($canonicalHost)){throw "COMPONENT_CONTRACT_CANONICAL_HOST_MISSING:$($entry.name):$canonicalHost"}
 if($entry.set.Contains($legacyHost)){throw "COMPONENT_CONTRACT_LEGACY_HOST_PRESENT:$($entry.name)"}
}
Write-Host "LAUNCHER_COMPONENT_CONTRACT_OK launcher=$(Format-ComponentSet $launcherComponents) runner=$(Format-ComponentSet $runnerComponents) teardown=$(Format-ComponentSet $teardownComponents)"

foreach($marker in @('backend.stdout.log','backend.stderr.log','frontend.stdout.log','frontend.stderr.log','host.log','bootstrap.log','wsl-core.log','result.json','teardown-result.json','launch-result.json')){
 if(($common+$start+$stop)-notmatch [regex]::Escape($marker)){throw "LOG_CONTRACT_MISSING:$marker"}
}
if($common -notmatch 'processes-\$When\.json'){throw 'LOG_CONTRACT_MISSING:processes-$When.json'}
foreach($mode in @('Full','WebOnly','Developer','UXValidation','FilesValidation','BrowserValidation','TerminalValidation')){if($common -notmatch [regex]::Escape($mode)){throw "MODE_MISSING:$mode"}}
foreach($marker in @('creationUtcTicks','executablePath','commandLineSanitized','sessionId','logDirectory')){if($common -notmatch [regex]::Escape($marker)){throw "PROCESS_IDENTITY_FIELD_MISSING:$marker"}}
if($common -notmatch 'detached-process-bootstrap\.cjs'){throw 'DETACHED_BOOTSTRAP_MISSING'}
if($common -notmatch "stdio:\s*\['ignore',\s*stdoutFd,\s*stderrFd\]"){throw 'DETACHED_DIRECT_FILE_STDIO_MISSING'}
if($common -match 'stdinFd'){throw 'DETACHED_STDIN_HANDLE_FORBIDDEN'}
if($runner -notmatch 'Invoke-ShortLauncherCommand'){throw 'RUNNER_SHORT_LAUNCHER_GATE_MISSING'}
if($runner -notmatch 'RUNNER_COMPONENT_READINESS_TIMEOUT'){throw 'RUNNER_COMPONENT_TIMEOUT_MISSING'}
if($common -notmatch 'Test-CloudOSProcessOwnership'){throw 'PROCESS_OWNERSHIP_GATE_MISSING'}
if($common -notmatch 'CloseMainWindow'){throw 'GRACEFUL_WINDOW_TEARDOWN_MISSING'}
if($common -notmatch 'taskkill\.exe'){throw 'GRACEFUL_HEADLESS_TEARDOWN_MISSING'}
if($common -notmatch 'forced-after-ownership-recheck'){throw 'FORCE_FALLBACK_OWNERSHIP_RECHECK_MISSING'}
if(($common+$owned+$start+$stop+$runner) -match '(?i)Stop-Process\s+-Name\s+(node|dotnet|pwsh|powershell|msedgewebview2)'){throw 'BROAD_PROCESS_KILL_FORBIDDEN'}
if($start -match 'npm\s+ci.*--prefix'){throw 'SUBFOLDER_NPM_CI_FORBIDDEN'}

. (Join-Path $root 'scripts/launch/cloudos-launcher-common.ps1')
. (Join-Path $root 'scripts/launch/cloudos-owned-processes.ps1')

# Identity survives JSON round-trip and does not depend on ISO fractional precision.
$identity=Get-CloudOSProcessIdentity $PID
if(-not $identity.exists -or -not $identity.creationUtcTicks -or -not $identity.executablePath){throw 'SELF_PROCESS_IDENTITY_UNAVAILABLE'}
$temp=Join-Path ([IO.Path]::GetTempPath()) "cloudos-launcher-contract-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $temp|Out-Null
$testLog=Join-Path $temp 'logs';$testRuntime=Join-Path $temp 'runtime';New-Item -ItemType Directory -Force -Path $testLog,$testRuntime|Out-Null
$session=[pscustomobject][ordered]@{schemaVersion=2;id='contract-session';mode='WebOnly';startedAt=(Get-Date).ToUniversalTime().ToString('o');root=$root;logDirectory=$testLog;runtimeDirectory=$testRuntime;dataDirectory=(Join-Path $temp 'data');git=@{};processes=@();status='running'}
$record=[pscustomobject][ordered]@{component='self';pid=$PID;sessionId=$session.id;logDirectory=$session.logDirectory;creationUtcTicks=[string]$identity.creationUtcTicks;creationTimeUtc=$identity.creationTimeUtc;startedAt=$identity.creationTimeUtc;executablePath=$identity.executablePath;commandLineSanitized=$identity.commandLineSanitized;processName=$identity.processName}
$roundTrip=(@{session=$session;record=$record}|ConvertTo-Json -Depth 8|ConvertFrom-Json)
$roundTripCheck=Test-CloudOSProcessOwnership $roundTrip.session $roundTrip.record
if(-not $roundTripCheck.owned){throw "PROCESS_IDENTITY_JSON_ROUNDTRIP_FAILED:$($roundTripCheck.reason)"}

$started=[datetime]::Parse([string]$identity.creationTimeUtc).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$legacy=[pscustomobject][ordered]@{component='self';pid=$PID;sessionId=$session.id;logDirectory=$session.logDirectory;startedAt=$started;executablePath=$identity.executablePath}
$precisionCheck=Test-CloudOSProcessOwnership $session $legacy
if(-not $precisionCheck.owned){throw "PROCESS_IDENTITY_PRECISION_NORMALIZATION_FAILED:$($precisionCheck.reason)"}

$reused=[pscustomobject][ordered]@{component='self';pid=$PID;sessionId=$session.id;logDirectory=$session.logDirectory;creationUtcTicks=[string]([int64]$identity.creationUtcTicks + [TimeSpan]::TicksPerMillisecond);executablePath=$identity.executablePath}
$reuseCheck=Test-CloudOSProcessOwnership $session $reused
if($reuseCheck.owned -or $reuseCheck.reason -ne 'creation-time-mismatch'){throw 'PID_REUSE_FAIL_CLOSED_FAILED'}

$external=[pscustomobject][ordered]@{component='external';pid=$PID;sessionId=$session.id;logDirectory=$session.logDirectory;creationUtcTicks=[string]$identity.creationUtcTicks;executablePath=(Join-Path $temp 'not-the-current-executable.exe')}
$externalCheck=Test-CloudOSProcessOwnership $session $external
if($externalCheck.owned -or $externalCheck.reason -ne 'executable-path-mismatch'){throw 'EXTERNAL_PROCESS_PRESERVATION_GATE_FAILED'}

# Complete-CloudOSSession must add missing properties under StrictMode.
$strictSession=[pscustomobject][ordered]@{schemaVersion=2;id='strict-session';mode='WebOnly';root=$root;logDirectory=(Join-Path $temp 'strict');runtimeDirectory=(Join-Path $temp 'strict-runtime');dataDirectory=(Join-Path $temp 'strict-data');git=@{};processes=@();status='running'}
New-Item -ItemType Directory -Force -Path $strictSession.logDirectory|Out-Null
[void](Complete-CloudOSSession -Session $strictSession -Status 'stopped' -Message 'strict-mode-contract' -PersistCurrentState:$false -SkipProcessSnapshot:$true)
if(-not ($strictSession.PSObject.Properties.Name -contains 'finishedAt') -or -not $strictSession.finishedAt){throw 'STRICTMODE_FINISHEDAT_NOT_PERSISTED'}
foreach($property in @('teardownResult','stoppedProcesses','preservedProcesses','failures')){if(-not($strictSession.PSObject.Properties.Name -contains $property)){throw "STRICTMODE_PROPERTY_NOT_PERSISTED:$property"}}

# Detached child must outlive the short bootstrap while writing directly to its own log.
$oldStateFile=$script:SessionStateFile
$script:SessionStateFile=Join-Path $temp 'current-session.json'
$childSession=[pscustomobject][ordered]@{schemaVersion=2;id='detached-session';mode='WebOnly';startedAt=(Get-Date).ToUniversalTime().ToString('o');root=$root;logDirectory=(Join-Path $temp 'child-logs');runtimeDirectory=(Join-Path $temp 'child-runtime');dataDirectory=(Join-Path $temp 'child-data');git=@{};processes=@();status='running';readiness=$null;teardownResult=$null;stoppedProcesses=@();preservedProcesses=@();failures=@()}
New-Item -ItemType Directory -Force -Path $childSession.logDirectory,$childSession.runtimeDirectory,$childSession.dataDirectory|Out-Null
foreach($name in @('launcher.log','backend.stdout.log','backend.stderr.log','teardown.log')){New-Item -ItemType File -Force -Path (Join-Path $childSession.logDirectory $name)|Out-Null}
Write-CloudOSJsonAtomic (Join-Path $childSession.logDirectory 'manifest.json') $childSession
Write-CloudOSJsonAtomic $script:SessionStateFile $childSession
$node=(Get-Command node -ErrorAction Stop).Source
$child=$null
try{
 $sw=[Diagnostics.Stopwatch]::StartNew()
 $child=Start-CloudOSLoggedProcess $childSession 'backend' $node @('-e',"console.log('before');setTimeout(()=>console.log('after'),700);setInterval(()=>{},1000)") (Join-Path $childSession.logDirectory 'backend.stdout.log') (Join-Path $childSession.logDirectory 'backend.stderr.log') @{}
 $sw.Stop()
 if($sw.Elapsed.TotalSeconds -gt 10){throw "DETACHED_LAUNCHER_RETURN_TOO_SLOW:$($sw.Elapsed.TotalSeconds)"}
 Start-Sleep -Milliseconds 1200
 $output=Get-Content -LiteralPath (Join-Path $childSession.logDirectory 'backend.stdout.log') -Raw -ErrorAction SilentlyContinue
 if($output -notmatch 'before' -or $output -notmatch 'after'){throw 'DETACHED_CHILD_STDOUT_NOT_PERSISTENT'}
 $teardown=Stop-CloudOSRecordedProcesses $childSession
 if(@($teardown.failures).Count -gt 0){throw "DETACHED_CHILD_TEARDOWN_FAILED:$(@($teardown.failures).Count)"}
 [void](Assert-NoCloudOSOwnedProcessesRemain $childSession)
 $stopped=@($teardown.stoppedProcesses|Where-Object{[string]$_.component -eq 'backend'}|Select-Object -First 1)
 if($stopped.Count -eq 0){throw 'GRACEFUL_TEARDOWN_RESULT_MISSING'}
 if(-not [string]$stopped[0].method){throw 'TEARDOWN_METHOD_NOT_RECORDED'}
}finally{
 if($child){$left=Get-Process -Id $child.Id -ErrorAction SilentlyContinue;if($left){try{Stop-Process -Id $left.Id -Force -ErrorAction SilentlyContinue}catch{}}}
 $script:SessionStateFile=$oldStateFile
 Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

$global:LASTEXITCODE=0
Write-Host 'LAUNCHER_CONTRACT_OK'
exit 0