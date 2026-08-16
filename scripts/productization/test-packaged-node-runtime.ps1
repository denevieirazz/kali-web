param([string]$ResultPath,[string]$Staging)
. (Join-Path $PSScriptRoot 'common.ps1')
if(-not $IsWindows){throw 'PACKAGED_NODE_RUNTIME_TEST_WINDOWS_ONLY'}
$paths=Get-CloudOSArtifactPaths
if([string]::IsNullOrWhiteSpace($Staging)){
    if([string]::IsNullOrWhiteSpace($ResultPath)){$ResultPath=Join-Path $paths.Artifacts 'package-result.json'}
    $result=Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json
    $Staging=[string]$result.staging
}
$stage=[IO.Path]::GetFullPath($Staging)
$node=Join-Path $stage 'runtime\node.exe'
$backend=Join-Path $stage 'agent\backend\src\server.js'
$frontend=Join-Path $stage 'web'
foreach($required in @($node,$backend,(Join-Path $frontend 'index.html'))){if(-not(Test-Path -LiteralPath $required)){throw "PACKAGED_RUNTIME_FILE_MISSING:$required"}}
$temp=Join-Path ([IO.Path]::GetTempPath()) "cloudos-packaged-node-$([Guid]::NewGuid().ToString('N'))"
$runtime=Join-Path $temp 'runtime';$data=Join-Path $temp 'data';$logs=Join-Path $temp 'logs'
New-Item -ItemType Directory -Force -Path $runtime,$data,$logs | Out-Null
$token=[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
$process=$null
$previousPath=$env:PATH
try{
    $system32=Join-Path $env:SystemRoot 'System32'
    $env:PATH=$system32
    & (Join-Path $system32 'where.exe') node.exe *> $null
    $globalNodeExit=$LASTEXITCODE
    $global:LASTEXITCODE=0
    if($globalNodeExit -eq 0){throw 'GLOBAL_NODE_STILL_DISCOVERABLE_IN_SANITIZED_PATH'}
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$node;$info.WorkingDirectory=$stage;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    [void]$info.ArgumentList.Add($backend)
    foreach($key in @($info.Environment.Keys)){if($key -match '(?i)(SECRET|TOKEN|PASSWORD|CREDENTIAL|PRIVATE_KEY|API_KEY)'){$info.Environment.Remove($key)}}
    $info.Environment['PATH']=$system32;$info.Environment['NODE_ENV']='production';$info.Environment['HOST']='127.0.0.1';$info.Environment['PORT']='0'
    $info.Environment['CLOUDOS_RUNTIME_DIR']=$runtime;$info.Environment['CLOUDOS_DATA_DIR']=$data;$info.Environment['CLOUDOS_LOCAL_ROOT']=$temp
    $info.Environment['CLOUDOS_FRONTEND_DIST']=$frontend;$info.Environment['CLOUDOS_SUPERVISOR_TOKEN']=$token
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    if(-not $process.Start()){throw 'PACKAGED_NODE_BACKEND_START_FAILED'}
    $outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync()
    $manifestPath=Join-Path $runtime 'backend-port.json';$deadline=[DateTime]::UtcNow.AddSeconds(30);$manifest=$null
    while([DateTime]::UtcNow -lt $deadline){
        if($process.HasExited){$out=$outTask.GetAwaiter().GetResult();$err=$errTask.GetAwaiter().GetResult();throw "PACKAGED_NODE_BACKEND_EXITED:$($process.ExitCode):${err}:${out}"}
        if(Test-Path -LiteralPath $manifestPath){try{$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json}catch{};if($manifest){break}}
        Start-Sleep -Milliseconds 120
    }
    if(-not $manifest){throw 'PACKAGED_NODE_RUNTIME_MANIFEST_TIMEOUT'}
    if([int]$manifest.pid -ne $process.Id){throw "PACKAGED_NODE_PID_MISMATCH:manifest=$($manifest.pid):process=$($process.Id)"}
    $api="http://127.0.0.1:$([int]$manifest.backendPort)";$health=Invoke-RestMethod -Uri "$api/api/health" -Method Get -TimeoutSec 4
    if($health.status -ne 'ok'){throw 'PACKAGED_NODE_HEALTH_FAILED'}
    Invoke-RestMethod -Uri "$api/_cloudos/supervisor/shutdown" -Method Post -Headers @{'X-CloudOS-Supervisor-Token'=$token} -TimeoutSec 4 | Out-Null
    if(-not $process.WaitForExit(10000)){throw 'PACKAGED_NODE_GRACEFUL_STOP_TIMEOUT'}
    if($process.ExitCode -ne 0){throw "PACKAGED_NODE_BACKEND_EXIT_NONZERO:$($process.ExitCode)"}
    $global:LASTEXITCODE=0
    Write-Host "PRODUCTIZATION_PACKAGED_NODE_RUNTIME_OK pid=$($process.Id) globalNode=false staging=$stage"
}finally{
    $env:PATH=$previousPath
    if($process){if(-not $process.HasExited){try{$process.Kill($false);$process.WaitForExit()}catch{}};$process.Dispose()}
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
$global:LASTEXITCODE=0
