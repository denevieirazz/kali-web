[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Temporary migration patcher. The Windows runner validates C++ + Host before committing production code.
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$path = Join-Path $repoRoot 'desktop\CloudOS.Host\Native\NativeWindowManager.cs'
$content = [IO.File]::ReadAllText($path)

function Replace-ExactlyOnce([string]$Old, [string]$New, [string]$Name) {
    $count = ([regex]::Matches($script:content, [regex]::Escape($Old))).Count
    if ($count -ne 1) { throw "${Name}_EXPECTED_1_FOUND_$count" }
    $script:content = $script:content.Replace($Old, $New)
}

$focusOld = @'
            else
            {
                if (!attachment.RequestedVisible)
                {
                    error = "The CloudOS Hub surface is hidden. Open the Hub before focusing this application.";
                    return false;
                }
                if (!TryRestoreResponsive(hwnd, true, out error)) return false;
                if (!TryApplyAttachedLayout(hwnd, attachment, attachment.Bounds, true, false, false, out error))
                {
                    QuarantineAfterContainmentFailure(hwnd, attachment, error);
                    return false;
                }
            }
            if (!NativeMethods.SetForegroundWindow(hwnd))
            {
                error = "Windows denied foreground activation. User interaction may be required.";
                return false;
            }

            RefreshOne(hwnd, NativeWindowChangeKind.Updated);
            error = null;
            return true;
'@
$focusNew = @'
            else
            {
                if (!attachment.RequestedVisible)
                {
                    error = "The CloudOS Hub surface is hidden. Open the Hub before focusing this application.";
                    return false;
                }

                if (CloudOsNativeRuntime.CanUseWindowOperations)
                {
                    if (!CloudOsNativeRuntime.TryFocusWindow(
                        hwnd,
                        attachment.Owner,
                        attachment.AttachedStyle,
                        attachment.AttachedExtendedStyle,
                        attachment.Bounds,
                        _options.CloseTimeoutMilliseconds,
                        out error))
                    {
                        QuarantineAfterContainmentFailure(hwnd, attachment, error);
                        return false;
                    }
                    RefreshOne(hwnd, NativeWindowChangeKind.Updated);
                    error = null;
                    return true;
                }

                if (!TryRestoreResponsive(hwnd, true, out error)) return false;
                if (!TryApplyAttachedLayout(hwnd, attachment, attachment.Bounds, true, false, false, out error))
                {
                    QuarantineAfterContainmentFailure(hwnd, attachment, error);
                    return false;
                }
            }
            if (!NativeMethods.SetForegroundWindow(hwnd))
            {
                error = "Windows denied foreground activation. User interaction may be required.";
                return false;
            }

            RefreshOne(hwnd, NativeWindowChangeKind.Updated);
            error = null;
            return true;
'@
Replace-ExactlyOnce $focusOld $focusNew 'FOCUS'

$attachNeedle = @'
            try
            {
                if (!TryForceHideWindow(hwnd, out error)) throw new InvalidOperationException(error);

                long attachedStyle = GetExpectedAttachedStyle(state);
                long attachedExtendedStyle = GetExpectedAttachedExtendedStyle(state);

                NativeMethods.SetWindowStyle(hwnd, attachedStyle);
'@
$attachReplacement = @'
            try
            {
                if (!TryForceHideWindow(hwnd, out error)) throw new InvalidOperationException(error);

                if (CloudOsNativeRuntime.CanUseWindowOperations)
                {
                    state.Bounds = bounds;
                    state.RequestedVisible = visible;
                    // Register attachment capability while hidden. A WinEvent produced by the
                    // native style/owner transition can never reclassify the HWND as escaped.
                    lock (_sync) _attachments[hwnd] = state;
                    if (!CloudOsNativeRuntime.TryAttachWindow(
                        hwnd,
                        owner,
                        bounds,
                        visible,
                        out var appliedStyle,
                        out var appliedExtendedStyle,
                        out error))
                    {
                        throw new InvalidOperationException(error);
                    }
                    state.RecordAppliedStyles(appliedStyle, appliedExtendedStyle);
                    RefreshOne(hwnd, NativeWindowChangeKind.Updated);
                    error = null;
                    return true;
                }

                long attachedStyle = GetExpectedAttachedStyle(state);
                long attachedExtendedStyle = GetExpectedAttachedExtendedStyle(state);

                NativeMethods.SetWindowStyle(hwnd, attachedStyle);
'@
Replace-ExactlyOnce $attachNeedle $attachReplacement 'ATTACH'

$layoutNeedle = @'
            if (!TryApplyAttachedLayout(hwnd, state, bounds, visible, false, true, out error))
            {
                QuarantineAfterContainmentFailure(hwnd, state, error);
                return false;
            }
            RefreshOne(hwnd, NativeWindowChangeKind.Updated);
            return true;
'@
$layoutReplacement = @'
            if (CloudOsNativeRuntime.CanUseWindowOperations)
            {
                if (!CloudOsNativeRuntime.TryLayoutWindow(
                    hwnd,
                    state.Owner,
                    state.AttachedStyle,
                    state.AttachedExtendedStyle,
                    bounds,
                    visible,
                    preserveMinimized: true,
                    out error))
                {
                    QuarantineAfterContainmentFailure(hwnd, state, error);
                    return false;
                }
                state.Bounds = bounds;
                state.RequestedVisible = visible;
                RefreshOne(hwnd, NativeWindowChangeKind.Updated);
                return true;
            }

            if (!TryApplyAttachedLayout(hwnd, state, bounds, visible, false, true, out error))
            {
                QuarantineAfterContainmentFailure(hwnd, state, error);
                return false;
            }
            RefreshOne(hwnd, NativeWindowChangeKind.Updated);
            return true;
'@
Replace-ExactlyOnce $layoutNeedle $layoutReplacement 'LAYOUT'

[IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))

$runtimePath = Join-Path $repoRoot 'desktop\CloudOS.Host\Native\CloudOsNativeRuntime.cs'
$runtime = [IO.File]::ReadAllText($runtimePath)
$oldFailure = @'
    private static Win32Exception NativeFailure(string message) =>
        new(Marshal.GetLastWin32Error(), message);
'@
$newFailure = @'
    private static Win32Exception NativeFailure(string message)
    {
        var nativeError = Marshal.GetLastWin32Error();
        var systemMessage = new Win32Exception(nativeError).Message;
        return new Win32Exception(nativeError, $"{message} Win32 error {nativeError}: {systemMessage}");
    }
'@
$failureCount = ([regex]::Matches($runtime, [regex]::Escape($oldFailure))).Count
if ($failureCount -ne 1) { throw "NATIVE_FAILURE_EXPECTED_1_FOUND_$failureCount" }
$runtime = $runtime.Replace($oldFailure, $newFailure)
[IO.File]::WriteAllText($runtimePath, $runtime, [Text.UTF8Encoding]::new($false))

$updated = [IO.File]::ReadAllText($path)
foreach ($needle in @(
    'CloudOsNativeRuntime.TryAttachWindow(',
    'CloudOsNativeRuntime.TryLayoutWindow(',
    'CloudOsNativeRuntime.TryFocusWindow(',
    'CloudOsNativeRuntime.CanUseWindowOperations'
)) {
    if (-not $updated.Contains($needle)) { throw "MISSING_$needle" }
}
if (-not ([IO.File]::ReadAllText($runtimePath)).Contains('Win32 error {nativeError}')) {
    throw 'NATIVE_ERROR_DIAGNOSTIC_MISSING'
}

Write-Host 'CPP_WINDOW_OPERATIONS_PATCHED'
