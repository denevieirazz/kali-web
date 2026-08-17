Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'common.ps1')
$config=Get-Content -LiteralPath (Join-Path $root 'productization\cloudos-product.json') -Raw | ConvertFrom-Json
if($config.baseSha -ne 'ffaa9fd302065fbfd7c7123896d19465c1cd3e8a'){throw 'PRODUCTIZATION_BASE_CONTRACT_CHANGED'}
if($config.officialBaseSha -ne '2d3380ba562d23e05947f81cc9581e8fe9bcfdbc'){throw 'OFFICIAL_BASE_CONTRACT_CHANGED'}
if($config.velopackVersion -ne '1.2.0'){throw 'VELOPACK_NOT_PINNED_1_2_0'}
if($config.signing -ne 'unsigned-development' -or $config.stableUpdatesEnabled){throw 'RELEASE_SAFETY_CONTRACT_CHANGED'}

$bootstrap=Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.Bootstrap\App.xaml.cs') -Raw
$bootstrapProject=Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.Bootstrap\CloudOS.Bootstrap.csproj') -Raw
if($bootstrap -notmatch [regex]::Escape('VelopackApp.Build().Run();')){throw 'VELOPACK_BOOTSTRAP_MISSING'}
if($bootstrapProject -notmatch 'PackageReference Include="Velopack" Version="1\.2\.0"'){throw 'VELOPACK_NUGET_VERSION_DRIFT'}
if($bootstrapProject -notmatch 'ApplicationDefinition Remove="App\.xaml"' -or $bootstrapProject -notmatch 'Page Include="App\.xaml"'){throw 'VELOPACK_WPF_MAIN_CONTRACT_MISSING'}

$contractPath=[IO.Path]::GetFullPath($PSCommandPath)
$allProductFiles=Get-ChildItem -LiteralPath (Join-Path $root 'scripts\productization') -File -Recurse | Where-Object {[IO.Path]::GetFullPath($_.FullName) -ne $contractPath}
$text=($allProductFiles | ForEach-Object {Get-Content -LiteralPath $_.FullName -Raw}) -join "`n"
foreach($forbidden in @('wsl.exe --update','wsl --update','wsl.exe --install','wsl --install','wsl.exe --unregister','wsl --unregister','Stop-Process -Name','taskkill /IM','gh release create')){
    if($text.IndexOf($forbidden,[StringComparison]::OrdinalIgnoreCase) -ge 0){throw "FORBIDDEN_PRODUCTIZATION_OPERATION:$forbidden"}
}
$probe=Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.Bootstrap\PrerequisiteProbe.cs') -Raw
if($probe -notmatch '"--version"' -or $probe -notmatch '"--list", "--verbose"'){throw 'WSL_READ_ONLY_PROBE_MISSING'}
if($probe -match '"--update"|"--install"|"--unregister"'){throw 'WSL_MUTATION_IN_PREREQUISITE_PROBE'}
$update=Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.Bootstrap\DistributionUpdateService.cs') -Raw
if($update -notmatch 'AllowVersionDowngrade = false'){throw 'SILENT_DOWNGRADE_GUARD_MISSING'}
if($update -notmatch 'UriSchemeHttps'){throw 'HTTPS_UPDATE_GUARD_MISSING'}
$hostSource=Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.Host\Runtime\CloudOsRuntimeSupervisor.cs') -Raw
if($hostSource -notmatch 'CLOUDOS_LOCAL_ROOT'){throw 'PORTABLE_LOCAL_ROOT_NOT_HONORED'}
$pack=Get-Content -LiteralPath (Join-Path $root 'scripts\productization\package-cloudos.ps1') -Raw
$packageAssertions=[ordered]@{
    manifest='Join-Path\s+\$meta\s+''manifest\.json'''
    components='Join-Path\s+\$meta\s+''components\.json'''
    supplyChain='Join-Path\s+\$meta\s+''supply-chain\.json'''
    checksums='Join-Path\s+\$meta\s+''checksums\.sha256'''
    portableManifest='portable-manifest\.json'
    portableChecksums='portable-checksums\.sha256'
    componentOrigin='origin='
    unsigned='unsigned-development'
    customPortable='--noPortable'
}
foreach($entry in $packageAssertions.GetEnumerator()){
    if($pack -notmatch $entry.Value){throw "PACKAGE_CONTRACT_MISSING:$($entry.Key)"}
}
foreach($requiredScript in @('artifact-audit-lib.ps1','audit-artifacts.ps1','test-artifact-policy.ps1')){
    if(-not(Test-Path -LiteralPath (Join-Path $PSScriptRoot $requiredScript) -PathType Leaf)){throw "ARTIFACT_AUDIT_SCRIPT_MISSING:$requiredScript"}
}
$workflowPath=Join-Path $root '.github\workflows\productization-batch2-ci.yml'
if(Test-Path -LiteralPath $workflowPath){
    $workflow=Get-Content -LiteralPath $workflowPath -Raw
    if($workflow -match 'release(s)?\s*:\s*write|gh\s+release|create-release|softprops/action-gh-release'){throw 'REAL_RELEASE_PUBLICATION_FORBIDDEN'}
    foreach($required in @('test-artifact-policy.ps1','audit-artifacts.ps1','artifacts/supply-chain.json','artifacts/audit/')){
        if($workflow.IndexOf($required,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "ARTIFACT_AUDIT_CI_CONTRACT_MISSING:$required"}
    }
}

$git=Get-CloudOSCommandName 'git'
$global:LASTEXITCODE=0
$gitVersion=Invoke-CloudOSExternal $git @('--version') $root -Capture
if($gitVersion.ExitCode -ne 0 -or $gitVersion.Output -notmatch '^git version '){throw 'EXTERNAL_COMMAND_SUCCESS_CONTRACT_FAILED'}
$missingRef='refs/heads/__cloudos_productization_contract_missing__'
$global:LASTEXITCODE=0
$gitFailure=Invoke-CloudOSExternal $git @('show-ref','--verify','--quiet',$missingRef) $root -Capture -AllowFailure
if($gitFailure.ExitCode -eq 0){throw 'EXTERNAL_COMMAND_FAILURE_CONTRACT_FAILED'}
if([int]$global:LASTEXITCODE -ne [int]$gitFailure.ExitCode){throw 'EXTERNAL_COMMAND_EXITCODE_NOT_STABLE'}

$baseCheck=Invoke-CloudOSExternal $git @('merge-base','--is-ancestor',[string]$config.baseSha,'HEAD') $root -Capture -AllowFailure
if($baseCheck.ExitCode -ne 0){throw 'BATCH1_BASE_NOT_ANCESTOR'}
$officialCheck=Invoke-CloudOSExternal $git @('merge-base','--is-ancestor',[string]$config.officialBaseSha,'HEAD') $root -Capture -AllowFailure
if($officialCheck.ExitCode -ne 0){throw 'OFFICIAL_BASE_NOT_ANCESTOR'}
Write-Host 'PRODUCTIZATION_CONTRACT_OK artifactAudit=true supplyChain=true'
