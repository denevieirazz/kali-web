Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reportPath=Join-Path $root 'RELEASE_CANDIDATE_AUDIT.md'
if(-not(Test-Path -LiteralPath $reportPath -PathType Leaf)){throw 'RC_AUDIT_REPORT_MISSING'}
$report=Get-Content -LiteralPath $reportPath -Raw
foreach($heading in @('CONFIRMADO NO CÓDIGO','CONFIRMADO EM TESTES','CONFIRMADO EM CI','CONFIRMADO EM VALIDAÇÃO FÍSICA','NÃO CONFIRMADO','RISCOS','DÍVIDAS TÉCNICAS','PÓS-RC')){if($report -notmatch "(?m)^## $([regex]::Escape($heading))\s*$"){throw "RC_AUDIT_HEADING_MISSING:$heading"}}
$validation=Get-Content -LiteralPath (Join-Path $root 'productization\validation.json') -Raw|ConvertFrom-Json
if([string]$validation.status -ne 'not-run' -or [string]$validation.visualValidation -ne 'not-run'){throw 'RC_AUDIT_PHYSICAL_STATUS_MUST_REMAIN_NOT_RUN'}
foreach($obsolete in @('Reverter-Ultima-Correcao-Core-UI.ps1','Reverter-Ultima-Correcao-Core-UI.cmd')){if(Test-Path -LiteralPath (Join-Path $root $obsolete)){throw "RC_AUDIT_OBSOLETE_ROLLBACK_PRESENT:$obsolete"}}
$broken=New-Object System.Collections.Generic.List[string]
foreach($workflow in Get-ChildItem -LiteralPath (Join-Path $root '.github\workflows') -File|Where-Object{$_.Extension -in @('.yml','.yaml')}){
 $text=Get-Content -LiteralPath $workflow.FullName -Raw
 foreach($match in [regex]::Matches($text,'(?i)(?:\./)?scripts/productization/[A-Za-z0-9_.\-/]+\.ps1')){$relative=$match.Value.TrimStart('.','/').Replace('/','\');if(-not(Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)){[void]$broken.Add("$($workflow.Name):$relative")}}
}
if($broken.Count -gt 0){throw "RC_AUDIT_BROKEN_WORKFLOW_PATHS:$($broken -join ',')"}
foreach($required in @('scripts\start-cloudos.ps1','scripts\stop-cloudos.ps1','scripts\run-native-host.ps1','scripts\productization\test-installer-hardening.ps1','scripts\productization\test-packaged-node-runtime.ps1','scripts\productization\test-release-candidate-orphans.ps1','scripts\productization\audit-artifact-security.ps1','scripts\productization\export-diagnostics.ps1')){if(-not(Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)){throw "RC_AUDIT_REQUIRED_PATH_MISSING:$required"}}
$installer=Get-Content -LiteralPath (Join-Path $root 'scripts\productization\test-installer-hardening.ps1') -Raw
foreach($token in @('noGlobalNode=true','noGlobalGo=true')){if($installer.IndexOf($token,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "RC_AUDIT_INSTALLER_ASSERTION_MISSING:$token"}}
$package=Get-Content -LiteralPath (Join-Path $root 'scripts\productization\package-cloudos.ps1') -Raw
if($package -notmatch 'runtime[\\/]node\.exe' -or $package -notmatch 'runtime/cloudos-core'){throw 'RC_AUDIT_PACKAGED_RUNTIME_INVENTORY_MISSING'}
Write-Host 'PRODUCTIZATION_RC_AUDIT_OK brokenPaths=false obsoleteScripts=false physical=false visual=false globalNodeRuntime=false globalGoRuntime=false'
