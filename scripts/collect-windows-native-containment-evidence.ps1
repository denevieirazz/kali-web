[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [int[]] $TargetProcessId,

    [ValidateSet('Attached', 'Absent')]
    [string] $ExpectedState = 'Attached',

    [ValidateRange(0, 2147483647)]
    [int] $HostProcessId = 0,

    [ValidatePattern('^[a-zA-Z0-9._-]+$')]
    [string] $ExpectedHostProcessName = 'CloudOS.Host',

    [ValidateRange(0, 32)]
    [int] $BoundsTolerancePixels = 2,

    [string] $OutputDirectory = (Join-Path (Get-Location) 'poc1-physical-evidence\windows-contained-runtime'),

    [ValidatePattern('^[a-zA-Z0-9._-]+$')]
    [string] $Prefix = 'windows-native-containment'
)

$ErrorActionPreference = 'Stop'
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$jsonPath = Join-Path $resolvedOutputDirectory "$Prefix.json"
$logPath = Join-Path $resolvedOutputDirectory "$Prefix.log"
$finalVerdict = $null

function Write-EvidenceFiles {
    param(
        [Parameter(Mandatory)] $Evidence,
        [Parameter(Mandatory)] [AllowEmptyString()] [string[]] $LogLines
    )

    [System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText(
        $jsonPath,
        (($Evidence | ConvertTo-Json -Depth 14) + [Environment]::NewLine),
        $utf8NoBom)
    [System.IO.File]::WriteAllText(
        $logPath,
        (($LogLines -join [Environment]::NewLine) + [Environment]::NewLine),
        $utf8NoBom)
}

function Format-Hwnd {
    param([IntPtr] $Handle)
    return ('0x{0:X}' -f $Handle.ToInt64())
}

try {
    $targetIds = @($TargetProcessId | Select-Object -Unique)
    if ($targetIds.Count -eq 0 -or @($targetIds | Where-Object { $_ -le 0 }).Count -gt 0) {
        throw 'TargetProcessId deve conter apenas PIDs positivos.'
    }
    if ($ExpectedState -eq 'Attached' -and $HostProcessId -le 0) {
        throw 'HostProcessId é obrigatório quando ExpectedState=Attached.'
    }
    if ($ExpectedState -eq 'Attached' -and $targetIds -contains $HostProcessId) {
        throw 'HostProcessId não pode ser um dos TargetProcessId.'
    }

    if (-not ('CloudOSNativeContainmentEvidence' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public sealed class CloudOSNativeWindowEvidence
{
    public IntPtr Handle { get; set; }
    public IntPtr Owner { get; set; }
    public IntPtr Root { get; set; }
    public IntPtr RootOwner { get; set; }
    public IntPtr Representative { get; set; }
    public uint ProcessId { get; set; }
    public uint OwnerProcessId { get; set; }
    public string ClassName { get; set; }
    public string Title { get; set; }
    public bool Visible { get; set; }
    public bool Enabled { get; set; }
    public bool Cloaked { get; set; }
    public long Style { get; set; }
    public long ExStyle { get; set; }
    public bool ToolWindow { get; set; }
    public bool AppWindow { get; set; }
    public bool AltTabCandidate { get; set; }
    public CloudOSNativeRect Rect { get; set; }
    public CloudOSNativeRect OwnerRect { get; set; }
    public bool OwnerRectAvailable { get; set; }
}

[StructLayout(LayoutKind.Sequential)]
public struct CloudOSNativeRect
{
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

public sealed class CloudOSNativeJobEvidence
{
    public int ProcessId { get; set; }
    public bool ProcessOpened { get; set; }
    public bool QuerySucceeded { get; set; }
    public bool InJob { get; set; }
    public int NativeError { get; set; }
}

public static class CloudOSNativeContainmentEvidence
{
    private const int GWL_STYLE = -16;
    private const int GWL_EXSTYLE = -20;
    private const uint GW_OWNER = 4;
    private const uint GA_ROOT = 2;
    private const uint GA_ROOTOWNER = 3;
    private const long WS_EX_TOOLWINDOW = 0x00000080L;
    private const long WS_EX_APPWINDOW = 0x00040000L;
    private const uint DWMWA_CLOAKED = 14;
    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

    [return: MarshalAs(UnmanagedType.Bool)]
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowEnabled(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassNameW(IntPtr hWnd, StringBuilder className, int count);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong32(IntPtr hWnd, int index);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int index);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hWnd, uint command);

    [DllImport("user32.dll")]
    private static extern IntPtr GetAncestor(IntPtr hWnd, uint flags);

    [DllImport("user32.dll")]
    private static extern IntPtr GetLastActivePopup(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr hWnd, out CloudOSNativeRect rect);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hWnd, uint attribute, out int value, int valueSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint desiredAccess, [MarshalAs(UnmanagedType.Bool)] bool inheritHandle, uint processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsProcessInJob(IntPtr processHandle, IntPtr jobHandle, [MarshalAs(UnmanagedType.Bool)] out bool result);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);

    private static long GetWindowLongValue(IntPtr hWnd, int index)
    {
        return IntPtr.Size == 8
            ? GetWindowLongPtr64(hWnd, index).ToInt64()
            : GetWindowLong32(hWnd, index);
    }

    public static CloudOSNativeWindowEvidence[] Enumerate(int[] targetProcessIds)
    {
        var targets = new HashSet<uint>();
        foreach (var processId in targetProcessIds) targets.Add(unchecked((uint)processId));

        var windows = new List<CloudOSNativeWindowEvidence>();
        string callbackError = null;
        EnumWindowsProc callback = delegate(IntPtr hWnd, IntPtr ignored)
        {
            try
            {
                uint processId;
                GetWindowThreadProcessId(hWnd, out processId);
                if (!targets.Contains(processId)) return true;

                var title = new StringBuilder(2048);
                var className = new StringBuilder(512);
                GetWindowTextW(hWnd, title, title.Capacity);
                GetClassNameW(hWnd, className, className.Capacity);

                long style = GetWindowLongValue(hWnd, GWL_STYLE);
                long exStyle = GetWindowLongValue(hWnd, GWL_EXSTYLE);
                IntPtr owner = GetWindow(hWnd, GW_OWNER);
                uint ownerProcessId = 0;
                if (owner != IntPtr.Zero && IsWindow(owner)) GetWindowThreadProcessId(owner, out ownerProcessId);

                IntPtr root = GetAncestor(hWnd, GA_ROOT);
                IntPtr rootOwner = GetAncestor(hWnd, GA_ROOTOWNER);
                IntPtr representative = rootOwner;
                for (int iteration = 0; iteration < 32 && representative != IntPtr.Zero; iteration++)
                {
                    IntPtr popup = GetLastActivePopup(representative);
                    if (popup == IntPtr.Zero || popup == representative) break;
                    representative = popup;
                    if (IsWindowVisible(representative)) break;
                }

                int cloakedValue;
                bool cloaked = DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, out cloakedValue, sizeof(int)) == 0
                    && cloakedValue != 0;
                bool visible = IsWindowVisible(hWnd);
                bool toolWindow = (exStyle & WS_EX_TOOLWINDOW) != 0;
                bool appWindow = (exStyle & WS_EX_APPWINDOW) != 0;
                bool altTab = visible
                    && !cloaked
                    && title.Length > 0
                    && (appWindow || !toolWindow)
                    && representative == hWnd;

                CloudOSNativeRect rect;
                if (!GetWindowRect(hWnd, out rect)) throw new Win32Exception(Marshal.GetLastWin32Error(), "GetWindowRect(target) failed.");
                CloudOSNativeRect ownerRect = default(CloudOSNativeRect);
                bool ownerRectAvailable = owner != IntPtr.Zero && IsWindow(owner) && GetWindowRect(owner, out ownerRect);

                windows.Add(new CloudOSNativeWindowEvidence {
                    Handle = hWnd,
                    Owner = owner,
                    Root = root,
                    RootOwner = rootOwner,
                    Representative = representative,
                    ProcessId = processId,
                    OwnerProcessId = ownerProcessId,
                    ClassName = className.ToString(),
                    Title = title.ToString(),
                    Visible = visible,
                    Enabled = IsWindowEnabled(hWnd),
                    Cloaked = cloaked,
                    Style = style,
                    ExStyle = exStyle,
                    ToolWindow = toolWindow,
                    AppWindow = appWindow,
                    AltTabCandidate = altTab,
                    Rect = rect,
                    OwnerRect = ownerRect,
                    OwnerRectAvailable = ownerRectAvailable
                });
            }
            catch (Exception error)
            {
                callbackError = error.ToString();
            }
            return true;
        };

        if (!EnumWindows(callback, IntPtr.Zero))
            throw new InvalidOperationException("EnumWindows failed; callback=" + (callbackError ?? "none"));
        if (callbackError != null)
            throw new InvalidOperationException("EnumWindows callback failed: " + callbackError);
        return windows.ToArray();
    }

    public static CloudOSNativeJobEvidence QueryJob(int processId)
    {
        var evidence = new CloudOSNativeJobEvidence { ProcessId = processId };
        IntPtr processHandle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, unchecked((uint)processId));
        if (processHandle == IntPtr.Zero)
        {
            evidence.NativeError = Marshal.GetLastWin32Error();
            return evidence;
        }

        evidence.ProcessOpened = true;
        try
        {
            bool inJob;
            if (!IsProcessInJob(processHandle, IntPtr.Zero, out inJob))
            {
                evidence.NativeError = Marshal.GetLastWin32Error();
                return evidence;
            }
            evidence.QuerySucceeded = true;
            evidence.InJob = inJob;
            return evidence;
        }
        finally
        {
            CloseHandle(processHandle);
        }
    }
}
'@
    }

    $processEvidence = [System.Collections.Generic.List[object]]::new()
    foreach ($processId in $targetIds) {
        $process = $null
        try { $process = Get-Process -Id $processId -ErrorAction Stop } catch {}

        if ($null -eq $process) {
            $processEvidence.Add([pscustomobject]@{
                ProcessId = $processId
                Exists = $false
                ProcessName = $null
                SessionId = $null
                StartTimeUtc = $null
                JobQuerySucceeded = $false
                InAnyJob = $false
                JobQueryNativeError = $null
            })
            continue
        }

        $job = [CloudOSNativeContainmentEvidence]::QueryJob($processId)
        $startTimeUtc = $null
        try { $startTimeUtc = $process.StartTime.ToUniversalTime().ToString('o') } catch {}
        $processEvidence.Add([pscustomobject]@{
            ProcessId = $processId
            Exists = $true
            ProcessName = $process.ProcessName
            SessionId = $process.SessionId
            StartTimeUtc = $startTimeUtc
            JobQuerySucceeded = $job.QuerySucceeded
            InAnyJob = $job.InJob
            JobQueryNativeError = if ($job.NativeError -eq 0) { $null } else { $job.NativeError }
        })
    }

    $hostEvidence = $null
    if ($HostProcessId -gt 0) {
        $host = $null
        try { $host = Get-Process -Id $HostProcessId -ErrorAction Stop } catch {}
        $hostEvidence = if ($null -eq $host) {
            [pscustomobject]@{
                ProcessId = $HostProcessId
                Exists = $false
                ProcessName = $null
                SessionId = $null
                StartTimeUtc = $null
            }
        } else {
            $hostStartTimeUtc = $null
            try { $hostStartTimeUtc = $host.StartTime.ToUniversalTime().ToString('o') } catch {}
            [pscustomobject]@{
                ProcessId = $HostProcessId
                Exists = $true
                ProcessName = $host.ProcessName
                SessionId = $host.SessionId
                StartTimeUtc = $hostStartTimeUtc
            }
        }
    }

    $nativeWindows = @([CloudOSNativeContainmentEvidence]::Enumerate([int[]]$targetIds))
    $windowEvidence = foreach ($window in $nativeWindows) {
        $width = $window.Rect.Right - $window.Rect.Left
        $height = $window.Rect.Bottom - $window.Rect.Top
        $ownerWidth = if ($window.OwnerRectAvailable) { $window.OwnerRect.Right - $window.OwnerRect.Left } else { $null }
        $ownerHeight = if ($window.OwnerRectAvailable) { $window.OwnerRect.Bottom - $window.OwnerRect.Top } else { $null }
        $withinOwner = $window.OwnerRectAvailable `
            -and $window.Rect.Left -ge ($window.OwnerRect.Left - $BoundsTolerancePixels) `
            -and $window.Rect.Top -ge ($window.OwnerRect.Top - $BoundsTolerancePixels) `
            -and $window.Rect.Right -le ($window.OwnerRect.Right + $BoundsTolerancePixels) `
            -and $window.Rect.Bottom -le ($window.OwnerRect.Bottom + $BoundsTolerancePixels)

        [pscustomobject]@{
            Handle = Format-Hwnd $window.Handle
            ProcessId = [int]$window.ProcessId
            ClassName = $window.ClassName
            Title = $window.Title
            Visible = $window.Visible
            Enabled = $window.Enabled
            Cloaked = $window.Cloaked
            OwnerHandle = Format-Hwnd $window.Owner
            OwnerProcessId = [int]$window.OwnerProcessId
            RootHandle = Format-Hwnd $window.Root
            RootOwnerHandle = Format-Hwnd $window.RootOwner
            RepresentativeHandle = Format-Hwnd $window.Representative
            TopLevelRootIsSelf = ($window.Root -eq $window.Handle)
            Style = ('0x{0:X16}' -f $window.Style)
            ExStyle = ('0x{0:X16}' -f $window.ExStyle)
            ToolWindow = $window.ToolWindow
            AppWindow = $window.AppWindow
            ForbiddenFrameStylePresent = (($window.Style -band 0x00CF0000L) -ne 0)
            AltTabCandidate = $window.AltTabCandidate
            Bounds = [ordered]@{
                Left = $window.Rect.Left
                Top = $window.Rect.Top
                Right = $window.Rect.Right
                Bottom = $window.Rect.Bottom
                Width = $width
                Height = $height
            }
            OwnerBounds = if ($window.OwnerRectAvailable) {
                [ordered]@{
                    Left = $window.OwnerRect.Left
                    Top = $window.OwnerRect.Top
                    Right = $window.OwnerRect.Right
                    Bottom = $window.OwnerRect.Bottom
                    Width = $ownerWidth
                    Height = $ownerHeight
                }
            } else { $null }
            BoundsWithinOwner = $withinOwner
        }
    }

    $visibleWindows = @($windowEvidence | Where-Object Visible)
    $assertions = [System.Collections.Generic.List[object]]::new()
    function Add-Assertion {
        param([string] $Id, [bool] $Ok, [string] $Expected, $Actual)
        $assertions.Add([pscustomobject]@{
            Id = $Id
            Ok = $Ok
            Expected = $Expected
            Actual = $Actual
        })
    }

    if ($ExpectedState -eq 'Attached') {
        $hostNameOk = $hostEvidence.Exists -and $hostEvidence.ProcessName -ieq $ExpectedHostProcessName
        $existingProcesses = @($processEvidence | Where-Object Exists)
        $sameSession = $hostEvidence.Exists -and @($existingProcesses | Where-Object { $_.SessionId -ne $hostEvidence.SessionId }).Count -eq 0
        $jobFailures = @($existingProcesses | Where-Object { -not $_.JobQuerySucceeded -or -not $_.InAnyJob })
        $ownerFailures = @($visibleWindows | Where-Object { $_.OwnerProcessId -ne $HostProcessId })
        $topLevelFailures = @($visibleWindows | Where-Object { -not $_.TopLevelRootIsSelf })
        $toolFailures = @($visibleWindows | Where-Object { -not $_.ToolWindow })
        $appWindowFailures = @($visibleWindows | Where-Object AppWindow)
        $frameFailures = @($visibleWindows | Where-Object ForbiddenFrameStylePresent)
        $altTabFailures = @($windowEvidence | Where-Object AltTabCandidate)
        $boundsFailures = @($visibleWindows | Where-Object { -not $_.BoundsWithinOwner })

        Add-Assertion 'host.exists' $hostEvidence.Exists 'CloudOS Host process exists' $hostEvidence.Exists
        Add-Assertion 'host.identity' $hostNameOk "host process name equals $ExpectedHostProcessName" $hostEvidence.ProcessName
        Add-Assertion 'process.target-exists-all' ($existingProcesses.Count -eq $targetIds.Count) 'all target PIDs exist' $existingProcesses.Count
        Add-Assertion 'process.same-session-all' $sameSession 'all target PIDs share the CloudOS Host Windows session' (@($existingProcesses | Select-Object ProcessId, SessionId))
        Add-Assertion 'job.membership-all' ($jobFailures.Count -eq 0 -and $existingProcesses.Count -eq $targetIds.Count) 'every target PID is assigned to a Windows Job' (@($jobFailures | Select-Object ProcessId, JobQuerySucceeded, InAnyJob, JobQueryNativeError))
        Add-Assertion 'hwnd.target-present' ($windowEvidence.Count -gt 0) 'at least one target top-level HWND exists' $windowEvidence.Count
        Add-Assertion 'hwnd.visible-present' ($visibleWindows.Count -gt 0) 'at least one target HWND is visible for the physical open-stage proof' $visibleWindows.Count
        Add-Assertion 'hwnd.owner-cloudos-all' ($visibleWindows.Count -gt 0 -and $ownerFailures.Count -eq 0) 'every visible target HWND is directly owned by the CloudOS Host PID' (@($ownerFailures | Select-Object Handle, ProcessId, OwnerHandle, OwnerProcessId))
        Add-Assertion 'hwnd.top-level-root-all' ($visibleWindows.Count -gt 0 -and $topLevelFailures.Count -eq 0) 'anchored-overlay windows remain real top-level HWNDs by design' (@($topLevelFailures | Select-Object Handle, RootHandle))
        Add-Assertion 'style.toolwindow-all' ($visibleWindows.Count -gt 0 -and $toolFailures.Count -eq 0) 'WS_EX_TOOLWINDOW is set on every visible target HWND' (@($toolFailures | Select-Object Handle, ExStyle))
        Add-Assertion 'style.appwindow-zero' ($appWindowFailures.Count -eq 0) 'WS_EX_APPWINDOW is absent from every visible target HWND' (@($appWindowFailures | Select-Object Handle, ExStyle))
        Add-Assertion 'style.external-frame-zero' ($frameFailures.Count -eq 0) 'caption/thickframe/min/max/sysmenu bits are absent from every visible target HWND' (@($frameFailures | Select-Object Handle, Style))
        Add-Assertion 'alttab.target-zero' ($altTabFailures.Count -eq 0) 'zero target Alt+Tab candidates' (@($altTabFailures | Select-Object Handle, ProcessId, Title))
        Add-Assertion 'bounds.within-cloudos-owner-all' ($visibleWindows.Count -gt 0 -and $boundsFailures.Count -eq 0) "every visible target HWND remains within the CloudOS owner bounds (+/- $BoundsTolerancePixels px)" (@($boundsFailures | Select-Object Handle, Bounds, OwnerBounds))
    }
    else {
        $existingProcesses = @($processEvidence | Where-Object Exists)
        Add-Assertion 'process.target-absent-all' ($existingProcesses.Count -eq 0) 'all previously captured target PIDs have exited' (@($existingProcesses | Select-Object ProcessId, ProcessName, StartTimeUtc))
        Add-Assertion 'hwnd.target-zero' ($windowEvidence.Count -eq 0) 'zero top-level HWNDs remain for the previously captured target PIDs' $windowEvidence.Count
    }

    $failedAssertions = @($assertions | Where-Object { -not $_.Ok })
    $verdict = if ($failedAssertions.Count -eq 0) { 'PASS' } else { 'FAIL' }
    $evidence = [ordered]@{
        SchemaVersion = 1
        CollectedAt = [DateTimeOffset]::UtcNow.ToString('o')
        Collector = 'scripts/collect-windows-native-containment-evidence.ps1'
        FailClosed = $true
        ExpectedState = $ExpectedState
        Verdict = $verdict
        TargetProcessIds = $targetIds
        HostProcessId = if ($HostProcessId -gt 0) { $HostProcessId } else { $null }
        ExpectedHostProcessName = if ($ExpectedState -eq 'Attached') { $ExpectedHostProcessName } else { $null }
        BoundsTolerancePixels = $BoundsTolerancePixels
        Host = $hostEvidence
        Processes = @($processEvidence)
        Windows = @($windowEvidence)
        Counts = [ordered]@{
            TargetProcessesRequested = $targetIds.Count
            TargetProcessesExisting = @($processEvidence | Where-Object Exists).Count
            TargetTopLevelWindows = $windowEvidence.Count
            TargetVisibleWindows = $visibleWindows.Count
            TargetAltTabCandidates = @($windowEvidence | Where-Object AltTabCandidate).Count
        }
        Assertions = @($assertions)
        Limitations = @(
            'IsProcessInJob proves that a target PID belongs to a Windows Job, but public Win32 APIs used here do not identify that Job as the exact private CloudOS Job. Exact Job membership and descendant synchronization are enforced by the in-process NativeContainedProcessLease/NativeContainedJobTracker.',
            'BoundsWithinOwner proves the native HWND is geometrically inside the CloudOS owner window. The stricter WebView surface bounds are enforced in-process by WebMessageBridge.ConvertBounds and NativeWindowManager layout validation.',
            'Programmatic AltTabCandidate classification is evidence, not a replacement for the mandatory physical Alt+Tab observation and screenshot/video of the CloudOS surface.'
        )
    }

    $logLines = [System.Collections.Generic.List[string]]::new()
    $logLines.Add("CLOUDOS WINDOWS NATIVE CONTAINMENT: $verdict")
    $logLines.Add("expectedState=$ExpectedState")
    $logLines.Add("collectedAt=$($evidence.CollectedAt)")
    $logLines.Add("targetPids=$($targetIds -join ',') hostPid=$HostProcessId")
    $logLines.Add("targetHwnd=$($evidence.Counts.TargetTopLevelWindows) visible=$($evidence.Counts.TargetVisibleWindows) altTab=$($evidence.Counts.TargetAltTabCandidates)")
    $logLines.Add('')
    $logLines.Add('ASSERTIONS')
    foreach ($assertion in $assertions) {
        $status = if ($assertion.Ok) { 'PASS' } else { 'FAIL' }
        $actual = if ($null -eq $assertion.Actual) { '<null>' } else { ($assertion.Actual | ConvertTo-Json -Compress -Depth 8) }
        $logLines.Add("[$status] $($assertion.Id) expected=$($assertion.Expected) actual=$actual")
    }
    $logLines.Add('')
    $logLines.Add('LIMITATIONS')
    foreach ($limitation in $evidence.Limitations) { $logLines.Add("- $limitation") }

    Write-EvidenceFiles -Evidence $evidence -LogLines $logLines
    $finalVerdict = $verdict

    Write-Host "CLOUDOS WINDOWS NATIVE CONTAINMENT: $verdict"
    Write-Host "JSON: $jsonPath"
    Write-Host "LOG:  $logPath"
}
catch {
    $errorEvidence = [ordered]@{
        SchemaVersion = 1
        CollectedAt = [DateTimeOffset]::UtcNow.ToString('o')
        Collector = 'scripts/collect-windows-native-containment-evidence.ps1'
        FailClosed = $true
        ExpectedState = $ExpectedState
        Verdict = 'ERROR'
        TargetProcessIds = @($TargetProcessId)
        HostProcessId = if ($HostProcessId -gt 0) { $HostProcessId } else { $null }
        Error = $_.Exception.Message
        ErrorType = $_.Exception.GetType().FullName
    }
    try {
        Write-EvidenceFiles -Evidence $errorEvidence -LogLines @(
            'CLOUDOS WINDOWS NATIVE CONTAINMENT: ERROR',
            "collectedAt=$($errorEvidence.CollectedAt)",
            "type=$($errorEvidence.ErrorType)",
            "error=$($errorEvidence.Error)"
        )
    } catch {}
    throw
}

if ($finalVerdict -ne 'PASS') {
    throw "Windows native containment physical evidence failed. See $jsonPath"
}
