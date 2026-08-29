[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Read-Utf8([string]$Path) { [IO.File]::ReadAllText($Path) }
function Write-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false)) }
function Replace-Between([string]$Text, [string]$Start, [string]$End, [string]$Replacement, [string]$Name) {
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { throw "${Name}_START_NOT_FOUND" }
    $endIndex = $Text.IndexOf($End, $startIndex + $Start.Length, [StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw "${Name}_END_NOT_FOUND" }
    return $Text.Substring(0, $startIndex) + $Replacement + $Text.Substring($endIndex)
}

$path = Join-Path $repoRoot 'desktop\CloudOS.Host\Native\NativeWindowManager.cs'
$manager = Read-Utf8 $path

# The manager is already clean on reruns.
if (-not $manager.Contains('_capturedSources') -and -not $manager.Contains('CapturedSourceState')) {
    Write-Host 'NATIVE_WINDOW_MANAGER_CAPTURE_ALREADY_REMOVED'
    exit 0
}

$manager = [regex]::Replace(
    $manager,
    '(?m)^\s*private readonly Dictionary<IntPtr, CapturedSourceState> _capturedSources = new Dictionary<IntPtr, CapturedSourceState>\(\);\r?\n',
    '')
$manager = [regex]::Replace($manager, '(?m)^\s*_capturedSources\.Clear\(\);\r?\n', '')
$manager = [regex]::Replace($manager, '(?m)^\s*_capturedSources\.Remove\(hwnd\);\r?\n', '')

# Public capture-source API is dead now that the Host bridge has one native renderer.
$manager = Replace-Between \
    $manager \
    '        public bool TryPrepareCapturedSource(' \
    '        public bool TryUpdateAttachedLayout(' \
    '        public bool TryUpdateAttachedLayout(' \
    'CAPTURE_PUBLIC_API'

# Remove capture-specific private layout/validation/failure machinery.
$manager = Replace-Between \
    $manager \
    '        private bool TryApplyCapturedSourceLayout(' \
    '        private bool TryApplyAttachedLayout(' \
    '        private bool TryApplyAttachedLayout(' \
    'CAPTURE_PRIVATE_API'

# Snapshot logic now has only two states: attached HWND or hidden quarantine.
$snapshotReplacement = @'
        private bool TryCreateSnapshot(IntPtr hwnd, out NativeWindowSnapshot snapshot)
        {
            snapshot = null;
            if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return false;
            if (NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT) != hwnd) return false;

            uint ownerPid;
            NativeMethods.GetWindowThreadProcessId(hwnd, out ownerPid);
            if (ownerPid == 0 || ownerPid == (uint)_hostProcessId) return false;

            TrackedProcess registration;
            AttachedWindowState attachment;
            bool isAttached;
            bool requiresContainment;
            int processId = unchecked((int)ownerPid);
            lock (_sync)
            {
                if (!_processes.TryGetValue(processId, out registration)) return false;
                isAttached = _attachments.TryGetValue(hwnd, out attachment);
                requiresContainment = _containedProcesses.Contains(processId);
            }

            if (!IsSameProcessInstance(registration))
            {
                UntrackInvalidProcess(processId);
                return false;
            }

            // Polling and every WinEvent revalidate the native containment invariant. If an app
            // restores owner/frame/task-switcher style/visibility or leaves its CloudOS bounds,
            // hide it immediately and let the bridge terminate the entire Job.
            if (isAttached && !TryValidateAttachedContainment(hwnd, attachment, out string attachedError))
            {
                RecordAttachedContainmentFailure(hwnd, attachment, attachedError);
                return false;
            }

            if (!isAttached && requiresContainment)
            {
                string quarantineError;
                if (!TryForceHideWindow(hwnd, out quarantineError))
                {
                    lock (_sync) _containmentFailures[processId] = quarantineError;
                    return false;
                }
                lock (_sync)
                {
                    if (!_quarantinedWindows.ContainsKey(hwnd)
                        && _quarantinedWindows.Count >= _options.MaxTotalWindows)
                    {
                        _containmentFailures[processId] = "The native quarantine window limit was exceeded.";
                        return false;
                    }
                    _quarantinedWindows[hwnd] = processId;
                }
            }
            else if (!isAttached && !NativeMethods.IsWindowVisible(hwnd))
            {
                return false;
            }

            long extendedStyle = NativeMethods.GetWindowExtendedStyle(hwnd);
            bool isAppWindow = (extendedStyle & NativeMethods.WS_EX_APPWINDOW) != 0;
            bool isToolWindow = (extendedStyle & NativeMethods.WS_EX_TOOLWINDOW) != 0;
            if (!isAttached && isToolWindow && !isAppWindow) return false;
            if (!isAttached && NativeMethods.GetWindow(hwnd, NativeMethods.GW_OWNER) != IntPtr.Zero && !isAppWindow) return false;
            if (!isAttached && NativeMethods.IsWindowCloaked(hwnd)) return false;

            NativeMethods.RECT rect;
            if (!NativeMethods.GetWindowRect(hwnd, out rect)) return false;
            if (rect.Right <= rect.Left || rect.Bottom <= rect.Top) return false;

            snapshot = new NativeWindowSnapshot(
                hwnd.ToInt64(),
                processId,
                NativeMethods.GetWindowTitle(hwnd, _options.MaxTitleLength),
                NativeMethods.IsWindowVisible(hwnd),
                NativeMethods.IsIconic(hwnd),
                NativeMethods.IsZoomed(hwnd),
                isAttached,
                new NativeWindowBounds(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top),
                DateTimeOffset.UtcNow);
            return true;
        }

'@
$manager = Replace-Between $manager '        private bool TryCreateSnapshot(IntPtr hwnd, out NativeWindowSnapshot snapshot)' '        private void HookThreadMain()' $snapshotReplacement 'SNAPSHOT'

# ForceHideWindowsForProcess no longer scans a capture state table.
$forceHideReplacement = @'
        private void ForceHideWindowsForProcess(int processId)
        {
            HashSet<IntPtr> handles = new HashSet<IntPtr>();
            lock (_sync)
            {
                foreach (KeyValuePair<IntPtr, NativeWindowSnapshot> window in _windows)
                {
                    if (window.Value.ProcessId == processId) handles.Add(window.Key);
                }
                foreach (KeyValuePair<IntPtr, int> window in _quarantinedWindows)
                {
                    if (window.Value == processId) handles.Add(window.Key);
                }
            }
            foreach (IntPtr hwnd in handles) TryForceHideWindow(hwnd, out _);
        }

'@
$manager = Replace-Between $manager '        private void ForceHideWindowsForProcess(int processId)' '        private bool TryAuthorizeOperation(long windowHandle, out IntPtr hwnd, out string error)' $forceHideReplacement 'FORCE_HIDE'

# Process cleanup removes windows/attachments/quarantine only.
$removeWindowsReplacement = @'
        private void RemoveWindowsForProcessLocked(int processId, IList<NativeWindowChangedEventArgs> changes)
        {
            List<IntPtr> handles = new List<IntPtr>();
            foreach (KeyValuePair<IntPtr, NativeWindowSnapshot> item in _windows)
            {
                if (item.Value.ProcessId == processId) handles.Add(item.Key);
            }

            foreach (IntPtr hwnd in handles)
            {
                NativeWindowSnapshot snapshot = _windows[hwnd];
                _windows.Remove(hwnd);
                _attachments.Remove(hwnd);
                _quarantinedWindows.Remove(hwnd);
                changes.Add(new NativeWindowChangedEventArgs(NativeWindowChangeKind.Removed, snapshot));
            }

            List<IntPtr> quarantined = new List<IntPtr>();
            foreach (KeyValuePair<IntPtr, int> item in _quarantinedWindows)
            {
                if (item.Value == processId) quarantined.Add(item.Key);
            }
            foreach (IntPtr hwnd in quarantined) _quarantinedWindows.Remove(hwnd);
        }

'@
$manager = Replace-Between $manager '        private void RemoveWindowsForProcessLocked(int processId, IList<NativeWindowChangedEventArgs> changes)' '        private int CountWindowsForProcessLocked(int processId)' $removeWindowsReplacement 'REMOVE_WINDOWS'

# Remove capture state class while preserving the NativeWindowManager closing brace.
$classStart = $manager.IndexOf('        private sealed class CapturedSourceState', [StringComparison]::Ordinal)
if ($classStart -ge 0) {
    $nextType = $manager.IndexOf('    public sealed class NativeWindowManagerOptions', $classStart, [StringComparison]::Ordinal)
    if ($nextType -lt 0) { throw 'CAPTURE_STATE_NEXT_TYPE_NOT_FOUND' }
    $manager = $manager.Substring(0, $classStart) + "    }`r`n`r`n" + $manager.Substring($nextType)
}

# Remove any capture summary comment orphaned by method deletion.
$manager = [regex]::Replace(
    $manager,
    '(?ms)^\s*/// <summary>\r?\n\s*/// Transitions a quarantined HWND.*?/// </summary>\r?\n(?=\s*public bool TryUpdateAttachedLayout)',
    '')

foreach ($forbidden in @('_capturedSources', 'CapturedSourceState', 'TryPrepareCapturedSource', 'TryActivateCapturedSource', 'TryUpdateCapturedSourceLayout', 'CancelCapturedSource', 'TryApplyCapturedSourceLayout', 'TryValidateCapturedSourceContainment', 'RecordCapturedContainmentFailure')) {
    if ($manager.Contains($forbidden)) { throw "NATIVE_MANAGER_CAPTURE_REMAINS_$forbidden" }
}
Write-Utf8 $path $manager

# Delete capture-only fixture helpers from Host tests if they are no longer referenced.
$testPath = Join-Path $repoRoot 'desktop\CloudOS.Host.Tests\Program.cs'
$test = Read-Utf8 $testPath
if ($test.Contains('internal static IntPtr CreateVisiblePresenter(')) {
    $test = Replace-Between $test '    internal static IntPtr CreateVisiblePresenter(' '    internal static void Destroy(IntPtr hwnd)' '' 'TEST_PRESENTER_HELPER'
}
# CreateVisibleOwner was only used to anchor the capture presenter.
if ($test.Contains('internal static IntPtr CreateVisibleOwner(')) {
    $test = Replace-Between $test '    internal static IntPtr CreateVisibleOwner()' '    internal static IntPtr CreateVisiblePresenter(' '' 'TEST_VISIBLE_OWNER'
}
Write-Utf8 $testPath $test

Write-Host 'NATIVE_WINDOW_MANAGER_CAPTURE_DEAD_CODE_REMOVED'
