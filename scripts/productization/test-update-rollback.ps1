param([string]$PackageResult,[string]$FixtureResult)
. (Join-Path $PSScriptRoot 'common.ps1')
if(-not $IsWindows){throw 'UPDATE_ROLLBACK_TEST_WINDOWS_ONLY'}
$paths=Get-CloudOSArtifactPaths
if([string]::IsNullOrWhiteSpace($PackageResult)){$PackageResult=Join-Path $paths.Artifacts 'package-result.json'}
if([string]::IsNullOrWhiteSpace($FixtureResult)){$FixtureResult=Join-Path $paths.Artifacts 'update-fixture-result.json'}
$package=Get-Content -LiteralPath $PackageResult -Raw|ConvertFrom-Json;$fixture=Get-Content -LiteralPath $FixtureResult -Raw|ConvertFrom-Json
$root=Join-Path ([IO.Path]::GetTempPath()) "CloudOS Update Test $([Guid]::NewGuid().ToString('N'))";$install=Join-Path $root 'Install With Spaces';$data=Join-Path $root 'isolated-data';$setupLog=Join-Path $root 'setup.log'
New-Item -ItemType Directory -Force -Path $root,$data|Out-Null;Set-Content -LiteralPath (Join-Path $data 'sentinel.txt') -Value 'preserve-through-update' -Encoding utf8
function Get-InstallDiagnostic{
    $rootEntries='missing-root'
    $updateFound='none'
    $productFound='none'
    if(Test-Path -LiteralPath $root){
        $rootEntries=((Get-ChildItem -LiteralPath $root -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 60 | ForEach-Object {[IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/')}) -join ',')
        $updateFound=((Get-ChildItem -LiteralPath $root -Filter 'Update.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 10 | ForEach-Object {[IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/')}) -join ',')
        if([string]::IsNullOrWhiteSpace($updateFound)){$updateFound='none'}
        $productFound=((Get-ChildItem -LiteralPath $root -Filter 'product.json' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 10 | ForEach-Object {[IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/')}) -join ',')
        if([string]::IsNullOrWhiteSpace($productFound)){$productFound='none'}
    }
    $logTail='missing-log'
    if(Test-Path -LiteralPath $setupLog){$logTail=((Get-Content -LiteralPath $setupLog -Tail 80 -ErrorAction SilentlyContinue) -join ' | ')}
    return "install=$install installExists=$(Test-Path -LiteralPath $install) rootEntries=$rootEntries updateFound=$updateFound productFound=$productFound setupLog=$logTail"
}
function Invoke-UpdateExe([string]$Package){
    $updateExe=Join-Path $install 'Update.exe';if(-not(Test-Path -LiteralPath $updateExe)){throw "UPDATE_EXE_MISSING $(Get-InstallDiagnostic)"}
    Invoke-CloudOSExternal $updateExe @('apply','--package',$Package,'--norestart') $root | Out-Null
}
function Assert-Version([string]$Expected){
    $productPath=Join-Path $install 'current\meta\product.json';if(-not(Test-Path -LiteralPath $productPath)){throw "INSTALLED_PRODUCT_METADATA_MISSING $(Get-InstallDiagnostic)"}
    $actual=(Get-Content -LiteralPath $productPath -Raw|ConvertFrom-Json).version
    if([string]$actual -ne $Expected){throw "INSTALLED_VERSION_MISMATCH:expected=$Expected actual=$actual"}
}
function Assert-PrerequisiteWindow{
    $exe=Join-Path $install 'current\CloudOS.Bootstrap.exe';$info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$exe;$info.UseShellExecute=$false;$info.ArgumentList.Add('--prerequisites');$info.Environment['CLOUDOS_LOCAL_ROOT']=$data
    $p=[Diagnostics.Process]::new();$p.StartInfo=$info;if(-not $p.Start()){throw 'UPDATED_BOOTSTRAP_RESTART_FAILED'};$expectedStart=$p.StartTime.ToUniversalTime().Ticks
    try{$deadline=[DateTime]::UtcNow.AddSeconds(25);$visible=$false;while([DateTime]::UtcNow -lt $deadline -and -not $p.HasExited){$p.Refresh();if($p.MainWindowHandle -ne 0){$visible=$true;break};Start-Sleep -Milliseconds 150};if(-not $visible){throw 'UPDATED_PREREQUISITE_WINDOW_NOT_VISIBLE'};[void]$p.CloseMainWindow();if(-not $p.WaitForExit(10000)){$p.Refresh();if($p.StartTime.ToUniversalTime().Ticks -ne $expectedStart -or [IO.Path]::GetFullPath($p.MainModule.FileName) -ne [IO.Path]::GetFullPath($exe)){throw 'UPDATED_BOOTSTRAP_OWNERSHIP_LOST'};$p.Kill($false);$p.WaitForExit()}}finally{$p.Dispose()}
}
try{
    Invoke-CloudOSExternal ([string]$package.setup) @('--silent','--installto',$install,'--log',$setupLog) $root | Out-Null
    Assert-Version ([string]$fixture.currentVersion)
    Invoke-UpdateExe ([string]$fixture.nextFullPackage);Assert-Version ([string]$fixture.nextVersion);Assert-PrerequisiteWindow
    & (Join-Path $PSScriptRoot 'test-packaged-node-runtime.ps1') -Staging (Join-Path $install 'current')
    if($LASTEXITCODE -ne 0){throw "UPDATED_PACKAGED_NODE_HEALTH_FAILED:$LASTEXITCODE"}
    Invoke-UpdateExe ([string]$fixture.currentFullPackage);Assert-Version ([string]$fixture.currentVersion);Assert-PrerequisiteWindow
    if((Get-Content -LiteralPath (Join-Path $data 'sentinel.txt') -Raw).Trim() -ne 'preserve-through-update'){throw 'UPDATE_OR_ROLLBACK_REMOVED_DATA'}
    Invoke-CloudOSExternal (Join-Path $install 'Update.exe') @('uninstall','--silent') $root | Out-Null
    if(-not(Test-Path -LiteralPath (Join-Path $data 'sentinel.txt'))){throw 'UPDATE_TEST_UNINSTALL_REMOVED_DATA'}
    Write-Host 'PRODUCTIZATION_UPDATE_ROLLBACK_OK apply=true restart=true health=true rollback=true dataPreserved=true'
}finally{
    if(Test-Path -LiteralPath (Join-Path $install 'Update.exe')){try{Invoke-CloudOSExternal (Join-Path $install 'Update.exe') @('uninstall','--silent') $root -AllowFailure | Out-Null}catch{}}
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
