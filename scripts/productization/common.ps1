Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProductizationScriptRoot = Split-Path -Parent $PSCommandPath
$script:CloudOSRepoRoot = (Resolve-Path (Join-Path $script:ProductizationScriptRoot '..\..')).Path
$script:ProductConfigPath = Join-Path $script:CloudOSRepoRoot 'productization\cloudos-product.json'

function Get-CloudOSRepoRoot { return $script:CloudOSRepoRoot }

function Get-CloudOSProductConfig {
    if (-not (Test-Path -LiteralPath $script:ProductConfigPath)) { throw "PRODUCT_CONFIG_MISSING:$script:ProductConfigPath" }
    $config = Get-Content -LiteralPath $script:ProductConfigPath -Raw | ConvertFrom-Json
    if ($config.schemaVersion -ne 1) { throw "PRODUCT_CONFIG_SCHEMA_UNSUPPORTED:$($config.schemaVersion)" }
    return $config
}

function Get-CloudOSGitSha {
    Push-Location $script:CloudOSRepoRoot
    try {
        $sha = (& git rev-parse HEAD 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $sha -notmatch '^[0-9a-f]{40}$') { throw "GIT_HEAD_UNAVAILABLE:$sha" }
        return $sha
    } finally { Pop-Location }
}

function Assert-CloudOSProductizationBranch {
    param([switch]$AllowDetached)
    $config = Get-CloudOSProductConfig
    Push-Location $script:CloudOSRepoRoot
    try {
        $branch = (& git branch --show-current 2>&1 | Out-String).Trim()
        if (-not $AllowDetached -and $branch -ne 'productization/cloudos-distribution-batch-2') {
            throw "PRODUCTIZATION_BRANCH_REQUIRED:actual=$branch"
        }
        & git merge-base --is-ancestor $config.baseSha HEAD
        if ($LASTEXITCODE -ne 0) { throw "PRODUCTIZATION_BASE_MISMATCH:required=$($config.baseSha)" }
        & git merge-base --is-ancestor $config.officialBaseSha HEAD
        if ($LASTEXITCODE -ne 0) { throw "OFFICIAL_BASE_NOT_ANCESTOR:required=$($config.officialBaseSha)" }
    } finally { Pop-Location }
}

function Invoke-CloudOSExternal {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $script:CloudOSRepoRoot,
        [switch]$Capture,
        [switch]$AllowFailure
    )
    Push-Location $WorkingDirectory
    try {
        if ($Capture) {
            $output = & $FilePath @Arguments 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
            if (-not $AllowFailure -and $exitCode -ne 0) { throw "COMMAND_FAILED:$FilePath exit=$exitCode`n$output" }
            return [pscustomobject]@{ ExitCode = $exitCode; Output = $output.Trim() }
        }
        & $FilePath @Arguments
        $exitCode = $LASTEXITCODE
        if (-not $AllowFailure -and $exitCode -ne 0) { throw "COMMAND_FAILED:$FilePath exit=$exitCode" }
        return $exitCode
    } finally { Pop-Location }
}

function Get-CloudOSCommandName {
    param([Parameter(Mandatory)][string]$BaseName)
    if ($IsWindows) {
        $cmd = Get-Command "$BaseName.cmd" -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        $exe = Get-Command "$BaseName.exe" -ErrorAction SilentlyContinue
        if ($exe) { return $exe.Source }
    }
    $plain = Get-Command $BaseName -ErrorAction SilentlyContinue
    if ($plain) { return $plain.Source }
    throw "TOOL_NOT_FOUND:$BaseName"
}

function Ensure-CloudOSDirectory {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-CloudOSArtifactPaths {
    $config = Get-CloudOSProductConfig
    $artifacts = Ensure-CloudOSDirectory (Join-Path $script:CloudOSRepoRoot 'artifacts')
    $build = Ensure-CloudOSDirectory (Join-Path $artifacts 'build')
    $tools = Ensure-CloudOSDirectory (Join-Path $artifacts 'tools')
    $toolcache = Ensure-CloudOSDirectory (Join-Path $artifacts 'toolcache')
    $staging = Join-Path $artifacts "staging\$($config.version)\$($config.rid)"
    $releases = Join-Path $artifacts "releases\$($config.version)\$($config.rid)"
    $portable = Join-Path $artifacts "portable\$($config.version)\$($config.rid)"
    return [pscustomobject]@{ Artifacts=$artifacts; Build=$build; Tools=$tools; ToolCache=$toolcache; Staging=$staging; Releases=$releases; Portable=$portable }
}

function Ensure-CloudOSNodeRuntime {
    $config = Get-CloudOSProductConfig
    $paths = Get-CloudOSArtifactPaths
    $version = [string]$config.nodeVersion
    $archiveName = "node-v$version-win-x64.zip"
    $cacheRoot = Ensure-CloudOSDirectory (Join-Path $paths.ToolCache "node-v$version-win-x64")
    $nodeExe = Join-Path $cacheRoot 'node.exe'
    if (Test-Path -LiteralPath $nodeExe) { return $cacheRoot }

    if (-not $IsWindows) { throw 'NODE_RUNTIME_DOWNLOAD_WINDOWS_ONLY' }
    $downloadRoot = Ensure-CloudOSDirectory (Join-Path $paths.ToolCache 'downloads')
    $archivePath = Join-Path $downloadRoot $archiveName
    $checksumsPath = Join-Path $downloadRoot "node-v$version-SHASUMS256.txt"
    $baseUrl = "https://nodejs.org/dist/v$version"
    Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/SHASUMS256.txt" -OutFile $checksumsPath
    $match = Get-Content -LiteralPath $checksumsPath | Where-Object { $_ -match "^([0-9a-fA-F]{64})\s+$([regex]::Escape($archiveName))$" } | Select-Object -First 1
    if (-not $match) { throw "NODE_CHECKSUM_NOT_FOUND:$archiveName" }
    $expected = ([regex]::Match($match, '^([0-9a-fA-F]{64})')).Groups[1].Value.ToLowerInvariant()
    Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/$archiveName" -OutFile $archivePath
    $actual = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "NODE_CHECKSUM_MISMATCH:expected=$expected actual=$actual" }

    $extractRoot = Join-Path $downloadRoot "node-extract-$version"
    Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force
    $source = Join-Path $extractRoot "node-v$version-win-x64"
    if (-not (Test-Path -LiteralPath (Join-Path $source 'node.exe'))) { throw 'NODE_ARCHIVE_LAYOUT_INVALID' }
    Copy-Item -LiteralPath (Join-Path $source 'node.exe') -Destination $nodeExe -Force
    foreach ($name in @('LICENSE','README.md')) {
        $sourceFile = Join-Path $source $name
        if (Test-Path -LiteralPath $sourceFile) { Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $cacheRoot $name) -Force }
    }
    Set-Content -LiteralPath (Join-Path $cacheRoot 'sha256.txt') -Value "$actual  $archiveName" -Encoding utf8
    Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    return $cacheRoot
}

function Write-CloudOSJson {
    param([Parameter(Mandatory)]$InputObject,[Parameter(Mandatory)][string]$Path,[int]$Depth=20)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $InputObject | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding utf8
}

function Get-CloudOSRelativePath {
    param([string]$Base,[string]$Path)
    return [IO.Path]::GetRelativePath($Base, $Path).Replace('\','/')
}

function New-CloudOSFileInventory {
    param([Parameter(Mandatory)][string]$Root)
    $files = Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName
    return @($files | ForEach-Object {
        [pscustomobject]@{
            path = Get-CloudOSRelativePath $Root $_.FullName
            size = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
}

function Write-CloudOSChecksums {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Path,[string[]]$Exclude=@())
    $excludeSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($item in $Exclude){ [void]$excludeSet.Add($item.Replace('\','/')) }
    $lines = foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName) {
        $relative = Get-CloudOSRelativePath $Root $file.FullName
        if ($excludeSet.Contains($relative)) { continue }
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
    Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
}

function Assert-CloudOSStagingClean {
    param([Parameter(Mandatory)][string]$Root)
    $forbiddenDirectories = @('node_modules','test-results','.git','logs','data','data-portable','cache','updates')
    $badDirs = Get-ChildItem -LiteralPath $Root -Directory -Recurse | Where-Object { $forbiddenDirectories -contains $_.Name }
    if ($badDirs) { throw "STAGING_FORBIDDEN_DIRECTORY:$((@($badDirs.FullName) -join ','))" }
    $badFiles = Get-ChildItem -LiteralPath $Root -File -Recurse | Where-Object {
        $_.Name -match '^\.env($|\.)|cloudos\.(json|db)$|\.(sqlite|sqlite3|db)$|\.log$' -or $_.Name -match '(secret|credential|private[_-]?key)' 
    }
    if ($badFiles) { throw "STAGING_FORBIDDEN_FILE:$((@($badFiles.FullName) -join ','))" }
}

function New-CloudOSDeterministicZip {
    param([Parameter(Mandatory)][string]$SourceDirectory,[Parameter(Mandatory)][string]$DestinationPath)
    Add-Type -AssemblyName System.IO.Compression
    $parent = Split-Path -Parent $DestinationPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    if (Test-Path -LiteralPath $DestinationPath) { Remove-Item -LiteralPath $DestinationPath -Force }
    $stream = [IO.File]::Open($DestinationPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
        try {
            $epoch = [DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
            foreach($file in Get-ChildItem -LiteralPath $SourceDirectory -File -Recurse | Sort-Object { Get-CloudOSRelativePath $SourceDirectory $_.FullName }) {
                $relative = Get-CloudOSRelativePath $SourceDirectory $file.FullName
                $entry = $zip.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = $epoch
                $input = [IO.File]::OpenRead($file.FullName)
                try { $output = $entry.Open(); try { $input.CopyTo($output) } finally { $output.Dispose() } } finally { $input.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }
    return $DestinationPath
}
