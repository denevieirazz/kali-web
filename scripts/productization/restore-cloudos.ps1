param(
    [Parameter(Mandatory)][string]$BackupPath,
    [Parameter(Mandatory)][string]$DataRoot,
    [Parameter(Mandatory)][switch]$ConfirmRestore
)
. (Join-Path $PSScriptRoot 'common.ps1')
if(-not $ConfirmRestore){throw 'RESTORE_EXPLICIT_CONFIRMATION_REQUIRED'}
$archive=[IO.Path]::GetFullPath($BackupPath)
if(-not(Test-Path -LiteralPath $archive -PathType Leaf)){throw "RESTORE_BACKUP_MISSING:$archive"}
$root=[IO.Path]::GetFullPath($DataRoot)
New-Item -ItemType Directory -Force -Path $root | Out-Null
$runtime=Join-Path $root 'runtime'
if(Test-Path -LiteralPath $runtime){
    $active=Get-ChildItem -LiteralPath $runtime -Filter 'backend-port.json' -File -Recurse -ErrorAction SilentlyContinue
    if($active){throw 'RESTORE_ACTIVE_SESSION_REFUSED:close CloudOS before restore'}
}

Add-Type -AssemblyName System.IO.Compression
$zip=[IO.Compression.ZipFile]::OpenRead($archive)
try{
    if($zip.Entries.Count -gt 50000){throw 'RESTORE_ARCHIVE_TOO_MANY_ENTRIES'}
    $total=[int64]0
    foreach($entry in $zip.Entries){
        $total+=[int64]$entry.Length
        if($total -gt 2GB){throw 'RESTORE_ARCHIVE_TOO_LARGE'}
        $name=$entry.FullName.Replace('\','/')
        if([string]::IsNullOrWhiteSpace($name)){continue}
        if($name.StartsWith('/') -or $name -match '^[A-Za-z]:' -or ($name -split '/') -contains '..'){throw "RESTORE_UNSAFE_ENTRY:$name"}
    }
}finally{$zip.Dispose()}

$work=Join-Path ([IO.Path]::GetTempPath()) "cloudos-restore-$([Guid]::NewGuid().ToString('N'))"
$rollback=Join-Path $work 'rollback'
$extract=Join-Path $work 'extract'
New-Item -ItemType Directory -Force -Path $rollback,$extract | Out-Null
$created=New-Object System.Collections.Generic.List[string]
$moved=New-Object System.Collections.Generic.List[object]
try{
    [IO.Compression.ZipFile]::ExtractToDirectory($archive,$extract)
    $manifestPath=Join-Path $extract 'manifest.json'
    if(-not(Test-Path -LiteralPath $manifestPath)){throw 'RESTORE_MANIFEST_MISSING'}
    $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if($manifest.schemaVersion -ne 1 -or $manifest.product -ne 'CloudOS'){throw 'RESTORE_MANIFEST_INVALID'}
    $config=Get-CloudOSProductConfig
    $backupMajor=([string]$manifest.productVersion -split '[.-]')[0]
    $currentMajor=([string]$config.version -split '[.-]')[0]
    if($backupMajor -ne $currentMajor){throw "RESTORE_INCOMPATIBLE_MAJOR:backup=$backupMajor current=$currentMajor"}

    $payload=Join-Path $extract 'payload'
    foreach($item in @($manifest.files)){
        $relative=[string]$item.path
        if([string]::IsNullOrWhiteSpace($relative) -or ($relative -split '/') -contains '..'){throw "RESTORE_MANIFEST_UNSAFE_PATH:$relative"}
        $source=Join-Path $payload ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
        if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "RESTORE_PAYLOAD_MISSING:$relative"}
        $actual=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        if($actual -ne ([string]$item.sha256).ToLowerInvariant()){throw "RESTORE_CHECKSUM_MISMATCH:$relative"}
    }

    Write-Host "CLOUDOS_RESTORE_CONTENT version=$($manifest.productVersion) files=$(@($manifest.files).Count)"
    foreach($item in @($manifest.files)){
        $relative=[string]$item.path
        $source=Join-Path $payload ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
        $destination=[IO.Path]::GetFullPath((Join-Path $root ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))))
        if(-not $destination.StartsWith($root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "RESTORE_DESTINATION_ESCAPE:$relative"}
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        if(Test-Path -LiteralPath $destination){
            $safe=Join-Path $rollback ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $safe) | Out-Null
            Move-Item -LiteralPath $destination -Destination $safe -Force
            $moved.Add([pscustomobject]@{Destination=$destination;Backup=$safe})
        }else{$created.Add($destination)}
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    Set-Content -LiteralPath (Join-Path $root 'restore-session-invalidated.marker') -Value ([DateTimeOffset]::UtcNow.ToString('O')) -Encoding utf8
    Write-Host "CLOUDOS_RESTORE_OK root=$root"
}catch{
    foreach($path in $created){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}
    foreach($entry in @($moved) | Select-Object -Reverse){
        Remove-Item -LiteralPath $entry.Destination -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $entry.Destination) | Out-Null
        if(Test-Path -LiteralPath $entry.Backup){Move-Item -LiteralPath $entry.Backup -Destination $entry.Destination -Force}
    }
    throw
}finally{Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}
