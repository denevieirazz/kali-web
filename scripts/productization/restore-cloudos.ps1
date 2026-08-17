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
try{$zip=[IO.Compression.ZipFile]::OpenRead($archive)}catch{
    Write-Host 'CLOUDOS_RESTORE_FAILED code=RESTORE_ARCHIVE_INVALID'
    throw 'RESTORE_ARCHIVE_INVALID'
}
try{
    if($zip.Entries.Count -gt 50000){throw 'RESTORE_ARCHIVE_TOO_MANY_ENTRIES'}
    $total=[int64]0
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in $zip.Entries){
        $total+=[int64]$entry.Length
        if($total -gt 2GB){throw 'RESTORE_ARCHIVE_TOO_LARGE'}
        $name=$entry.FullName.Replace('\','/')
        if([string]::IsNullOrWhiteSpace($name)){continue}
        if($name.StartsWith('/') -or $name -match '^[A-Za-z]:' -or ($name -split '/') -contains '..'){throw "RESTORE_UNSAFE_ENTRY:$name"}
        if(-not $seen.Add($name)){throw "RESTORE_DUPLICATE_ENTRY:$name"}
    }
    if(-not $seen.Contains('manifest.json')){throw 'RESTORE_MANIFEST_MISSING'}
    if(-not $seen.Contains('checksums.sha256')){throw 'RESTORE_CHECKSUM_FILE_MISSING'}
}catch{
    Write-Host "CLOUDOS_RESTORE_FAILED code=$($_.Exception.Message)"
    throw
}finally{$zip.Dispose()}

$work=Join-Path ([IO.Path]::GetTempPath()) "cloudos-restore-$([Guid]::NewGuid().ToString('N'))"
$rollback=Join-Path $work 'rollback'
$extract=Join-Path $work 'extract'
New-Item -ItemType Directory -Force -Path $rollback,$extract | Out-Null
$created=New-Object System.Collections.Generic.List[string]
$moved=New-Object System.Collections.Generic.List[object]
try{
    try{$zip=[IO.Compression.ZipFile]::OpenRead($archive)}catch{throw 'RESTORE_ARCHIVE_INVALID'}
    try{
        $index=0
        foreach($entry in $zip.Entries){
            $name=$entry.FullName.Replace('\','/')
            if([string]::IsNullOrWhiteSpace($name)){continue}
            $destination=[IO.Path]::GetFullPath((Join-Path $extract ($name.Replace('/',[IO.Path]::DirectorySeparatorChar))))
            $prefix=$extract.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
            if(-not $destination.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "RESTORE_EXTRACTION_ESCAPE:$name"}
            if([string]::IsNullOrEmpty($entry.Name)){New-Item -ItemType Directory -Force -Path $destination | Out-Null;continue}
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
            $input=$entry.Open();$output=[IO.File]::Open($destination,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$input.CopyTo($output)}finally{$output.Dispose();$input.Dispose()}
            $index++
            if($env:NODE_ENV -eq 'test' -and $env:CLOUDOS_TEST_INTERRUPT_EXTRACTION -eq '1' -and $index -eq 1){throw 'RESTORE_EXTRACTION_INTERRUPTED'}
        }
    }finally{$zip.Dispose()}

    $manifestPath=Join-Path $extract 'manifest.json'
    try{$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json}catch{throw 'RESTORE_MANIFEST_JSON_INVALID'}
    if($manifest.schemaVersion -ne 1 -or $manifest.product -ne 'CloudOS' -or [string]::IsNullOrWhiteSpace([string]$manifest.productVersion)){throw 'RESTORE_MANIFEST_INVALID'}
    $items=@($manifest.files)
    if($items.Count -eq 0 -or @($manifest.content).Count -ne $items.Count){throw 'RESTORE_MANIFEST_INVALID'}
    $config=Get-CloudOSProductConfig
    $backupMajor=([regex]::Match([string]$manifest.productVersion,'^(\d+)')).Groups[1].Value
    $currentMajor=([regex]::Match([string]$config.version,'^(\d+)')).Groups[1].Value
    if([string]::IsNullOrWhiteSpace($backupMajor) -or [string]::IsNullOrWhiteSpace($currentMajor)){throw 'RESTORE_VERSION_INVALID'}
    if($backupMajor -ne $currentMajor){throw "RESTORE_INCOMPATIBLE_MAJOR:backup=$backupMajor current=$currentMajor"}

    $checksumPath=Join-Path $extract 'checksums.sha256'
    $checksumMap=@{}
    foreach($line in Get-Content -LiteralPath $checksumPath){
        if([string]::IsNullOrWhiteSpace($line)){continue}
        $match=[regex]::Match($line,'^([0-9a-fA-F]{64})\s{2}(.+)$')
        if(-not $match.Success){throw 'RESTORE_CHECKSUM_FILE_INVALID'}
        $relative=$match.Groups[2].Value.Replace('\','/')
        if([string]::IsNullOrWhiteSpace($relative) -or $relative.StartsWith('/') -or ($relative -split '/') -contains '..'){throw "RESTORE_CHECKSUM_PATH_INVALID:$relative"}
        if($checksumMap.ContainsKey($relative)){throw "RESTORE_CHECKSUM_DUPLICATE:$relative"}
        $checksumMap[$relative]=$match.Groups[1].Value.ToLowerInvariant()
    }
    if($checksumMap.Count -ne $items.Count){throw "RESTORE_CHECKSUM_COVERAGE_INVALID:checksums=$($checksumMap.Count) files=$($items.Count)"}

    $payload=Join-Path $extract 'payload'
    [int64]$requiredBytes=0
    $manifestPaths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($item in $items){
        $relative=[string]$item.path
        if([string]::IsNullOrWhiteSpace($relative) -or $relative.StartsWith('/') -or ($relative -split '/') -contains '..'){throw "RESTORE_MANIFEST_UNSAFE_PATH:$relative"}
        if(-not $manifestPaths.Add($relative)){throw "RESTORE_MANIFEST_DUPLICATE_PATH:$relative"}
        if(([string]$item.sha256) -notmatch '^[0-9a-fA-F]{64}$' -or [int64]$item.size -lt 0){throw "RESTORE_MANIFEST_FILE_INVALID:$relative"}
        if(-not $checksumMap.ContainsKey($relative)){throw "RESTORE_CHECKSUM_MISSING:$relative"}
        if($checksumMap[$relative] -ne ([string]$item.sha256).ToLowerInvariant()){throw "RESTORE_CHECKSUM_MANIFEST_MISMATCH:$relative"}
        $source=Join-Path $payload ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
        if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "RESTORE_PAYLOAD_MISSING:$relative"}
        $length=(Get-Item -LiteralPath $source).Length
        if($length -ne [int64]$item.size){throw "RESTORE_SIZE_MISMATCH:$relative"}
        $actual=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        if($actual -ne ([string]$item.sha256).ToLowerInvariant()){throw "RESTORE_CHECKSUM_MISMATCH:$relative"}
        $requiredBytes+=$length
    }
    $payloadFiles=@(Get-ChildItem -LiteralPath $payload -File -Recurse)
    if($payloadFiles.Count -ne $items.Count){throw "RESTORE_PAYLOAD_COVERAGE_INVALID:payload=$($payloadFiles.Count) files=$($items.Count)"}

    $available=[int64]([IO.DriveInfo]::new([IO.Path]::GetPathRoot($root))).AvailableFreeSpace
    if($env:NODE_ENV -eq 'test' -and $env:CLOUDOS_TEST_AVAILABLE_BYTES -match '^\d+$'){$available=[int64]$env:CLOUDOS_TEST_AVAILABLE_BYTES}
    if($requiredBytes -gt $available){throw "RESTORE_INSUFFICIENT_SPACE:required=$requiredBytes available=$available"}
    if($env:NODE_ENV -eq 'test' -and $env:CLOUDOS_TEST_DENY_RESTORE_WRITE -eq '1'){throw 'RESTORE_PERMISSION_DENIED'}
    $probe=Join-Path $root ".cloudos-restore-write-probe-$([Guid]::NewGuid().ToString('N')).tmp"
    try{[IO.File]::WriteAllText($probe,'probe')}catch{throw 'RESTORE_PERMISSION_DENIED'}finally{Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue}

    Write-Host "CLOUDOS_RESTORE_CONTENT version=$($manifest.productVersion) files=$($items.Count)"
    $commitIndex=0
    foreach($item in $items){
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
        $commitIndex++
        if($env:NODE_ENV -eq 'test' -and $env:CLOUDOS_TEST_INTERRUPT_RESTORE_AFTER -match '^\d+$' -and $commitIndex -eq [int]$env:CLOUDOS_TEST_INTERRUPT_RESTORE_AFTER){throw 'RESTORE_INTERRUPTED'}
    }
    Set-Content -LiteralPath (Join-Path $root 'restore-session-invalidated.marker') -Value ([DateTimeOffset]::UtcNow.ToString('O')) -Encoding utf8
    Write-Host "CLOUDOS_RESTORE_OK root=$root"
}catch{
    foreach($path in $created){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}
    for($rollbackIndex=$moved.Count-1;$rollbackIndex -ge 0;$rollbackIndex--){
        $entry=$moved[$rollbackIndex]
        Remove-Item -LiteralPath $entry.Destination -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $entry.Destination) | Out-Null
        if(Test-Path -LiteralPath $entry.Backup){Move-Item -LiteralPath $entry.Backup -Destination $entry.Destination -Force}
    }
    Write-Host "CLOUDOS_RESTORE_FAILED code=$($_.Exception.Message) rollback=true"
    throw
}finally{Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}
