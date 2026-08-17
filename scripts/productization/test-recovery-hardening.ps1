param()
. (Join-Path $PSScriptRoot 'common.ps1')
Add-Type -AssemblyName System.IO.Compression
$temp=Join-Path ([IO.Path]::GetTempPath()) "cloudos-recovery-hardening-$([Guid]::NewGuid().ToString('N'))"
$source=Join-Path $temp 'source';$out=Join-Path $temp 'out';$target=Join-Path $temp 'target';$variants=Join-Path $temp 'variants'
New-Item -ItemType Directory -Force -Path (Join-Path $source 'data'),(Join-Path $source 'settings'),$out,$variants | Out-Null
Set-Content -LiteralPath (Join-Path $source 'data/account.json') -Value '{"version":"new","value":42}' -Encoding utf8
Set-Content -LiteralPath (Join-Path $source 'settings/ui.json') -Value '{"theme":"new"}' -Encoding utf8

function Reset-Target{
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path (Join-Path $target 'data'),(Join-Path $target 'settings') | Out-Null
    Set-Content -LiteralPath (Join-Path $target 'data/account.json') -Value '{"version":"old","value":7}' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $target 'settings/ui.json') -Value '{"theme":"old"}' -Encoding utf8
}
function Assert-Preserved{
    if((Get-Content -LiteralPath (Join-Path $target 'data/account.json') -Raw).Trim() -ne '{"version":"old","value":7}'){throw 'RECOVERY_OLD_DATA_NOT_PRESERVED:data/account.json'}
    if((Get-Content -LiteralPath (Join-Path $target 'settings/ui.json') -Raw).Trim() -ne '{"theme":"old"}'){throw 'RECOVERY_OLD_DATA_NOT_PRESERVED:settings/ui.json'}
    if(Test-Path -LiteralPath (Join-Path $target 'restore-session-invalidated.marker')){throw 'RECOVERY_FAILED_RESTORE_LEFT_SESSION_MARKER'}
}
function New-Variant{
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][scriptblock]$Mutate)
    $dir=Join-Path $variants "$Name-dir";$zipPath=Join-Path $variants "$Name.zip"
    Remove-Item -LiteralPath $dir,$zipPath -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($backup,$dir)
    & $Mutate $dir
    New-CloudOSDeterministicZip $dir $zipPath | Out-Null
    return $zipPath
}
function Assert-RestoreFailure{
    param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$Expected,[hashtable]$Environment=@{})
    Reset-Target
    $oldNode=$env:NODE_ENV;$oldAvailable=$env:CLOUDOS_TEST_AVAILABLE_BYTES;$oldDeny=$env:CLOUDOS_TEST_DENY_RESTORE_WRITE;$oldExtract=$env:CLOUDOS_TEST_INTERRUPT_EXTRACTION;$oldRestore=$env:CLOUDOS_TEST_INTERRUPT_RESTORE_AFTER
    try{
        $env:NODE_ENV='test'
        Remove-Item Env:CLOUDOS_TEST_AVAILABLE_BYTES,Env:CLOUDOS_TEST_DENY_RESTORE_WRITE,Env:CLOUDOS_TEST_INTERRUPT_EXTRACTION,Env:CLOUDOS_TEST_INTERRUPT_RESTORE_AFTER -ErrorAction SilentlyContinue
        foreach($key in $Environment.Keys){Set-Item -Path "Env:$key" -Value ([string]$Environment[$key])}
        $failed=$false;$message=''
        try{& (Join-Path $PSScriptRoot 'restore-cloudos.ps1') -BackupPath $Archive -DataRoot $target -ConfirmRestore | Out-Null}catch{$failed=$true;$message=$_.Exception.Message}
        if(-not $failed){throw "RECOVERY_NEGATIVE_CASE_ACCEPTED:$Expected"}
        if($message -notlike "$Expected*"){throw "RECOVERY_NEGATIVE_CASE_WRONG_ERROR:expected=$Expected actual=$message"}
        Assert-Preserved
    }finally{
        if($null -eq $oldNode){Remove-Item Env:NODE_ENV -ErrorAction SilentlyContinue}else{$env:NODE_ENV=$oldNode}
        foreach($pair in @(@('CLOUDOS_TEST_AVAILABLE_BYTES',$oldAvailable),@('CLOUDOS_TEST_DENY_RESTORE_WRITE',$oldDeny),@('CLOUDOS_TEST_INTERRUPT_EXTRACTION',$oldExtract),@('CLOUDOS_TEST_INTERRUPT_RESTORE_AFTER',$oldRestore))){
            if($null -eq $pair[1]){Remove-Item "Env:$($pair[0])" -ErrorAction SilentlyContinue}else{Set-Item "Env:$($pair[0])" -Value $pair[1]}
        }
    }
}

try{
    $backup=& (Join-Path $PSScriptRoot 'backup-cloudos.ps1') -DataRoot $source -OutputDirectory $out
    if(-not(Test-Path -LiteralPath $backup -PathType Leaf)){throw 'RECOVERY_BACKUP_FIXTURE_MISSING'}

    $corrupt=New-Variant 'corrupt-payload' {param($dir);Add-Content -LiteralPath (Join-Path $dir 'payload/data/account.json') -Value 'tampered'}
    Assert-RestoreFailure $corrupt 'RESTORE_SIZE_MISMATCH'

    $checksum=New-Variant 'checksum-invalid' {param($dir);$p=Join-Path $dir 'checksums.sha256';$lines=@(Get-Content -LiteralPath $p);$lines[0]=('0'*64)+'  '+(($lines[0] -split '\s{2}',2)[1]);Set-Content -LiteralPath $p -Value $lines -Encoding utf8}
    Assert-RestoreFailure $checksum 'RESTORE_CHECKSUM_MANIFEST_MISMATCH'

    $manifestInvalid=New-Variant 'manifest-invalid' {param($dir);$p=Join-Path $dir 'manifest.json';$m=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json;$m.schemaVersion=99;Write-CloudOSJson $m $p 40}
    Assert-RestoreFailure $manifestInvalid 'RESTORE_MANIFEST_INVALID'

    $incompatible=New-Variant 'version-incompatible' {param($dir);$p=Join-Path $dir 'manifest.json';$m=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json;$m.productVersion='999.0.0';Write-CloudOSJson $m $p 40}
    Assert-RestoreFailure $incompatible 'RESTORE_INCOMPATIBLE_MAJOR'

    $jsonInvalid=New-Variant 'json-invalid' {param($dir);Set-Content -LiteralPath (Join-Path $dir 'manifest.json') -Value '{invalid-json' -Encoding utf8}
    Assert-RestoreFailure $jsonInvalid 'RESTORE_MANIFEST_JSON_INVALID'

    $invalidZip=Join-Path $variants 'invalid.zip';Set-Content -LiteralPath $invalidZip -Value 'not-a-zip' -Encoding utf8
    Assert-RestoreFailure $invalidZip 'RESTORE_ARCHIVE_INVALID'

    $truncated=Join-Path $variants 'truncated.zip';$bytes=[IO.File]::ReadAllBytes($backup);[IO.File]::WriteAllBytes($truncated,$bytes[0..([Math]::Max(1,[int]($bytes.Length/2)))])
    Assert-RestoreFailure $truncated 'RESTORE_ARCHIVE_INVALID'

    Assert-RestoreFailure $backup 'RESTORE_EXTRACTION_INTERRUPTED' @{CLOUDOS_TEST_INTERRUPT_EXTRACTION='1'}
    Assert-RestoreFailure $backup 'RESTORE_INTERRUPTED' @{CLOUDOS_TEST_INTERRUPT_RESTORE_AFTER='1'}
    Assert-RestoreFailure $backup 'RESTORE_INSUFFICIENT_SPACE' @{CLOUDOS_TEST_AVAILABLE_BYTES='0'}
    Assert-RestoreFailure $backup 'RESTORE_PERMISSION_DENIED' @{CLOUDOS_TEST_DENY_RESTORE_WRITE='1'}

    Reset-Target
    & (Join-Path $PSScriptRoot 'restore-cloudos.ps1') -BackupPath $backup -DataRoot $target -ConfirmRestore | Out-Null
    if((Get-Content -LiteralPath (Join-Path $target 'data/account.json') -Raw).Trim() -ne '{"version":"new","value":42}'){throw 'RECOVERY_VALID_RESTORE_DATA_MISMATCH'}
    if((Get-Content -LiteralPath (Join-Path $target 'settings/ui.json') -Raw).Trim() -ne '{"theme":"new"}'){throw 'RECOVERY_VALID_RESTORE_SETTINGS_MISMATCH'}
    if(-not(Test-Path -LiteralPath (Join-Path $target 'restore-session-invalidated.marker'))){throw 'RECOVERY_VALID_RESTORE_MARKER_MISSING'}
    Write-Host 'PRODUCTIZATION_RECOVERY_HARDENING_OK corrupt=true truncated=true checksums=true manifest=true version=true json=true zip=true partialExtraction=true interrupted=true space=true permissions=true rollback=true preserved=true'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
