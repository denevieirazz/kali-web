. (Join-Path $PSScriptRoot 'common.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) "cloudos-backup-test-$([Guid]::NewGuid().ToString('N'))"
$source=Join-Path $root 'source';$restored=Join-Path $root 'restored';$out=Join-Path $root 'out'
try{
    New-Item -ItemType Directory -Force -Path (Join-Path $source 'data'),(Join-Path $source 'settings'),(Join-Path $source 'logs'),$out | Out-Null
    Set-Content -LiteralPath (Join-Path $source 'data\cloudos.json') -Value '{"users":[{"password_hash":"hashed"}]}' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $source 'settings\ui.json') -Value '{"theme":"dark"}' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $source 'logs\private.log') -Value 'must-not-backup' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $source 'settings\access-token.txt') -Value 'must-not-backup' -Encoding utf8
    $archive=& (Join-Path $PSScriptRoot 'backup-cloudos.ps1') -DataRoot $source -OutputDirectory $out -ProductVersion '1.1.0-batch2.1' -Head ('a'*40)
    if(-not(Test-Path -LiteralPath $archive)){throw 'BACKUP_TEST_ARCHIVE_MISSING'}
    & (Join-Path $PSScriptRoot 'restore-cloudos.ps1') -BackupPath $archive -DataRoot $restored -ConfirmRestore
    if((Get-Content -LiteralPath (Join-Path $restored 'data\cloudos.json') -Raw) -notmatch 'password_hash'){throw 'BACKUP_TEST_DB_NOT_RESTORED'}
    if((Get-Content -LiteralPath (Join-Path $restored 'settings\ui.json') -Raw) -notmatch 'dark'){throw 'BACKUP_TEST_SETTINGS_NOT_RESTORED'}
    if(Test-Path -LiteralPath (Join-Path $restored 'logs\private.log')){throw 'BACKUP_TEST_LOG_LEAK'}
    if(Test-Path -LiteralPath (Join-Path $restored 'settings\access-token.txt')){throw 'BACKUP_TEST_SECRET_LEAK'}
    $before=(Get-Content -LiteralPath (Join-Path $restored 'data\cloudos.json') -Raw)
    Add-Type -AssemblyName System.IO.Compression
    $bad=Join-Path $out 'corrupt.zip';Copy-Item -LiteralPath $archive -Destination $bad
    $zip=[IO.Compression.ZipFile]::Open($bad,[IO.Compression.ZipArchiveMode]::Update)
    try{$entry=$zip.GetEntry('payload/data/cloudos.json');$entry.Delete();$entry=$zip.CreateEntry('payload/data/cloudos.json');$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write('tampered')}finally{$writer.Dispose()}}finally{$zip.Dispose()}
    $failed=$false;try{& (Join-Path $PSScriptRoot 'restore-cloudos.ps1') -BackupPath $bad -DataRoot $restored -ConfirmRestore}catch{$failed=$true}
    if(-not $failed){throw 'BACKUP_TEST_TAMPER_ACCEPTED'}
    if((Get-Content -LiteralPath (Join-Path $restored 'data\cloudos.json') -Raw) -ne $before){throw 'BACKUP_TEST_FAILED_RESTORE_MUTATED_DATA'}
    Write-Host 'PRODUCTIZATION_BACKUP_RESTORE_OK'
}finally{Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
