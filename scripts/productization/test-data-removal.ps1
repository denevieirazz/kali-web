$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Join-Path ([IO.Path]::GetTempPath()) "cloudos-remove-test-$([Guid]::NewGuid().ToString('N'))"
$dataRoot=Join-Path $root 'CloudOS';$outside=Join-Path $root 'outside-sentinel.txt'
try{
    foreach($name in @('data','backups','logs','cache','updates','runtime')){New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot $name)|Out-Null;Set-Content -LiteralPath (Join-Path $dataRoot "$name\sentinel.txt") -Value $name -Encoding utf8}
    Set-Content -LiteralPath $outside -Value 'never-touch' -Encoding utf8
    & (Join-Path $PSScriptRoot 'remove-cloudos-data.ps1') -DataRoot $dataRoot
    foreach($name in @('data','backups','logs')){if(-not(Test-Path -LiteralPath (Join-Path $dataRoot "$name\sentinel.txt"))){throw "SAFE_DEFAULT_REMOVED:$name"}}
    $refused=$false
    try{& (Join-Path $PSScriptRoot 'remove-cloudos-data.ps1') -DataRoot $dataRoot -RemoveData -Confirmation 'nao'}catch{$refused=$true}
    if(-not $refused){throw 'DATA_REMOVAL_ACCEPTED_WEAK_CONFIRMATION'}
    if(-not(Test-Path -LiteralPath (Join-Path $dataRoot 'data\sentinel.txt'))){throw 'WEAK_CONFIRMATION_MUTATED_DATA'}
    & (Join-Path $PSScriptRoot 'remove-cloudos-data.ps1') -DataRoot $dataRoot -RemoveData -Confirmation 'REMOVER DADOS CLOUDOS'
    foreach($name in @('data','cache','updates','runtime')){if(Test-Path -LiteralPath (Join-Path $dataRoot $name)){throw "CONFIRMED_DATA_REMOVAL_LEFT:$name"}}
    foreach($name in @('backups','logs')){if(-not(Test-Path -LiteralPath (Join-Path $dataRoot "$name\sentinel.txt"))){throw "CONFIRMED_DATA_REMOVAL_REMOVED_PRESERVED:$name"}}
    & (Join-Path $PSScriptRoot 'remove-cloudos-data.ps1') -DataRoot $dataRoot -RemoveBackups -RemoveLogs
    foreach($name in @('backups','logs')){if(Test-Path -LiteralPath (Join-Path $dataRoot $name)){throw "EXPLICIT_OPTIONAL_REMOVAL_LEFT:$name"}}
    if((Get-Content -LiteralPath $outside -Raw).Trim() -ne 'never-touch'){throw 'DATA_REMOVAL_ESCAPED_ROOT'}
    Write-Host 'PRODUCTIZATION_DATA_REMOVAL_OK'
}finally{Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
