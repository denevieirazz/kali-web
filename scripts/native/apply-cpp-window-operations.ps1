[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Temporary migration patcher. The Windows runner validates the production
# NativeWindowManager against the real C++ DLL before committing the manager.
# Keep this rerunnable while the physical HWND migration is being proven.
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$path = Join-Path $repoRoot 'desktop\CloudOS.Host\Native\NativeWindowManager.cs'
$content = [IO.File]::ReadAllText($path)

$requiredNativeCalls = @(
    'CloudOsNativeRuntime.TryAttachWindow(',
    'CloudOsNativeRuntime.TryLayoutWindow(',
    'CloudOsNativeRuntime.TryFocusWindow(',
    'CloudOsNativeRuntime.CanUseWindowOperations'
)

$alreadyMigrated = $true
foreach ($needle in $requiredNativeCalls) {
    if (-not $content.Contains($needle)) {
        $alreadyMigrated = $false
        break
    }
}
if ($alreadyMigrated) {
    Write-Host 'CPP_WINDOW_OPERATIONS_ALREADY_MIGRATED'
    exit 0
}

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

$updated = [IO.File]::ReadAllText($path)
foreach ($needle in $requiredNativeCalls) {
    if (-not $updated.Contains($needle)) { throw "MISSING_$needle" }
}

Write-Host 'CPP_WINDOW_OPERATIONS_PATCHED'
