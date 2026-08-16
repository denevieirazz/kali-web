param([string]$ResultPath)
. (Join-Path $PSScriptRoot 'common.ps1')
if(-not $IsWindows){throw 'INSTALLER_TEST_WINDOWS_ONLY'}
$paths=Get-CloudOSArtifactPaths
if([string]::IsNullOrWhiteSpace($ResultPath)){$ResultPath=Join-Path $paths.Artifacts 'package-result.json'}
$result=Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json
$testRoot=Join-Path ([IO.Path]::GetTempPath()) "CloudOS Product Test $([Guid]::NewGuid().ToString('N'))"
$installRoot=Join-Path $testRoot 'Install With Spaces'
$dataRoot=Join-Path $testRoot 'User Data Preserved'
$log=Join-Path $testRoot 'setup.log'
New-Item -ItemType Directory -Force -Path $testRoot,$dataRoot | Out-Null
Set-Content -LiteralPath (Join-Path $dataRoot 'sentinel.txt') -Value 'preserve-me' -Encoding utf8
try{
    $process=Start-Process -FilePath ([string]$result.setup) -ArgumentList @('--silent','--installto',$installRoot,'--log',$log) -Wait -PassThru
    if($process.ExitCode -ne 0){throw "INSTALLER_EXIT_NONZERO:$($process.ExitCode)"}
    foreach($relative in @('Update.exe','current\CloudOS.Bootstrap.exe','current\app\host\CloudOS.Host.exe','current\runtime\node.exe')){if(-not(Test-Path -LiteralPath (Join-Path $installRoot $relative))){throw "INSTALLED_FILE_MISSING:$relative"}}
    $nodeVersion=(& (Join-Path $installRoot 'current\runtime\node.exe') --version 2>&1 | Out-String).Trim()
    if($nodeVersion -notmatch '^v22\.23\.2$'){throw "INSTALLED_NODE_INVALID:$nodeVersion"}
    $updateExe=Join-Path $installRoot 'Update.exe'
    $uninstall=Start-Process -FilePath $updateExe -ArgumentList @('uninstall','--silent') -Wait -PassThru
    if($uninstall.ExitCode -ne 0){throw "UNINSTALLER_EXIT_NONZERO:$($uninstall.ExitCode)"}
    Start-Sleep -Milliseconds 500
    if(-not(Test-Path -LiteralPath (Join-Path $dataRoot 'sentinel.txt'))){throw 'UNINSTALL_REMOVED_USER_DATA'}
    Write-Host "PRODUCTIZATION_INSTALLER_OK installRoot=$installRoot dataPreserved=true"
}finally{Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue}
