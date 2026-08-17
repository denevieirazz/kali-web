Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reportPath=Join-Path $root 'RELEASE_CANDIDATE_AUDIT.md'
if(-not(Test-Path -LiteralPath $reportPath -PathType Leaf)){throw 'RC_AUDIT_REPORT_MISSING'}
$report=Get-Content -LiteralPath $reportPath -Raw
foreach($heading in @('CONFIRMADO NO CÓDIGO','CONFIRMADO EM TESTES','CONFIRMADO EM CI','CONFIRMADO EM VALIDAÇÃO FÍSICA','NÃO CONFIRMADO','RISCOS','DÍVIDAS TÉCNICAS','PÓS-RC')){
    if($report -notmatch "(?m)^## $([regex]::Escape($heading))\s*$"){throw "RC_AUDIT_HEADING_MISSING:$heading"}
}
$validation=Get-Content -LiteralPath (Join-Path $root 'productization\validation.json') -Raw|ConvertFrom-Json
if([string]$validation.status -ne 'not-run' -or [string]$validation.visualValidation -ne 'not-run'){throw 'RC_AUDIT_PHYSICAL_STATUS_MUST_REMAIN_NOT_RUN'}
foreach($obsolete in @('Reverter-Ultima-Correcao-Core-UI.ps1','Reverter-Ultima-Correcao-Core-UI.cmd')){
    if(Test-Path -LiteralPath (Join-Path $root $obsolete)){throw "RC_AUDIT_OBSOLETE_ROLLBACK_PRESENT:$obsolete"}
}
$broken=New-Object System.Collections.Generic.List[string]
foreach($workflow in Get-ChildItem -LiteralPath (Join-Path $root '.github\workflows') -File|Where-Object{$_.Extension -in @('.yml','.yaml')}){
    $text=Get-Content -LiteralPath $workflow.FullName -Raw
    foreach($match in [regex]::Matches($text,'(?i)(?:\./)?scripts/productization/[A-Za-z0-9_.\-/]+\.ps1')){
        $relative=$match.Value.TrimStart('.','/').Replace('/','\')
        if(-not(Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)){[void]$broken.Add("$($workflow.Name):$relative")}
    }
    if($text -match 'release(s)?\s*:\s*write|gh\s+release|create-release|softprops/action-gh-release'){throw "RC_AUDIT_RELEASE_PUBLICATION_PRESENT:$($workflow.Name)"}
}
if($broken.Count -gt 0){throw "RC_AUDIT_BROKEN_WORKFLOW_PATHS:$($broken -join ',')"}
foreach($required in @(
    'scripts\productization\test-installer-hardening.ps1',
    'scripts\productization\test-packaged-node-runtime.ps1',
    'scripts\productization\test-release-candidate-orphans.ps1',
    'scripts\productization\measure-release-candidate.ps1',
    'scripts\productization\audit-artifact-security.ps1',
    'scripts\productization\export-diagnostics.ps1')){
    if(-not(Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)){throw "RC_AUDIT_REQUIRED_PATH_MISSING:$required"}
}
$bootstrap=Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.Bootstrap\App.xaml.cs') -Raw
foreach($token in @('RunWebOnlyAsync','WebOnlySession','BootstrapSupervisor','ReadinessReached','StabilityReached','StopAsync')){
    if($bootstrap.IndexOf($token,[StringComparison]::Ordinal) -lt 0){throw "RC_AUDIT_BOOTSTRAP_CONTRACT_MISSING:$token"}
}
$updater=Get-Content -LiteralPath (Join-Path $root 'desktop\CloudOS.Bootstrap\DistributionUpdateService.cs') -Raw
if($updater -notmatch 'AllowVersionDowngrade\s*=\s*false'){throw 'RC_AUDIT_DOWNGRADE_GUARD_MISSING'}
if($updater -notmatch 'UriSchemeHttps'){throw 'RC_AUDIT_HTTPS_UPDATE_GUARD_MISSING'}
$installer=Get-Content -LiteralPath (Join-Path $root 'scripts\productization\test-installer-hardening.ps1') -Raw
foreach($token in @('noGlobalNode=true','noGlobalGo=true','noNodeModules=true')){
    if($installer.IndexOf($token,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "RC_AUDIT_INSTALLER_ASSERTION_MISSING:$token"}
}
$package=Get-Content -LiteralPath (Join-Path $root 'scripts\productization\package-cloudos.ps1') -Raw
foreach($token in @('runtime/node.exe','runtime/cloudos-core','supply-chain.json','portable-manifest.json','portable-checksums.sha256')){
    if($package.IndexOf($token,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "RC_AUDIT_PACKAGE_CONTRACT_MISSING:$token"}
}
foreach($uiPath in @('desktop\CloudOS.Bootstrap\UpdateWindow.cs','desktop\CloudOS.Bootstrap\RecoveryWindow.xaml.cs')){
    $ui=Get-Content -LiteralPath (Join-Path $root $uiPath) -Raw
    $rawException='\{(?:error|ex|exception|storageError|rollbackError)\.Message\}'
    if($ui -match "(?m)_status\.Text\s*=\s*\$\"[^\"\r\n]*$rawException" -or $ui -match "(?m)MessageBox\.Show\(\s*\$\"[^\"\r\n]*$rawException"){
        throw "RC_AUDIT_RAW_EXCEPTION_IN_UI:$uiPath"
    }
}
$workflow=Get-Content -LiteralPath (Join-Path $root '.github\workflows\productization-batch2-ci.yml') -Raw
foreach($token in @('test-release-candidate-audit.ps1','test-release-candidate-orphans.ps1','measure-release-candidate.ps1','test-wsl-core-package-smoke.ps1 -SkipIfUnavailable')){
    if($workflow.IndexOf($token,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "RC_AUDIT_CI_GATE_MISSING:$token"}
}
Write-Host 'PRODUCTIZATION_RC_AUDIT_OK brokenPaths=false obsoleteScripts=false physical=false visual=false globalNodeRuntime=false globalGoRuntime=false uiRawExceptions=false'
