param(
    [Parameter(Mandatory)][string]$DataRoot,
    [switch]$RemoveData,
    [switch]$RemoveBackups,
    [switch]$RemoveLogs,
    [string]$Confirmation
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($DataRoot)
if(-not(Test-Path -LiteralPath $root)){Write-Host "CLOUDOS_DATA_ALREADY_ABSENT root=$root";exit 0}
if($RemoveData -and $Confirmation -ne 'REMOVER DADOS CLOUDOS'){throw 'DATA_REMOVAL_STRONG_CONFIRMATION_REQUIRED'}

$targets=New-Object System.Collections.Generic.List[string]
if($RemoveData){
    foreach($name in @('data','settings','workspaces','preferences','app-state','cache','updates','runtime')){$targets.Add((Join-Path $root $name))}
    foreach($name in @('bootstrap-state.json','prerequisites-v1.json','distribution-state.json','restore-session-invalidated.marker')){$targets.Add((Join-Path $root $name))}
}
if($RemoveBackups){$targets.Add((Join-Path $root 'backups'))}
if($RemoveLogs){$targets.Add((Join-Path $root 'logs'))}
foreach($target in $targets){
    $full=[IO.Path]::GetFullPath($target)
    if(-not $full.StartsWith($root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "UNINSTALL_PATH_ESCAPE:$full"}
    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "CLOUDOS_DATA_CLEANUP_OK data=$RemoveData backups=$RemoveBackups logs=$RemoveLogs root=$root"
