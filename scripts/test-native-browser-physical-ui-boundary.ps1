$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$baseSha = '56f0ca8bc0a59987a43295da1ded277afc40e6e9'
$protectedPaths = @(
    'desktop/CloudOS.Host/Browser/BrowserWindow.xaml.cs',
    'desktop/CloudOS.Host/Browser/BrowserTab.cs',
    'desktop/CloudOS.Host/Browser/BrowserPolicy.cs',
    'desktop/CloudOS.Host/Browser/BrowserSecurityPolicy.cs',
    'desktop/CloudOS.Host/Browser/BrowserPermissionController.cs',
    'desktop/CloudOS.Host/Browser/BrowserDownloadManager.cs',
    'desktop/CloudOS.Host/Browser/BrowserCredentialController.cs',
    'desktop/CloudOS.Host/Browser/BrowserOpenResult.cs',
    'desktop/CloudOS.Host/Browser/BrowserStateStore.cs',
    'desktop/CloudOS.Host/Browser/BrowserStorageLayout.cs',
    'desktop/CloudOS.Host/Browser/BrowserDiagnostics.cs',
    'desktop/CloudOS.Host/Bridge/WebMessageBridge.cs',
    'frontend/src/services/nativeHostBridge.ts',
    'frontend/src/apps/Browser/Browser.tsx'
)

$changed = @(& git diff --name-only "$baseSha...HEAD" -- $protectedPaths)
if ($LASTEXITCODE -ne 0) { throw 'BROWSER_PHYSICAL_UI_BOUNDARY_FAILED: git diff falhou.' }
if ($changed.Count -gt 0) {
    throw "BROWSER_PHYSICAL_UI_BOUNDARY_FAILED: lifecycle/bridge/security foi alterado:`n$($changed -join "`n")"
}

# BrowserManager can change only to enable WebView2 browser extensions in the same isolated Browser UDF.
$managerPath = 'desktop/CloudOS.Host/Browser/BrowserManager.cs'
$baseManager = (& git show "${baseSha}:$managerPath") -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'BROWSER_PHYSICAL_UI_BOUNDARY_FAILED: BrowserManager base indisponível.' }
$headManager = Get-Content -Raw -LiteralPath $managerPath
$extensionBlock = '(?ms)        var options = new CoreWebView2EnvironmentOptions\s*\{\s*AreBrowserExtensionsEnabled = true\s*\};\s*        var environment = await CoreWebView2Environment\.CreateAsync\(\s*browserExecutableFolder: null,\s*userDataFolder: _userDataFolder,\s*options: options\);'
$normalizedHead = [regex]::Replace($headManager, $extensionBlock, '        var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: _userDataFolder);')
$normalize = { param([string]$text) ($text -replace "`r`n", "`n").TrimEnd("`n") }
if ((& $normalize $normalizedHead) -cne (& $normalize $baseManager)) {
    throw 'BROWSER_PHYSICAL_UI_BOUNDARY_FAILED: BrowserManager mudou além da opção de extensões.'
}
if ($headManager -notmatch 'AreBrowserExtensionsEnabled\s*=\s*true') { throw 'BROWSER_PHYSICAL_UI_BOUNDARY_FAILED: extensões não habilitadas explicitamente.' }
if ($headManager -notmatch 'BROWSER_UDF_ISOLATION_FAILED') { throw 'BROWSER_PHYSICAL_UI_BOUNDARY_FAILED: isolamento UDF removido.' }

& git diff --check "$baseSha...HEAD"
if ($LASTEXITCODE -ne 0) { throw 'BROWSER_PHYSICAL_UI_BOUNDARY_FAILED: whitespace inválido.' }
Write-Host 'PASS Browser physical UI boundary: lifecycle/bridge/security intactos; BrowserManager limitado à opção de extensões.'
