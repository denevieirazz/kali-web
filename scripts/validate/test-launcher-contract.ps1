$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$required=@(
 'Iniciar CloudOS.cmd','Diagnosticar CloudOS.cmd','Parar CloudOS.cmd',
 'scripts/launch/cloudos-launcher-common.ps1','scripts/launch/start-cloudos.ps1','scripts/launch/stop-cloudos.ps1','scripts/diagnostics/diagnose-cloudos.ps1'
)
foreach($relative in $required){if(-not(Test-Path(Join-Path $root $relative))){throw "LAUNCHER_FILE_MISSING:$relative"}}
$tokens=$null;$errors=$null
foreach($relative in $required|Where-Object{$_.EndsWith('.ps1')}){
 $tokens=$null;$errors=$null
 [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw "POWERSHELL_PARSE_FAILED:${relative}:$($errors[0].Message)"}
}
$common=Get-Content (Join-Path $root 'scripts/launch/cloudos-launcher-common.ps1') -Raw
$start=Get-Content (Join-Path $root 'scripts/launch/start-cloudos.ps1') -Raw
foreach($marker in @('backend.stdout.log','backend.stderr.log','frontend.stdout.log','frontend.stderr.log','host.log','bootstrap.log','wsl-core.log','result.json')){if(($common+$start)-notmatch [regex]::Escape($marker)){throw "LOG_CONTRACT_MISSING:$marker"}}
if($common -notmatch 'processes-\$When\.json'){throw 'LOG_CONTRACT_MISSING:processes-$When.json'}
foreach($mode in @('Full','WebOnly','Developer','UXValidation','FilesValidation','BrowserValidation','TerminalValidation')){if($common -notmatch [regex]::Escape($mode)){throw "MODE_MISSING:$mode"}}
if($common -notmatch 'HasExited'){throw 'EARLY_EXIT_GATE_MISSING'}
if($common -notmatch 'StartTime'){throw 'PROCESS_IDENTITY_GATE_MISSING'}
if($common -match 'Stop-Process\s+-Name\s+(node|dotnet)'){throw 'BROAD_PROCESS_KILL_FORBIDDEN'}
if($start -match 'npm\s+ci.*--prefix'){throw 'SUBFOLDER_NPM_CI_FORBIDDEN'}
Write-Host 'LAUNCHER_CONTRACT_OK'
