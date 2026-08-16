param(
    [Parameter(Mandatory)][string]$DataRoot,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$ProductVersion,
    [string]$Head
)
. (Join-Path $PSScriptRoot 'common.ps1')

$root=[IO.Path]::GetFullPath($DataRoot)
if(-not(Test-Path -LiteralPath $root)){throw "BACKUP_DATA_ROOT_MISSING:$root"}
$out=Ensure-CloudOSDirectory $OutputDirectory
$config=Get-CloudOSProductConfig
if([string]::IsNullOrWhiteSpace($ProductVersion)){$ProductVersion=[string]$config.version}
if([string]::IsNullOrWhiteSpace($Head)){try{$Head=Get-CloudOSGitSha}catch{$Head=[string]$config.baseSha}}
$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$work=Join-Path ([IO.Path]::GetTempPath()) "cloudos-backup-$([Guid]::NewGuid().ToString('N'))"
$payload=Join-Path $work 'payload'
New-Item -ItemType Directory -Force -Path $payload | Out-Null

$allowedTop=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($name in @('data','settings','workspaces','preferences','app-state')){[void]$allowedTop.Add($name)}
$allowedFiles=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($name in @('bootstrap-state.json','prerequisites-v1.json','distribution-state.json')){[void]$allowedFiles.Add($name)}
$forbiddenName='(^\.env($|\.)|secret|credential|private[_-]?key|access[_-]?token|refresh[_-]?token)'

try{
    $selected=New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach($file in Get-ChildItem -LiteralPath $root -File -Recurse){
        $relative=[IO.Path]::GetRelativePath($root,$file.FullName)
        $segments=$relative -split '[\\/]'
        $top=$segments[0]
        if($segments.Count -eq 1){if(-not $allowedFiles.Contains($file.Name)){continue}}
        elseif(-not $allowedTop.Contains($top)){continue}
        if($segments | Where-Object {$_ -in @('logs','cache','runtime','updates','backups','node_modules','test-results')}){continue}
        if($file.Name -match $forbiddenName){continue}
        $selected.Add($file)
    }

    foreach($file in $selected){
        $relative=[IO.Path]::GetRelativePath($root,$file.FullName)
        $destination=Join-Path $payload $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }

    $files=@(New-CloudOSFileInventory $payload)
    $manifest=[ordered]@{
        schemaVersion=1
        product='CloudOS'
        productVersion=$ProductVersion
        head=$Head
        createdAt=[DateTimeOffset]::UtcNow.ToString('O')
        source='explicit-user-backup'
        content=@($files | ForEach-Object {$_.path})
        files=$files
    }
    Write-CloudOSJson $manifest (Join-Path $work 'manifest.json') 40
    Write-CloudOSChecksums $payload (Join-Path $work 'checksums.sha256')
    $archive=Join-Path $out "CloudOSBackup-$stamp.zip"
    New-CloudOSDeterministicZip $work $archive | Out-Null
    Write-Host "CLOUDOS_BACKUP_OK path=$archive files=$($files.Count)"
    return $archive
}finally{
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
