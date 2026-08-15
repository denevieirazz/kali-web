$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$baseSha = 'f83a765061eb69df2f88a162c44ef0ec7dc60b90'
$protectedPaths = @(
    'desktop/CloudOS.Host/Browser/BrowserWindow.xaml.cs',
    'desktop/CloudOS.Host/Browser/BrowserManager.cs',
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
if ($LASTEXITCODE -ne 0) {
    throw 'BROWSER_VISUAL_BOUNDARY_FAILED: git diff não pôde validar a fronteira visual.'
}
if ($changed.Count -gt 0) {
    throw "BROWSER_VISUAL_BOUNDARY_FAILED: a branch visual alterou arquivos protegidos:`n$($changed -join "`n")"
}

& git diff --check "$baseSha...HEAD"
if ($LASTEXITCODE -ne 0) {
    throw 'BROWSER_VISUAL_BOUNDARY_FAILED: git diff --check encontrou problemas.'
}

Write-Host 'PASS native Browser visual isolation boundary'
