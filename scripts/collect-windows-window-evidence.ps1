[CmdletBinding()]
param(
    [ValidateSet('Baseline', 'During', 'After')]
    [string] $Phase = 'Baseline',

    [ValidatePattern('^[a-zA-Z0-9._+-]+$')]
    [string[]] $TargetMarkers = @('l3afpad', 'firefox'),

    [string] $BaselineJson,

    [string] $OutputDirectory = (Join-Path (Get-Location) 'poc1-physical-evidence\automatic-app-integration'),

    [ValidatePattern('^[a-zA-Z0-9._-]+$')]
    [string] $Prefix
)

$ErrorActionPreference = 'Stop'
$phaseLower = $Phase.ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($Prefix)) {
    $Prefix = "windows-hwnd-$phaseLower"
}
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$jsonPath = Join-Path $resolvedOutputDirectory "$Prefix.json"
$logPath = Join-Path $resolvedOutputDirectory "$Prefix.log"

function Write-EvidenceFiles {
    param(
        [Parameter(Mandatory)] $Evidence,
        [Parameter(Mandatory)] [AllowEmptyString()] [string[]] $LogLines
    )
    [System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($jsonPath, (($Evidence | ConvertTo-Json -Depth 12) + [Environment]::NewLine), $utf8NoBom)
    [System.IO.File]::WriteAllText($logPath, (($LogLines -join [Environment]::NewLine) + [Environment]::NewLine), $utf8NoBom)
}

try {
    if ($Phase -eq 'During' -and [string]::IsNullOrWhiteSpace($BaselineJson)) {
        throw 'BaselineJson é obrigatório na fase During.'
    }
    if ($BaselineJson -and -not (Test-Path -LiteralPath $BaselineJson -PathType Leaf)) {
        throw "BaselineJson não encontrado: $BaselineJson"
    }

    if (-not ('CloudOSWindowEvidenceNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public sealed class CloudOSWindowInfo
{
    public IntPtr Handle { get; set; }
    public IntPtr Owner { get; set; }
    public IntPtr RootOwner { get; set; }
    public IntPtr Representative { get; set; }
    public uint ProcessId { get; set; }
    public string ClassName { get; set; }
    public string Title { get; set; }
    public bool Visible { get; set; }
    public bool Enabled { get; set; }
    public bool Cloaked { get; set; }
    public uint ExStyle { get; set; }
    public bool ToolWindow { get; set; }
    public bool AppWindow { get; set; }
    public bool AltTabCandidate { get; set; }
}

public static class CloudOSWindowEvidenceNative
{
    [return: MarshalAs(UnmanagedType.Bool)]
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsWindowEnabled(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassNameW(IntPtr hWnd, StringBuilder className, int count);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    public static extern int GetWindowLong(IntPtr hWnd, int index);

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(IntPtr hWnd, uint command);

    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr hWnd, uint flags);

    [DllImport("user32.dll")]
    public static extern IntPtr GetLastActivePopup(IntPtr hWnd);

    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hWnd, uint attribute, out int value, int valueSize);

    public static CloudOSWindowInfo[] Enumerate()
    {
        const int GWL_EXSTYLE = -20;
        const uint GW_OWNER = 4;
        const uint GA_ROOTOWNER = 3;
        const uint WS_EX_TOOLWINDOW = 0x00000080;
        const uint WS_EX_APPWINDOW = 0x00040000;
        const uint DWMWA_CLOAKED = 14;
        var windows = new List<CloudOSWindowInfo>();
        string callbackError = null;
        EnumWindowsProc callback = delegate(IntPtr hWnd, IntPtr ignored)
        {
            try
            {
                uint processId;
                GetWindowThreadProcessId(hWnd, out processId);
                var title = new StringBuilder(2048);
                var className = new StringBuilder(512);
                GetWindowTextW(hWnd, title, title.Capacity);
                GetClassNameW(hWnd, className, className.Capacity);
                uint exStyle = unchecked((uint)GetWindowLong(hWnd, GWL_EXSTYLE));
                IntPtr rootOwner = GetAncestor(hWnd, GA_ROOTOWNER);
                IntPtr representative = rootOwner;
                for (int iteration = 0; iteration < 32; iteration++)
                {
                    IntPtr popup = GetLastActivePopup(representative);
                    if (popup == IntPtr.Zero || popup == representative) break;
                    representative = popup;
                    if (IsWindowVisible(representative)) break;
                }
                int cloakedValue;
                bool cloaked = DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, out cloakedValue, sizeof(int)) == 0 && cloakedValue != 0;
                bool visible = IsWindowVisible(hWnd);
                bool toolWindow = (exStyle & WS_EX_TOOLWINDOW) != 0;
                bool appWindow = (exStyle & WS_EX_APPWINDOW) != 0;
                bool altTab = visible && !cloaked && title.Length > 0 && (appWindow || !toolWindow) && representative == hWnd;
                windows.Add(new CloudOSWindowInfo {
                    Handle = hWnd,
                    Owner = GetWindow(hWnd, GW_OWNER),
                    RootOwner = rootOwner,
                    Representative = representative,
                    ProcessId = processId,
                    ClassName = className.ToString(),
                    Title = title.ToString(),
                    Visible = visible,
                    Enabled = IsWindowEnabled(hWnd),
                    Cloaked = cloaked,
                    ExStyle = exStyle,
                    ToolWindow = toolWindow,
                    AppWindow = appWindow,
                    AltTabCandidate = altTab,
                });
            }
            catch (Exception error)
            {
                callbackError = error.ToString();
            }
            return true;
        };
        if (!EnumWindows(callback, IntPtr.Zero)) throw new InvalidOperationException("EnumWindows failed; callback=" + (callbackError ?? "none"));
        if (callbackError != null) throw new InvalidOperationException("EnumWindows callback failed: " + callbackError);
        return windows.ToArray();
    }
}
'@
    }

    $rawWindows = [System.Collections.Generic.List[object]]::new()
    foreach ($nativeWindow in [CloudOSWindowEvidenceNative]::Enumerate()) {
        $processName = '<exited>'
        try {
            $processName = (Get-Process -Id ([int] $nativeWindow.ProcessId) -ErrorAction Stop).ProcessName
        } catch {}
        $rawWindows.Add([pscustomobject]@{
            Handle = ('0x{0:X}' -f $nativeWindow.Handle.ToInt64())
            OwnerHandle = ('0x{0:X}' -f $nativeWindow.Owner.ToInt64())
            RootOwnerHandle = ('0x{0:X}' -f $nativeWindow.RootOwner.ToInt64())
            RepresentativeHandle = ('0x{0:X}' -f $nativeWindow.Representative.ToInt64())
            ProcessId = [int] $nativeWindow.ProcessId
            ProcessName = $processName
            ClassName = $nativeWindow.ClassName
            Title = $nativeWindow.Title
            Visible = $nativeWindow.Visible
            Enabled = $nativeWindow.Enabled
            Cloaked = $nativeWindow.Cloaked
            ExStyle = ('0x{0:X8}' -f $nativeWindow.ExStyle)
            ToolWindow = $nativeWindow.ToolWindow
            AppWindow = $nativeWindow.AppWindow
            AltTabCandidate = $nativeWindow.AltTabCandidate
        })
    }

    $normalizedMarkers = @($TargetMarkers | ForEach-Object { $_.ToLowerInvariant() })
    $classifiedWindows = foreach ($window in $rawWindows) {
        $processLower = $window.ProcessName.ToLowerInvariant()
        $titleLower = $window.Title.ToLowerInvariant()
        $classLower = $window.ClassName.ToLowerInvariant()
        $targetMatch = $false
        foreach ($marker in $normalizedMarkers) {
            if ($processLower -eq $marker -or $titleLower.Contains($marker) -or $classLower.Contains($marker)) {
                $targetMatch = $true
                break
            }
        }
        $railMatch = $processLower -in @('msrdc', 'mstsc', 'wslg', 'wslhost') -or $classLower -match '(rail|rdp|mstsc)'
        $titleHash = if ($window.Title.Length -gt 0) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($window.Title)
            $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
            [Convert]::ToHexString($hash).ToLowerInvariant()
        } else { $null }
        [pscustomobject]@{
            Handle = $window.Handle
            OwnerHandle = $window.OwnerHandle
            RootOwnerHandle = $window.RootOwnerHandle
            RepresentativeHandle = $window.RepresentativeHandle
            ProcessId = $window.ProcessId
            ProcessName = $window.ProcessName
            ClassName = $window.ClassName
            Title = if ($targetMatch -or $railMatch) { $window.Title } else { $null }
            TitleSha256 = $titleHash
            Visible = $window.Visible
            Enabled = $window.Enabled
            Cloaked = $window.Cloaked
            ExStyle = $window.ExStyle
            ToolWindow = $window.ToolWindow
            AppWindow = $window.AppWindow
            AltTabCandidate = $window.AltTabCandidate
            TargetMatch = $targetMatch
            RailMatch = $railMatch
        }
    }

    $baseline = $null
    $baselineRaw = $null
    $baselineSha256 = $null
    $baselineSnapshotName = $null
    $baselineSnapshotLogName = $null
    $baselineKeys = @{}
    if ($BaselineJson) {
        $baselineRaw = Get-Content -Raw -LiteralPath $BaselineJson
        $baseline = $baselineRaw | ConvertFrom-Json
        $baselineBytes = [System.Text.Encoding]::UTF8.GetBytes($baselineRaw)
        $baselineSha256 = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($baselineBytes)).ToLowerInvariant()
        $baselineSnapshotBase = if ($Prefix -match '^windows-hwnd-during') {
            $Prefix -replace '^windows-hwnd-during', 'windows-hwnd-baseline'
        } else {
            "$Prefix-baseline-input"
        }
        $baselineSnapshotName = "$baselineSnapshotBase.json"
        $baselineSnapshotLogName = "$baselineSnapshotBase.log"
        foreach ($windowKey in @($baseline.WindowKeys)) {
            if ($windowKey -is [string] -and $windowKey -match '^\d+:0x[0-9A-Fa-f]+$') {
                $baselineKeys[$windowKey] = $true
            }
        }
        # Compatibility with evidence produced before WindowKeys became the
        # privacy-preserving baseline contract.
        if ($baselineKeys.Count -eq 0) {
            foreach ($window in @($baseline.Windows)) {
                $baselineKeys["$($window.ProcessId):$($window.Handle)"] = $true
            }
        }
    }
    $newWindows = @($classifiedWindows | Where-Object { -not $baselineKeys.ContainsKey("$($_.ProcessId):$($_.Handle)") })
    $targetWindows = @($classifiedWindows | Where-Object TargetMatch)
    $targetAltTab = @($targetWindows | Where-Object AltTabCandidate)
    $newTargetWindows = @($newWindows | Where-Object TargetMatch)
    $newRailWindows = @($newWindows | Where-Object RailMatch)
    $newVisibleRailWindows = @($newRailWindows | Where-Object { $_.Visible -and -not $_.Cloaked })
    $newRailAltTab = @($newRailWindows | Where-Object AltTabCandidate)

    $assertions = [System.Collections.Generic.List[object]]::new()
    function Add-Assertion {
        param([string] $Id, [bool] $Ok, [string] $Expected, $Actual)
        $assertions.Add([pscustomobject]@{ Id = $Id; Ok = $Ok; Expected = $Expected; Actual = $Actual })
    }
    Add-Assertion 'hwnd.target-zero' ($targetWindows.Count -eq 0) 'zero top-level HWND matching target process/title/class' $targetWindows.Count
    Add-Assertion 'alttab.target-zero' ($targetAltTab.Count -eq 0) 'zero target Alt+Tab candidates' $targetAltTab.Count
    if ($Phase -eq 'During') {
        Add-Assertion 'baseline.loaded-pass' ($baseline.Verdict -eq 'PASS') 'baseline verdict PASS' $baseline.Verdict
        Add-Assertion 'hwnd.new-target-zero' ($newTargetWindows.Count -eq 0) 'zero new target HWND since baseline' $newTargetWindows.Count
        Add-Assertion 'hwnd.new-visible-wslg-rail-zero' ($newVisibleRailWindows.Count -eq 0) 'zero new visible WSLg/RDP RAIL HWND since baseline' $newVisibleRailWindows.Count
        Add-Assertion 'alttab.new-wslg-rail-zero' ($newRailAltTab.Count -eq 0) 'zero new WSLg/RDP RAIL Alt+Tab candidates since baseline' $newRailAltTab.Count
    }

    $verdict = if (@($assertions | Where-Object { -not $_.Ok }).Count -eq 0) { 'PASS' } else { 'FAIL' }
    $evidence = [ordered]@{
        SchemaVersion = 1
        CollectedAt = [DateTimeOffset]::UtcNow.ToString('o')
        Collector = 'scripts/collect-windows-window-evidence.ps1'
        FailClosed = $true
        Phase = $Phase
        TargetMarkers = $normalizedMarkers
        Baseline = if ($baseline) {
            [ordered]@{
                SnapshotFile = $baselineSnapshotName
                SnapshotLogFile = $baselineSnapshotLogName
                Sha256 = $baselineSha256
                CollectedAt = $baseline.CollectedAt
                Verdict = $baseline.Verdict
                Counts = $baseline.Counts
            }
        } else { $null }
        Verdict = $verdict
        Assertions = @($assertions)
        Counts = [ordered]@{
            TopLevel = @($classifiedWindows).Count
            AltTabCandidates = @($classifiedWindows | Where-Object AltTabCandidate).Count
            TargetTopLevel = $targetWindows.Count
            TargetAltTab = $targetAltTab.Count
            NewTopLevel = $newWindows.Count
            NewTargetTopLevel = $newTargetWindows.Count
            NewRailTopLevel = $newRailWindows.Count
            NewVisibleRailTopLevel = $newVisibleRailWindows.Count
            NewRailAltTab = $newRailAltTab.Count
        }
        WindowKeys = @($classifiedWindows | ForEach-Object { "$($_.ProcessId):$($_.Handle)" })
        TargetWindows = $targetWindows
        NewTargetWindows = $newTargetWindows
        NewRailWindows = $newRailWindows
        NewVisibleRailWindows = $newVisibleRailWindows
    }
    $logLines = [System.Collections.Generic.List[string]]::new()
    $logLines.Add("CLOUDOS WINDOWS HWND EVIDENCE: $verdict")
    $logLines.Add("phase=$Phase")
    $logLines.Add("collectedAt=$($evidence.CollectedAt)")
    $logLines.Add("topLevel=$($evidence.Counts.TopLevel) altTab=$($evidence.Counts.AltTabCandidates) targetHwnd=$($evidence.Counts.TargetTopLevel) targetAltTab=$($evidence.Counts.TargetAltTab)")
    $logLines.Add('')
    $logLines.Add('ASSERTIONS')
    foreach ($assertion in $assertions) {
        $logLines.Add("$(if ($assertion.Ok) { 'PASS' } else { 'FAIL' }) $($assertion.Id) expected=$($assertion.Expected) actual=$($assertion.Actual)")
    }
    foreach ($window in @($targetWindows + $newVisibleRailWindows)) {
        $logLines.Add("SUSPECT hwnd=$($window.Handle) pid=$($window.ProcessId) process=$($window.ProcessName) class=$($window.ClassName) altTab=$($window.AltTabCandidate) title=$($window.Title)")
    }
    if ($baseline) {
        $logLines.Add("baselineSnapshot=$baselineSnapshotName baselineSha256=$baselineSha256 baselineCollectedAt=$($baseline.CollectedAt)")
        [System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText((Join-Path $resolvedOutputDirectory $baselineSnapshotName), $baselineRaw, $utf8NoBom)
        $baselineLogLines = [System.Collections.Generic.List[string]]::new()
        $baselineLogLines.Add("CLOUDOS WINDOWS HWND EVIDENCE: $($baseline.Verdict)")
        $baselineLogLines.Add('phase=Baseline')
        $baselineLogLines.Add("collectedAt=$($baseline.CollectedAt)")
        $baselineLogLines.Add("topLevel=$($baseline.Counts.TopLevel) altTab=$($baseline.Counts.AltTabCandidates) targetHwnd=$($baseline.Counts.TargetTopLevel) targetAltTab=$($baseline.Counts.TargetAltTab)")
        $baselineLogLines.Add('')
        $baselineLogLines.Add('ASSERTIONS')
        foreach ($assertion in @($baseline.Assertions)) {
            $baselineLogLines.Add("$(if ($assertion.Ok) { 'PASS' } else { 'FAIL' }) $($assertion.Id) expected=$($assertion.Expected) actual=$($assertion.Actual)")
        }
        [System.IO.File]::WriteAllText((Join-Path $resolvedOutputDirectory $baselineSnapshotLogName), (($baselineLogLines -join [Environment]::NewLine) + [Environment]::NewLine), $utf8NoBom)
    }
    Write-EvidenceFiles -Evidence $evidence -LogLines $logLines
    Write-Output ($logLines -join [Environment]::NewLine)
    Write-Output "JSON=$jsonPath"
    Write-Output "LOG=$logPath"
    if ($verdict -ne 'PASS') { exit 1 }
    exit 0
} catch {
    $message = $_.Exception.Message
    $evidence = [ordered]@{
        SchemaVersion = 1
        CollectedAt = [DateTimeOffset]::UtcNow.ToString('o')
        Collector = 'scripts/collect-windows-window-evidence.ps1'
        FailClosed = $true
        Phase = $Phase
        TargetMarkers = $TargetMarkers
        Verdict = 'FAIL'
        Assertions = @([ordered]@{
            Id = 'collection.complete'
            Ok = $false
            Expected = 'complete top-level HWND and Alt+Tab evidence'
            Actual = 'collection failed'
        })
        FatalError = $message
        WindowKeys = @()
    }
    $logLines = @(
        'CLOUDOS WINDOWS HWND EVIDENCE: FAIL',
        "phase=$Phase",
        "collectedAt=$($evidence.CollectedAt)",
        'FAIL collection.complete',
        "FATAL $message"
    )
    Write-EvidenceFiles -Evidence $evidence -LogLines $logLines
    Write-Error $message
    Write-Output "JSON=$jsonPath"
    Write-Output "LOG=$logPath"
    exit 2
}
