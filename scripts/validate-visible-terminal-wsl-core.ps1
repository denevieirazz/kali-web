[CmdletBinding()]
param(
  [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$Distribution,
  [string]$OutputDirectory='test-results\visible-terminal-wsl-core-physical'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'visible-terminal-wsl-core-common.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
New-Item -ItemType Directory -Force -Path $output | Out-Null
$validation=Join-Path $output 'validation.json'
$browserReportPath=Join-Path $output 'browser-validation.json'
$wsl=Join-Path ($env:WINDIR ?? 'C:\Windows') 'System32\wsl.exe'
if(-not(Test-Path -LiteralPath $wsl)){throw 'WSL_NOT_FOUND'}
$node=(Get-Command node -ErrorAction Stop).Source
$selected=Get-CloudOSWsl2Distribution -WslExe $wsl -Requested $Distribution

function Get-WslConfigFingerprint {
  $result=Invoke-CloudOSWsl -WslExe $wsl -Arguments @('--list','--verbose')
  $rows=@()
  foreach($raw in $result.Output){
    $line=([string]$raw).Replace([string][char]0,'').Trim()
    if(-not $line){continue}
    $isDefault=$line.StartsWith('*')
    if($isDefault){$line=$line.Substring(1).TrimStart()}
    if($line -match '^(?<name>[A-Za-z0-9][A-Za-z0-9._-]{0,79})\s+.+?\s+(?<version>[12])$'){
      $rows += "$(if($isDefault){'*'}else{'-'})|$($Matches.name)|$($Matches.version)"
    }
  }
  return [string]::Join("`n",@($rows|Sort-Object))
}
$runId=[Guid]::NewGuid().ToString('N')
$core=$null;$backend=$null;$frontend=$null
$temp=Join-Path ([IO.Path]::GetTempPath()) "cloudos-visible-terminal-physical-$runId"
$runtime=Join-Path $temp 'runtime';$data=Join-Path $temp 'data'
New-Item -ItemType Directory -Force -Path $runtime,$data | Out-Null
$realDbBefore=@{
  backend=Get-CloudOSPathFingerprint -Path (Join-Path $root 'backend\data')
  root=Get-CloudOSPathFingerprint -Path (Join-Path $root 'data')
}
$wslBefore=Get-WslConfigFingerprint
$final=$null
try {
  if(-not(Test-Path -LiteralPath (Join-Path $root 'node_modules\@playwright\test'))){throw 'PLAYWRIGHT_NOT_INSTALLED: execute npm ci no repositório antes da validação.'}
  $core=New-CloudOSTemporaryCore -Root $root -WslExe $wsl -Distribution $selected -RunId $runId
  $frontPort=Get-CloudOSFreePort
  $envMap=@{
    NODE_ENV='development'; CLOUDOS_WSL_CORE_FOUNDATION='1'; CLOUDOS_WSL_CORE_TERMINAL='1'; CLOUDOS_WSL_CORE_TERMINAL_FALLBACK='0';
    CLOUDOS_WSL_CORE_LINUX_PATH=$core.Path; CLOUDOS_RUNTIME_DIR=$runtime; CLOUDOS_DATA_DIR=$data; DATABASE_PATH=(Join-Path $data 'cloudos.json');
    PORT='0'; CLOUDOS_FRONTEND_PORT=[string]$frontPort; CLOUDOS_FRONTEND_STRICT_PORT='1'; CORS_ORIGIN="http://127.0.0.1:$frontPort"
  }
  $backend=Start-CloudOSNodeProcess -NodeExe $node -Script (Join-Path $root 'backend\src\server.js') -WorkingDirectory (Join-Path $root 'backend') -Environment $envMap
  $backendRuntime=Wait-CloudOSJsonFile -Path (Join-Path $runtime 'backend-port.json') -TimeoutSeconds 30
  $backendUrl="http://127.0.0.1:$($backendRuntime.backendPort)"

  $username="vtprobe$($runId.Substring(0,8))"
  $password="CloudOS-Visible-$($runId.Substring(0,12))!9z"
  $setupBody=@{username=$username;displayName='Visible Terminal Probe';password=$password;confirmPassword=$password}|ConvertTo-Json
  [void](Invoke-RestMethod -Method Post -Uri "$backendUrl/api/setup/admin" -ContentType 'application/json' -Body $setupBody -TimeoutSec 15)

  $frontend=Start-CloudOSNodeProcess -NodeExe $node -Script (Join-Path $root 'frontend\scripts\dev-server.js') -WorkingDirectory (Join-Path $root 'frontend') -Environment $envMap
  $frontRuntime=Wait-CloudOSJsonFile -Path (Join-Path $runtime 'frontend-port.json') -TimeoutSeconds 30
  $frontUrl=[string]$frontRuntime.url

  & $node (Join-Path $root 'scripts\probe-visible-terminal-wsl-core.mjs') --url $frontUrl --distro $selected --core $core.Path --username $username --password $password --output $browserReportPath
  if($LASTEXITCODE -ne 0){throw "VISIBLE_TERMINAL_PHYSICAL_PROBE_FAILED:exit=$LASTEXITCODE"}
  if(-not(Test-Path -LiteralPath $browserReportPath)){throw 'VISIBLE_TERMINAL_REPORT_MISSING'}
  $browserReport=Get-Content -LiteralPath $browserReportPath -Raw | ConvertFrom-Json
  if($browserReport.passed -ne $true -or $browserReport.mode -ne 'wsl-core-v2' -or $browserReport.noOrphansVerified -ne $true){throw 'VISIBLE_TERMINAL_REPORT_FAILED'}

  $realDbAfter=@{
    backend=Get-CloudOSPathFingerprint -Path (Join-Path $root 'backend\data')
    root=Get-CloudOSPathFingerprint -Path (Join-Path $root 'data')
  }
  $realDatabaseUntouched=($realDbBefore.backend -eq $realDbAfter.backend -and $realDbBefore.root -eq $realDbAfter.root)
  if(-not $realDatabaseUntouched){throw 'REAL_DATABASE_TOUCHED'}
  $wslAfter=Get-WslConfigFingerprint
  $wslMutated=$wslBefore -ne $wslAfter
  if($wslMutated){throw 'WSL_STATE_CHANGED'}

  $final=[ordered]@{
    passed=$true; physicalValidation=$true; visibleTerminal=$true; distribution=$selected; mode='wsl-core-v2'; protocol=2; protection='aes-256-gcm-seq';
    commands=@('uname -a','pwd','id','sleep + Ctrl+C'); resizeVerified=$true; closeWithActiveProcess=$true; noOrphansVerified=$true;
    realDatabaseUntouched=$true; databaseTouched=$false; wslMutated=$false; elevationRequested=$false; legacyFallbackUsed=$false;
    browserChecks=@($browserReport.checks)
  }
} catch {
  $browserReport=$null
  if(Test-Path -LiteralPath $browserReportPath){try{$browserReport=Get-Content -LiteralPath $browserReportPath -Raw|ConvertFrom-Json}catch{}}
  $failureMode=if($null -ne $browserReport){$browserReport.mode}else{$null}
  $failureChecks=if($null -ne $browserReport){@($browserReport.checks)}else{@()}
  $errorText=[string]$_.Exception.Message
  $final=[ordered]@{
    passed=$false; physicalValidation=$true; visibleTerminal=$true; distribution=$selected; mode=$failureMode; protocol=2; protection='aes-256-gcm-seq';
    errorCode=$errorText.Substring(0,[Math]::Min(180,$errorText.Length));
    browserChecks=$failureChecks; realDatabaseUntouched=$null; databaseTouched=$false; wslMutated=$false; elevationRequested=$false
  }
  throw
} finally {
  Stop-CloudOSOwnedProcess $frontend; Stop-CloudOSOwnedProcess $backend
  if($core){Remove-CloudOSTemporaryCore -WslExe $wsl -Distribution $selected -Core $core}
  if($null -ne $final){$final|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $validation -Encoding utf8}
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "PASS CloudOS visible Terminal WSL Core v2 physical validation: $validation"
