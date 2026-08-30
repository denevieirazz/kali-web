param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$sourceRoots = @(
    (Join-Path $rootPath 'desktop\CloudOS.NativeRuntime'),
    (Join-Path $rootPath 'desktop\CloudOS.NativeShell'),
    (Join-Path $rootPath 'desktop\CloudOS.NativeRecovery'),
    (Join-Path $rootPath 'scripts\native')
)

$excludedSegments = @('bin', 'obj', 'packages', '.vs', 'artifacts')
$files = New-Object System.Collections.Generic.List[System.IO.FileInfo]

foreach ($sourceRoot in $sourceRoots) {
    if (-not (Test-Path -LiteralPath $sourceRoot)) {
        throw "Native fingerprint source root missing: $sourceRoot"
    }

    Get-ChildItem -LiteralPath $sourceRoot -File -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring($rootPath.Length).TrimStart('\', '/')
        $segments = $relative -split '[\\/]'
        $excluded = $false
        foreach ($segment in $segments) {
            if ($excludedSegments -contains $segment) {
                $excluded = $true
                break
            }
        }
        if (-not $excluded) {
            $files.Add($_)
        }
    }
}

$ordered = $files | Sort-Object {
    $_.FullName.Substring($rootPath.Length).TrimStart('\', '/').ToLowerInvariant()
}

$builder = New-Object System.Text.StringBuilder
foreach ($file in $ordered) {
    $relative = $file.FullName.Substring($rootPath.Length).TrimStart('\', '/').Replace('\', '/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    [void]$builder.Append($relative)
    [void]$builder.Append('|')
    [void]$builder.Append($hash)
    [void]$builder.Append("`n")
}

$bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $digest = $sha.ComputeHash($bytes)
}
finally {
    $sha.Dispose()
}

([System.BitConverter]::ToString($digest) -replace '-', '').ToLowerInvariant()
