[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Temporary migration patcher. The Windows runner validates both the production
# NativeWindowManager and the C++ HWND implementation before committing either.
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$managerPath = Join-Path $repoRoot 'desktop\CloudOS.Host\Native\NativeWindowManager.cs'
$cppPath = Join-Path $repoRoot 'desktop\CloudOS.NativeRuntime\src\cloudos_native_runtime.cpp'
$manager = [IO.File]::ReadAllText($managerPath)
$cpp = [IO.File]::ReadAllText($cppPath)

function Replace-ExactlyOnce([ref]$Text, [string]$Old, [string]$New, [string]$Name) {
    $count = ([regex]::Matches($Text.Value, [regex]::Escape($Old))).Count
    if ($count -ne 1) { throw "${Name}_EXPECTED_1_FOUND_$count" }
    $Text.Value = $Text.Value.Replace($Old, $New)
}

$requiredNativeCalls = @(
    'CloudOsNativeRuntime.TryAttachWindow(',
    'CloudOsNativeRuntime.TryLayoutWindow(',
    'CloudOsNativeRuntime.TryFocusWindow(',
    'CloudOsNativeRuntime.CanUseWindowOperations'
)

$managerMigrated = $true
foreach ($needle in $requiredNativeCalls) {
    if (-not $manager.Contains($needle)) {
        $managerMigrated = $false
        break
    }
}

if (-not $managerMigrated) {
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
    Replace-ExactlyOnce ([ref]$manager) $focusOld $focusNew 'FOCUS'

    $attachOld = @'
            try
            {
                if (!TryForceHideWindow(hwnd, out error)) throw new InvalidOperationException(error);

                long attachedStyle = GetExpectedAttachedStyle(state);
                long attachedExtendedStyle = GetExpectedAttachedExtendedStyle(state);

                NativeMethods.SetWindowStyle(hwnd, attachedStyle);
'@
    $attachNew = @'
            try
            {
                if (!TryForceHideWindow(hwnd, out error)) throw new InvalidOperationException(error);

                if (CloudOsNativeRuntime.CanUseWindowOperations)
                {
                    state.Bounds = bounds;
                    state.RequestedVisible = visible;
                    // Register the capability while the HWND is still hidden. WinEvents raised
                    // by the native owner/style transition cannot reclassify it as escaped.
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
    Replace-ExactlyOnce ([ref]$manager) $attachOld $attachNew 'ATTACH'

    $layoutOld = @'
            if (!TryApplyAttachedLayout(hwnd, state, bounds, visible, false, true, out error))
            {
                QuarantineAfterContainmentFailure(hwnd, state, error);
                return false;
            }
            RefreshOne(hwnd, NativeWindowChangeKind.Updated);
            return true;
'@
    $layoutNew = @'
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
    Replace-ExactlyOnce ([ref]$manager) $layoutOld $layoutNew 'LAYOUT'
    [IO.File]::WriteAllText($managerPath, $manager, [Text.UTF8Encoding]::new($false))
}

$normalizationMarker = 'frame_changed ? current_style_after_frame'
$cppMigrated = $cpp.Contains($normalizationMarker)
if (-not $cppMigrated) {
    $validationOld = @'
    return validate_window_surface(
        window,
        owner,
        expected_style,
        expected_extended_style,
        x,
        y,
        width,
        height,
        visible);
'@
    $validationNew = @'
    const LONG_PTR current_style_after_frame = GetWindowLongPtrW(window, GWL_STYLE);
    const LONG_PTR current_extended_style_after_frame = GetWindowLongPtrW(window, GWL_EXSTYLE);

    // SWP_FRAMECHANGED is allowed to normalize otherwise harmless style bits. On the
    // initial attach validate containment invariants and let the caller persist the
    // actual post-frame styles. Subsequent layout/focus calls require exact equality.
    if (frame_changed) {
        if (GetWindow(window, GW_OWNER) != owner) return fail(ERROR_INVALID_STATE);
        if ((current_style_after_frame & kForbiddenFrameStyles) != 0) return fail(ERROR_INVALID_STATE);
        if ((current_extended_style_after_frame & WS_EX_APPWINDOW) != 0
            || (current_extended_style_after_frame & WS_EX_TOOLWINDOW) == 0) {
            return fail(ERROR_INVALID_STATE);
        }
        if (!IsIconic(window)) {
            RECT actual{};
            if (!GetWindowRect(window, &actual)) return FALSE;
            if (actual.left < x - kBoundsTolerance || actual.top < y - kBoundsTolerance
                || actual.right > x + width + kBoundsTolerance
                || actual.bottom > y + height + kBoundsTolerance) {
                return fail(ERROR_INVALID_STATE);
            }
            if ((IsWindowVisible(window) ? TRUE : FALSE) != visible) {
                return fail(ERROR_INVALID_STATE);
            }
        }
        SetLastError(ERROR_SUCCESS);
        return TRUE;
    }

    // marker: frame_changed ? current_style_after_frame
    return validate_window_surface(
        window,
        owner,
        expected_style,
        expected_extended_style,
        x,
        y,
        width,
        height,
        visible);
'@
    Replace-ExactlyOnce ([ref]$cpp) $validationOld $validationNew 'CPP_FRAME_NORMALIZATION'
    [IO.File]::WriteAllText($cppPath, $cpp, [Text.UTF8Encoding]::new($false))
}

$managerAfter = [IO.File]::ReadAllText($managerPath)
foreach ($needle in $requiredNativeCalls) {
    if (-not $managerAfter.Contains($needle)) { throw "MISSING_$needle" }
}
$cppAfter = [IO.File]::ReadAllText($cppPath)
if (-not $cppAfter.Contains($normalizationMarker)) {
    throw 'CPP_FRAME_NORMALIZATION_MISSING'
}

Write-Host "CPP_WINDOW_OPERATIONS_PATCHED managerChanged=$(-not $managerMigrated) cppChanged=$(-not $cppMigrated)"
