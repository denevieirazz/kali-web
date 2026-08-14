function Get-CloudOsNewestWriteTimeUtc {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Extensions = @()
    )

    if (-not (Test-Path -LiteralPath $Path)) { return [DateTime]::MinValue }
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction Stop
    if ($Extensions.Count -gt 0) {
        $normalized = @($Extensions | ForEach-Object { $_.ToLowerInvariant() })
        $files = @($files | Where-Object { $normalized -contains $_.Extension.ToLowerInvariant() })
    }
    if (-not $files -or $files.Count -eq 0) { return [DateTime]::MinValue }
    return ($files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
}

function Test-CloudOsFrontendDistFresh {
    param([Parameter(Mandatory = $true)][string]$Root)

    $source = Join-Path $Root 'frontend\src'
    if (-not (Test-Path -LiteralPath $source)) { return $true }
    $index = Join-Path $Root 'frontend\dist\index.html'
    if (-not (Test-Path -LiteralPath $index)) { return $false }

    $sourceNewest = Get-CloudOsNewestWriteTimeUtc -Path $source -Extensions @('.ts', '.tsx', '.js', '.jsx', '.css', '.html', '.json')
    $entryPoints = @(
        (Join-Path $Root 'frontend\package.json'),
        (Join-Path $Root 'frontend\vite.config.ts'),
        (Join-Path $Root 'frontend\index.html')
    ) | Where-Object { Test-Path -LiteralPath $_ }
    foreach ($entry in $entryPoints) {
        $stamp = (Get-Item -LiteralPath $entry).LastWriteTimeUtc
        if ($stamp -gt $sourceNewest) { $sourceNewest = $stamp }
    }

    return (Get-Item -LiteralPath $index).LastWriteTimeUtc -ge $sourceNewest
}

function Get-CloudOsPublishedHostState {
    param([Parameter(Mandatory = $true)][string]$Root)

    $source = Join-Path $Root 'desktop\CloudOS.Host'
    $publish = Join-Path $Root 'desktop\publish'
    $exe = Join-Path $publish 'CloudOS.Host.exe'
    $hostDll = Join-Path $publish 'CloudOS.Host.dll'
    $sourceExists = Test-Path -LiteralPath (Join-Path $source 'CloudOS.Host.csproj')
    $publishExists = Test-Path -LiteralPath $exe

    $missing = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $exe)) { $missing.Add('CloudOS.Host.exe') }
    if (-not (Test-Path -LiteralPath $hostDll)) { $missing.Add('CloudOS.Host.dll') }
    foreach ($assembly in @('Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.Wpf.dll')) {
        $found = $false
        if (Test-Path -LiteralPath $publish) {
            $found = $null -ne (Get-ChildItem -LiteralPath $publish -Recurse -File -Filter $assembly -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
        if (-not $found) { $missing.Add($assembly) }
    }

    $stale = $false
    if ($sourceExists -and $publishExists) {
        $sourceNewest = Get-CloudOsNewestWriteTimeUtc -Path $source -Extensions @('.cs', '.xaml', '.csproj', '.manifest')
        $publishNewest = Get-CloudOsNewestWriteTimeUtc -Path $publish
        $stale = $publishNewest -lt $sourceNewest
    }

    [pscustomobject]@{
        SourceCheckout = $sourceExists
        Exists = $publishExists
        Complete = $missing.Count -eq 0
        Stale = $stale
        Missing = @($missing)
        Usable = $publishExists -and $missing.Count -eq 0 -and -not $stale
        Executable = $exe
    }
}
