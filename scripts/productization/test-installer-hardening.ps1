param(
    [string]$PackageResult,
    [string]$FixtureResult
)
. (Join-Path $PSScriptRoot 'common.ps1')
if(-not $IsWindows){throw 'INSTALLER_HARDENING_WINDOWS_ONLY'}

$paths=Get-CloudOSArtifactPaths
if([string]::IsNullOrWhiteSpace($PackageResult)){$PackageResult=Join-Path $paths.Artifacts 'package-result.json'}
if([string]::IsNullOrWhiteSpace($FixtureResult)){$FixtureResult=Join-Path $paths.Artifacts 'update-fixture-result.json'}
$package=Get-Content -LiteralPath $PackageResult -Raw|ConvertFrom-Json
$fixture=Get-Content -LiteralPath $FixtureResult -Raw|ConvertFrom-Json

$testRoot=Join-Path ([IO.Path]::GetTempPath()) "CloudOS Installer Hardening $([Guid]::NewGuid().ToString('N'))"
$longSegment=('Long Path Segment ' + ('x'*42))
$installRoot=Join-Path $testRoot (Join-Path $longSegment (Join-Path $longSegment 'CloudOS Install'))
$localRoot=Join-Path $testRoot 'local-state'
$dataRoot=Join-Path $localRoot 'data'
$cacheRoot=Join-Path $localRoot 'cache'
$logsRoot=Join-Path $localRoot 'logs'
$updatesRoot=Join-Path $localRoot 'updates'
$setupLog=Join-Path $logsRoot 'setup.log'
New-Item -ItemType Directory -Force -Path $testRoot,$dataRoot,$cacheRoot,$logsRoot,$updatesRoot|Out-Null
Set-Content -LiteralPath (Join-Path $dataRoot 'sentinel.txt') -Value 'installer-hardening-preserve' -Encoding utf8

function Invoke-ExactWindowsExe {
    param([Parameter(Mandatory)][string]$FilePath,[string[]]$Arguments=@(),[hashtable]$Environment=@{},[switch]$AllowFailure)
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$FilePath;$info.WorkingDirectory=$testRoot;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($argument in $Arguments){[void]$info.ArgumentList.Add([string]$argument)}
    foreach($entry in $Environment.GetEnumerator()){$info.Environment[[string]$entry.Key]=[string]$entry.Value}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    try{
        if(-not $process.Start()){throw "EXACT_EXE_START_FAILED:$FilePath"}
        $stdoutTask=$process.StandardOutput.ReadToEndAsync();$stderrTask=$process.StandardError.ReadToEndAsync();$process.WaitForExit()
        $stdout=$stdoutTask.GetAwaiter().GetResult();$stderr=$stderrTask.GetAwaiter().GetResult();$exitCode=$process.ExitCode;$output=(($stdout+"`n"+$stderr).Trim())
        if(-not $AllowFailure -and $exitCode -ne 0){throw "EXACT_EXE_FAILED:$FilePath exit=$exitCode output=$output"}
        return [pscustomobject]@{ExitCode=$exitCode;Output=$output}
    }finally{$process.Dispose()}
}
function Assert-InstalledVersion([string]$Expected){$product=Join-Path $installRoot 'current\meta\product.json';if(-not(Test-Path -LiteralPath $product)){throw 'INSTALLER_HARDENING_PRODUCT_METADATA_MISSING'};$actual=[string](Get-Content -LiteralPath $product -Raw|ConvertFrom-Json).version;if($actual -ne $Expected){throw "INSTALLER_HARDENING_VERSION_MISMATCH:expected=$Expected actual=$actual"}}
function Assert-DataPreserved{$sentinel=Join-Path $dataRoot 'sentinel.txt';if(-not(Test-Path -LiteralPath $sentinel)){throw 'INSTALLER_HARDENING_DATA_REMOVED'};if((Get-Content -LiteralPath $sentinel -Raw).Trim() -ne 'installer-hardening-preserve'){throw 'INSTALLER_HARDENING_DATA_CHANGED'}}
function Invoke-Installer([hashtable]$Environment){Invoke-ExactWindowsExe ([string]$package.setup) @('--silent','--installto',$installRoot,'--log',$setupLog) $Environment|Out-Null}
function Invoke-Update([string]$FullPackage){$updateExe=Join-Path $installRoot 'Update.exe';if(-not(Test-Path -LiteralPath $updateExe)){throw 'INSTALLER_HARDENING_UPDATE_EXE_MISSING'};Invoke-ExactWindowsExe $updateExe @('apply','--package',$FullPackage,'--norestart')|Out-Null}
function Get-RestrictedPath{$system=@((Join-Path $env:SystemRoot 'System32'),$env:SystemRoot,(Join-Path $env:SystemRoot 'System32\Wbem'),(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0'));return ($system -join ';')}
function Assert-NoGlobalTool([string]$Name,[string]$RestrictedPath){$where=Invoke-ExactWindowsExe (Join-Path $env:SystemRoot 'System32\where.exe') @("$Name.exe") @{PATH=$RestrictedPath} -AllowFailure;if($where.ExitCode -eq 0){throw "INSTALLER_HARDENING_GLOBAL_TOOL_VISIBLE:$Name output=$($where.Output)"}}
function Assert-LayoutIsolation{$appRoot=[IO.Path]::GetFullPath((Join-Path $installRoot 'current'));$roots=@($dataRoot,$cacheRoot,$logsRoot,$updatesRoot)|ForEach-Object{[IO.Path]::GetFullPath($_)};foreach($candidate in $roots){if($candidate.StartsWith($appRoot,[StringComparison]::OrdinalIgnoreCase)){throw "INSTALLER_HARDENING_STATE_INSIDE_APP:$candidate"}};foreach($name in @('data','cache','logs','updates')){if(Test-Path -LiteralPath (Join-Path $appRoot $name)){throw "INSTALLER_HARDENING_MUTABLE_DIR_INSIDE_APP:$name"}}}
function Assert-LongPathCoverage{$deepPath=[IO.Path]::GetFullPath((Join-Path $installRoot 'current\meta\product.json'));if($deepPath.Length -le 260){throw "INSTALLER_HARDENING_LONG_PATH_TOO_SHORT:$($deepPath.Length)"};$updatePath=[IO.Path]::GetFullPath((Join-Path $installRoot 'Update.exe'));if($updatePath.Length -ge 260){throw "INSTALLER_HARDENING_UPDATER_LAUNCH_PATH_TOO_LONG:$($updatePath.Length)"}}
function Invoke-StandardUserInstall([hashtable]$Environment){
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=[Security.Principal.WindowsPrincipal]::new($identity);$currentIsAdmin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if(-not $currentIsAdmin){Invoke-Installer $Environment;return}
    $newLocalUser=Get-Command New-LocalUser -ErrorAction SilentlyContinue;$removeLocalUser=Get-Command Remove-LocalUser -ErrorAction SilentlyContinue
    if(-not $newLocalUser -or -not $removeLocalUser){throw 'INSTALLER_HARDENING_STANDARD_USER_PREREQUISITE_MISSING'}
    $userName=("CloudOSStd"+[Guid]::NewGuid().ToString('N').Substring(0,10));$passwordText=("C0s!"+[Guid]::NewGuid().ToString('N')+"aA9");$secure=ConvertTo-SecureString $passwordText -AsPlainText -Force;$credential=[Management.Automation.PSCredential]::new("$env:COMPUTERNAME\$userName",$secure)
    try{
        New-LocalUser -Name $userName -Password $secure -PasswordNeverExpires -UserMayNotChangePassword|Out-Null
        $acl=Get-Acl -LiteralPath $testRoot;$rule=[Security.AccessControl.FileSystemAccessRule]::new("$env:COMPUTERNAME\$userName",'Modify','ContainerInherit,ObjectInherit','None','Allow');$acl.AddAccessRule($rule);Set-Acl -LiteralPath $testRoot -AclObject $acl
        $wrapper=Join-Path $testRoot 'standard-user-install.cmd'
        @"
@echo off
setlocal
set "PATH=$($Environment['PATH'])"
"$($package.setup)" --silent --installto "$installRoot" --log "$setupLog"
exit /b %ERRORLEVEL%
"@ | Set-Content -LiteralPath $wrapper -Encoding ascii
        $process=Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',"`"$wrapper`"") -WorkingDirectory $testRoot -Credential $credential -LoadUserProfile -Wait -PassThru
        if($process.ExitCode -ne 0){throw "INSTALLER_HARDENING_STANDARD_USER_INSTALL_FAILED:$($process.ExitCode)"}
    }finally{try{Remove-LocalUser -Name $userName -ErrorAction SilentlyContinue}catch{}}
}

$restrictedPath=Get-RestrictedPath
Assert-NoGlobalTool 'node' $restrictedPath;Assert-NoGlobalTool 'go' $restrictedPath
$restrictedEnvironment=@{PATH=$restrictedPath;CLOUDOS_LOCAL_ROOT=$localRoot}
$standardUser=$false;$existing=$false;$reinstall=$false;$multiple=$false;$updated=$false;$rollbackThenInstall=$false
try{
    Invoke-StandardUserInstall $restrictedEnvironment;$standardUser=$true;Assert-InstalledVersion ([string]$fixture.currentVersion);Assert-DataPreserved;Assert-LayoutIsolation;Assert-LongPathCoverage
    Invoke-Installer $restrictedEnvironment;$existing=$true;Assert-InstalledVersion ([string]$fixture.currentVersion);Assert-DataPreserved
    Invoke-Installer $restrictedEnvironment;$reinstall=$true;$multiple=$true;Assert-InstalledVersion ([string]$fixture.currentVersion);Assert-DataPreserved
    Invoke-Update ([string]$fixture.nextFullPackage);$updated=$true;Assert-InstalledVersion ([string]$fixture.nextVersion);Assert-DataPreserved
    Invoke-Update ([string]$fixture.currentFullPackage);Assert-InstalledVersion ([string]$fixture.currentVersion);Assert-DataPreserved;Invoke-Installer $restrictedEnvironment;$rollbackThenInstall=$true;Assert-InstalledVersion ([string]$fixture.currentVersion);Assert-DataPreserved
    $packagedNode=Join-Path $installRoot 'current\runtime\node.exe';$node=Invoke-ExactWindowsExe $packagedNode @('--version') @{PATH=$restrictedPath};if($node.Output.Trim() -ne 'v22.23.2'){throw "INSTALLER_HARDENING_PACKAGED_NODE_INVALID:$($node.Output)"}
    Write-Host "PRODUCTIZATION_INSTALLER_HARDENING_OK existing=$existing reinstall=$reinstall afterRollback=$rollbackThenInstall longPath=true multiple=$multiple updateExisting=$updated noGlobalNode=true noGlobalGo=true standardUser=$standardUser layoutIsolation=true dataPreserved=true"
}finally{if(Test-Path -LiteralPath (Join-Path $installRoot 'Update.exe')){try{Invoke-ExactWindowsExe (Join-Path $installRoot 'Update.exe') @('uninstall','--silent') -AllowFailure|Out-Null}catch{}};Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue}
