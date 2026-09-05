[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Assert-FileContains {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string[]]$Needles,
        [string]$Description = ''
    )

    $fullPath = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "File missing for contract ($Description): $RelativePath"
    }

    $content = Get-Content -LiteralPath $fullPath -Raw
    foreach ($needle in $Needles) {
        if (-not $content.Contains($needle)) {
            throw "Contract check failed in $RelativePath ($Description). Expected to contain: '$needle'"
        }
    }
}

# 1. Clipboard Service V26
Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\clipboard_service_v26.h' -Needles @(
    'struct ClipboardItemV26',
    'class ClipboardServiceV26',
    'GetHistory(',
    'GetCurrentText()',
    'SetText(',
    'Clear(',
    'kMaxHistoryItems'
) -Description 'Clipboard Service V26 Header'

Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\clipboard_service_v26.cpp' -Needles @(
    'AddClipboardFormatListener',
    'RemoveClipboardFormatListener',
    'WM_CLIPBOARDUPDATE',
    'CF_UNICODETEXT',
    'CF_HDROP',
    'CF_DIB',
    'OpenClipboard',
    'EmptyClipboard',
    'clipboard.changed'
) -Description 'Clipboard Service V26 Implementation'

# 2. Open With Service V26
Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\open_with_service_v26.h' -Needles @(
    'struct FileAssociationV26',
    'class OpenWithServiceV26',
    'GetAssociations()',
    'GetDefaultApp(',
    'OpenFile(',
    'ShowOpenWithDialog('
) -Description 'Open With Service V26 Header'

Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\open_with_service_v26.cpp' -Needles @(
    'windows:notepad',
    'cloudos:browser',
    'cloudos:terminal',
    'ShellExecuteExW',
    'openas',
    'SEE_MASK_INVOKEIDLIST'
) -Description 'Open With Service V26 Implementation'

# 3. Notification Service V26
Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\notification_service_v26.h' -Needles @(
    'struct NotificationItemV26',
    'class NotificationServiceV26',
    'Post(',
    'GetNotifications()',
    'GetUnreadCount()',
    'Dismiss(',
    'Clear()',
    'MarkRead(',
    'MarkAllRead()'
) -Description 'Notification Service V26 Header'

Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\notification_service_v26.cpp' -Needles @(
    'notification.posted',
    'notification.dismissed',
    'notification.cleared'
) -Description 'Notification Service V26 Implementation'

# 4. Broker Server V21 Endpoints
Assert-FileContains -RelativePath 'desktop\CloudOS.SystemBroker\src\broker_server_v21.cpp' -Needles @(
    'if (method == "clipboard.getHistory")',
    'if (method == "clipboard.getText")',
    'if (method == "clipboard.setText")',
    'if (method == "clipboard.clear")',
    'if (method == "files.openWith")',
    'if (method == "files.getAssociations")',
    'if (method == "files.showOpenWithDialog")',
    'if (method == "notifications.post")',
    'if (method == "notifications.list")',
    'if (method == "notifications.dismiss")',
    'if (method == "notifications.clear")',
    'if (method == "notifications.markRead")',
    'if (method == "notifications.markAllRead")',
    'if (method == "system.lock")'
) -Description 'Broker Server V21 Desktop Services Endpoints'

# 5. Inviolable Security Rules
$prohibitedPatterns = @(
    'Winlogon',
    'explorer.exe /f',
    'taskkill /f /im explorer.exe',
    'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon',
    'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
)
foreach ($rel in @(
    'desktop\CloudOS.SystemBroker\src\clipboard_service_v26.cpp',
    'desktop\CloudOS.SystemBroker\src\open_with_service_v26.cpp',
    'desktop\CloudOS.SystemBroker\src\notification_service_v26.cpp'
)) {
    $code = Get-Content -LiteralPath (Join-Path $root $rel) -Raw
    foreach ($bad in $prohibitedPatterns) {
        if ($code.Contains($bad)) {
            throw "Security violation in ${rel}: contains prohibited pattern '$bad'"
        }
    }
}

Write-Host '[PASS] Desktop Services V26: Clipboard listener, Open With associations, Notification store and Desktop Actions verified.'
