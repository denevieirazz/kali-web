$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'native-host-freshness.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('cloudos-freshness-' + [Guid]::NewGuid().ToString('N'))
try {
    $frontendSrc = Join-Path $root 'frontend\src'
    $frontendDist = Join-Path $root 'frontend\dist'
    $hostSource = Join-Path $root 'desktop\CloudOS.Host'
    $publish = Join-Path $root 'desktop\publish'
    New-Item -ItemType Directory -Force -Path $frontendSrc, $frontendDist, $hostSource, $publish | Out-Null

    Set-Content -LiteralPath (Join-Path $frontendSrc 'Browser.tsx') -Value 'source'
    Set-Content -LiteralPath (Join-Path $frontendDist 'index.html') -Value 'dist'
    (Get-Item -LiteralPath (Join-Path $frontendDist 'index.html')).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-5)
    (Get-Item -LiteralPath (Join-Path $frontendSrc 'Browser.tsx')).LastWriteTimeUtc = [DateTime]::UtcNow
    Assert-True (-not (Test-CloudOsFrontendDistFresh -Root $root)) 'Dist antigo deve ser detectado.'

    (Get-Item -LiteralPath (Join-Path $frontendDist 'index.html')).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(1)
    Assert-True (Test-CloudOsFrontendDistFresh -Root $root) 'Dist novo deve ser aceito.'

    Set-Content -LiteralPath (Join-Path $hostSource 'CloudOS.Host.csproj') -Value '<Project />'
    Set-Content -LiteralPath (Join-Path $hostSource 'BrowserManager.cs') -Value 'source'
    Set-Content -LiteralPath (Join-Path $publish 'CloudOS.Host.exe') -Value 'exe'
    Set-Content -LiteralPath (Join-Path $publish 'CloudOS.Host.dll') -Value 'dll'
    Set-Content -LiteralPath (Join-Path $publish 'Microsoft.Web.WebView2.Core.dll') -Value 'wv2'
    Set-Content -LiteralPath (Join-Path $publish 'Microsoft.Web.WebView2.Wpf.dll') -Value 'wv2'
    Get-ChildItem -LiteralPath $publish -File | ForEach-Object { $_.LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(2) }
    $fresh = Get-CloudOsPublishedHostState -Root $root
    Assert-True $fresh.Usable 'Publicação completa e nova deve ser utilizável.'

    (Get-Item -LiteralPath (Join-Path $hostSource 'BrowserManager.cs')).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(5)
    $stale = Get-CloudOsPublishedHostState -Root $root
    Assert-True ($stale.Stale -and -not $stale.Usable) 'Host publicado antigo deve ser rejeitado.'

    (Get-Item -LiteralPath (Join-Path $hostSource 'BrowserManager.cs')).LastWriteTimeUtc = [DateTime]::UtcNow
    Remove-Item -LiteralPath (Join-Path $publish 'Microsoft.Web.WebView2.Wpf.dll') -Force
    $incomplete = Get-CloudOsPublishedHostState -Root $root
    Assert-True (-not $incomplete.Complete) 'WebView2 WPF ausente deve tornar publicação incompleta.'
    Assert-True ($incomplete.Missing -contains 'Microsoft.Web.WebView2.Wpf.dll') 'Arquivo ausente deve ser reportado.'

    Write-Host 'PASS native host freshness'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

# The file timestamp freshness gate above is not enough to protect a live session.
# Also require the persisted session/runtime revision to match the active checkout.
& (Join-Path $PSScriptRoot 'test-cloudos-session-freshness.ps1')
