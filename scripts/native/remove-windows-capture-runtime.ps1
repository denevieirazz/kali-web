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

$hostProject = Join-Path $repoRoot 'desktop\CloudOS.Host\CloudOS.Host.csproj'
$project = Read-Utf8 $hostProject
$project = $project -replace '(?m)^\s*<ProjectReference Include="\.\.\\CloudOS\.WindowsCapture\\CloudOS\.WindowsCapture\.csproj" />\r?\n', ''
$project = $project -replace '(?m)^\s*<ProjectReference Include="\.\.\\CloudOS\.WindowsCapture\.Presenter\\CloudOS\.WindowsCapture\.Presenter\.csproj" />\r?\n', ''
Write-Utf8 $hostProject $project

$bridgePath = Join-Path $repoRoot 'desktop\CloudOS.Host\Bridge\WebMessageBridge.cs'
$bridge = Read-Utf8 $bridgePath
$bridge = $bridge.Replace("using CloudOS.WindowsCapture;`r`n", '').Replace("using CloudOS.WindowsCapture;`n", '')
$bridge = $bridge.Replace("    private readonly CapturedSurfaceSessionManager? _capturedSurfaceRuntime;`r`n", '').Replace("    private readonly CapturedSurfaceSessionManager? _capturedSurfaceRuntime;`n", '')
$bridge = $bridge.Replace("    private readonly CapturedSurfaceBridgeAdapter? _capturedSurfaceBridge;`r`n", '').Replace("    private readonly CapturedSurfaceBridgeAdapter? _capturedSurfaceBridge;`n", '')
$ctorStart = '        if (NativeSurfaceMode.Current == NativeSurfaceRenderMode.CapturedSurface'
$ctorEnd = '        _windows.WindowChanged += OnNativeWindowChanged;'
$ctorIndex = $bridge.IndexOf($ctorStart, [StringComparison]::Ordinal)
if ($ctorIndex -ge 0) {
    $ctorEndIndex = $bridge.IndexOf($ctorEnd, $ctorIndex, [StringComparison]::Ordinal)
    if ($ctorEndIndex -lt 0) { throw 'BRIDGE_CAPTURE_CTOR_END_NOT_FOUND' }
    $bridge = $bridge.Substring(0, $ctorIndex) + $bridge.Substring($ctorEndIndex)
}

$attach = @'
    private async Task<object> AttachAsync(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId", "bounds", "visible");
        var sessionId = ReadString(parameters, "sessionId");
        await WaitForSessionRecoveryAsync(sessionId);
        var handle = GetHandle(sessionId);
        var surface = ReadSurfaceRequest(parameters);
        var bounds = ConvertBounds(surface);
        var visible = ReadOptionalBoolean(parameters, "visible", true);

        if (!_windows.TryAttach(handle, _ownerWindowHandle, bounds, visible, out var error))
        {
            TerminateSessionAndForget(sessionId, NativeContainmentFailure.AttachFailed);
            throw new BridgeException("WINDOW_CONTAINMENT_DENIED", error ?? "O aplicativo não aceita contenção visual.");
        }
        _pendingAttachDeadlinesByHandle.Remove(handle);
        _surfacesByHandle[handle] = surface with { Visible = visible, LastNativeBounds = bounds };
        if (_nativeSessionsById.TryGetValue(sessionId, out var nativeSession)) nativeSession.MarkAttached();
        return new { sessionId, accepted = true, contained = true, containmentMode = "anchored-overlay" };
    }

'@
$bridge = Replace-Between $bridge '    private async Task<object> AttachAsync(JsonElement parameters)' '    private async Task<object> LayoutAsync(JsonElement parameters)' $attach 'BRIDGE_ATTACH'

$layout = @'
    private async Task<object> LayoutAsync(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId", "bounds", "visible");
        var sessionId = ReadString(parameters, "sessionId");
        await WaitForSessionRecoveryAsync(sessionId);
        var handle = GetHandle(sessionId);
        var surface = ReadSurfaceRequest(parameters);
        var bounds = ConvertBounds(surface);
        var visible = ReadOptionalBoolean(parameters, "visible", true);

        if (!_windows.TryUpdateAttachedLayout(handle, bounds, visible, out var error))
        {
            _surfacesByHandle.Remove(handle);
            TerminateSessionAndForget(sessionId, NativeContainmentFailure.LayoutFailed);
            throw new BridgeException("WINDOW_LAYOUT_DENIED", error ?? "O Windows recusou a posição da janela.");
        }
        _surfacesByHandle[handle] = surface with { Visible = visible, LastNativeBounds = bounds };
        return new { sessionId, accepted = true, contained = true, containmentMode = "anchored-overlay", visible };
    }

'@
$bridge = Replace-Between $bridge '    private async Task<object> LayoutAsync(JsonElement parameters)' '    private object Detach(JsonElement parameters)' $layout 'BRIDGE_LAYOUT'

$detach = @'
    private object Detach(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId");
        var sessionId = ReadString(parameters, "sessionId");
        GetHandle(sessionId);
        TerminateSessionAndForget(sessionId, NativeContainmentFailure.DetachRequested);
        return new { sessionId, accepted = true, contained = false, containmentMode = "terminated", closed = true };
    }

'@
$bridge = Replace-Between $bridge '    private object Detach(JsonElement parameters)' '    public void RelayoutAttachedWindows()' $detach 'BRIDGE_DETACH'

$relayout = @'
    public void RelayoutAttachedWindows()
    {
        if (_disposed || _relayoutPending || _surfacesByHandle.Count == 0) return;
        _relayoutPending = true;
        _ = _dispatcher.BeginInvoke(() =>
        {
            _relayoutPending = false;
            if (_disposed) return;
            foreach (var pair in _surfacesByHandle.ToArray())
            {
                try
                {
                    if (!_windows.IsAttached(pair.Key))
                    {
                        TerminateHandleAndForget(pair.Key, NativeContainmentFailure.AttachmentLost);
                        continue;
                    }

                    var bounds = ConvertBounds(pair.Value);
                    if (_windows.TryUpdateAttachedLayout(pair.Key, bounds, pair.Value.Visible, out _))
                        _surfacesByHandle[pair.Key] = pair.Value with { LastNativeBounds = bounds };
                    else TerminateHandleAndForget(pair.Key, NativeContainmentFailure.LayoutFailed);
                }
                catch (Exception error) when (error is BridgeException or InvalidOperationException or OverflowException or ArithmeticException)
                {
                    BrowserDiagnostics.Write("native_relayout_failed", $"type={error.GetType().Name}");
                    TerminateHandleAndForget(pair.Key, NativeContainmentFailure.LayoutFailed);
                }
            }
        }, DispatcherPriority.Render);
    }

'@
$bridge = Replace-Between $bridge '    public void RelayoutAttachedWindows()' '    private long GetHandle(string sessionId)' $relayout 'BRIDGE_RELAYOUT'

$operate = @'
    private object Operate(JsonElement parameters, NativeOperation operation)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId");
        var sessionId = ReadString(parameters, "sessionId");
        if (!_handlesBySessionId.TryGetValue(sessionId, out var handle)) throw new BridgeException("SESSION_NOT_FOUND", "Janela não encontrada.");
        if (!operation(handle, out var error)) throw new BridgeException("WINDOW_OPERATION_DENIED", error ?? "O Windows recusou a operação.");
        return new { sessionId, accepted = true };
    }

'@
$bridge = Replace-Between $bridge '    private object Operate(JsonElement parameters, NativeOperation operation)' '    private async Task<object> CloseSessionAsync(JsonElement parameters)' $operate 'BRIDGE_OPERATE'

$getSessions = @'
    private object[] GetPublicSessions()
    {
        var snapshots = _windows.GetWindows();
        var sessions = new List<object>();
        foreach (var window in snapshots.OrderBy(window => window.ProcessId).ThenBy(window => window.Title, StringComparer.OrdinalIgnoreCase))
        {
            if (!_sessionIdsByHandle.TryGetValue(window.Handle, out var sessionId)) continue;
            sessions.Add(new
            {
                sessionId,
                title = string.IsNullOrWhiteSpace(window.Title) ? $"Aplicativo {window.ProcessId}" : window.Title,
                processId = window.ProcessId,
                minimized = window.IsMinimized,
                maximized = window.IsMaximized,
                contained = window.IsAttached,
                containmentMode = window.IsAttached ? "anchored-overlay" : "hidden-quarantine",
                visible = window.IsVisible,
                bounds = new { x = window.Bounds.X, y = window.Bounds.Y, width = window.Bounds.Width, height = window.Bounds.Height }
            });
        }
        return sessions.ToArray();
    }

'@
$bridge = Replace-Between $bridge '    private object[] GetPublicSessions()' '    private void PostResponse(string id, bool ok, object? result, object? error)' $getSessions 'BRIDGE_SESSIONS'

$bridge = $bridge.Replace("        SweepCapturedSurfaceHealth();`r`n", '').Replace("        SweepCapturedSurfaceHealth();`n", '')
if ($bridge.Contains('    private void SweepCapturedSurfaceHealth()')) {
    $bridge = Replace-Between $bridge '    private void SweepCapturedSurfaceHealth()' '    private void TerminateSessionAndForget(string sessionId, NativeContainmentFailure failure)' '' 'BRIDGE_CAPTURE_HEALTH'
}

$bridge = [regex]::Replace($bridge, '(?m)^\s*_capturedSurfaceBridge\?\.Close\([^\r\n]+\);\r?\n', '')
$bridge = [regex]::Replace($bridge, '(?m)^\s*_capturedSurfaceBridge\?\.CloseAll\(\);\r?\n', '')
$bridge = [regex]::Replace($bridge, '(?m)^\s*_capturedSurfaceBridge\?\.Dispose\(\);\r?\n', '')
$bridge = [regex]::Replace($bridge, '(?m)^\s*_capturedSurfaceRuntime\?\.Dispose\(\);\r?\n', '')
$isCapturedBlock = @'
                var isCaptured = _capturedSurfaceBridge is not null
                    && _capturedSurfaceBridge.TryGetState(sessionId, out _);
                if (!eventArgs.Window.IsAttached && !isCaptured && !_pendingAttachDeadlinesByHandle.ContainsKey(handle))
'@
$nativeOnlyBlock = @'
                if (!eventArgs.Window.IsAttached && !_pendingAttachDeadlinesByHandle.ContainsKey(handle))
'@
if ($bridge.Contains($isCapturedBlock)) { $bridge = $bridge.Replace($isCapturedBlock, $nativeOnlyBlock) }

foreach ($forbidden in @('CapturedSurface', '_capturedSurfaceBridge', '_capturedSurfaceRuntime', 'WINDOW_CAPTURE_', 'captured-surface', 'WindowsCaptureSetupException')) {
    if ($bridge.Contains($forbidden)) { throw "BRIDGE_CAPTURE_REFERENCE_REMAINS_$forbidden" }
}
Write-Utf8 $bridgePath $bridge

foreach ($path in @(
    'desktop\CloudOS.Host\Native\CapturedSurfaceBridgeAdapter.cs',
    'desktop\CloudOS.Host\Native\CapturedSurfaceSessionManager.cs',
    'desktop\CloudOS.Host\Native\NativeSurfaceMode.cs'
)) {
    $full = Join-Path $repoRoot $path
    if (Test-Path $full) { Remove-Item -Force $full }
}

$programPath = Join-Path $repoRoot 'desktop\CloudOS.Host.Tests\Program.cs'
$program = Read-Utf8 $programPath
$program = [regex]::Replace($program, '(?m)^\s*CapturedSourceIsolationFollowsSurface\(\);\r?\n', '')
$start = $program.IndexOf('static void CapturedSourceIsolationFollowsSurface()', [StringComparison]::Ordinal)
if ($start -ge 0) {
    $end = $program.IndexOf('static void ', $start + 'static void CapturedSourceIsolationFollowsSurface()'.Length, [StringComparison]::Ordinal)
    if ($end -lt 0) { throw 'CAPTURE_TEST_END_NOT_FOUND' }
    $program = $program.Substring(0, $start) + $program.Substring($end)
}
Write-Utf8 $programPath $program

$surfaceContractPath = Join-Path $repoRoot 'desktop\CloudOS.Host.Tests\NativeSurfaceModeContract.cs'
$surfaceContract = @'
using System.Runtime.CompilerServices;

internal static class NativeSurfaceModeContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        var repoRoot = RepoRoot();
        var bridgePath = Path.Combine(repoRoot, "desktop", "CloudOS.Host", "Bridge", "WebMessageBridge.cs");
        var projectPath = Path.Combine(repoRoot, "desktop", "CloudOS.Host", "CloudOS.Host.csproj");
        var bridge = File.ReadAllText(bridgePath);
        var project = File.ReadAllText(projectPath);

        Assert(bridge.Contains("containmentMode = \"anchored-overlay\"", StringComparison.Ordinal),
            "Native HWND anchored-overlay must remain the Windows application renderer.");
        Assert(!bridge.Contains("captured-surface", StringComparison.OrdinalIgnoreCase)
            && !bridge.Contains("CapturedSurface", StringComparison.Ordinal),
            "The production bridge must not contain a captured-surface renderer.");
        Assert(!project.Contains("CloudOS.WindowsCapture", StringComparison.Ordinal),
            "The Host must not reference Windows capture projects.");
        Assert(!File.Exists(Path.Combine(repoRoot, "desktop", "CloudOS.Host", "Native", "NativeSurfaceMode.cs")),
            "The capture renderer selector must be removed.");

        Console.WriteLine("PASS native Windows surface-only contract");
    }

    private static string RepoRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            if (Directory.Exists(Path.Combine(current.FullName, ".git"))) return current.FullName;
            current = current.Parent;
        }
        throw new InvalidOperationException("Repository root not found.");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
'@
Write-Utf8 $surfaceContractPath $surfaceContract

foreach ($dir in @('desktop\CloudOS.WindowsCapture', 'desktop\CloudOS.WindowsCapture.Presenter')) {
    $full = Join-Path $repoRoot $dir
    if (Test-Path $full) { Remove-Item -Recurse -Force $full }
}
foreach ($workflow in @(
    '.github\workflows\windows-capture-physical-harness-ci.yml',
    '.github\workflows\windows-captured-surface-ci.yml',
    '.github\workflows\windows-captured-surface-native-session-reference-ci.yml',
    '.github\workflows\windows-captured-surface-presenter-ci.yml'
)) {
    $full = Join-Path $repoRoot $workflow
    if (Test-Path $full) { Remove-Item -Force $full }
}
Get-ChildItem (Join-Path $repoRoot 'scripts') -Recurse -File | Where-Object {
    $_.Name -match '(?i)(windows-capture|captured-surface)'
} | Remove-Item -Force

$forbiddenFiles = Get-ChildItem (Join-Path $repoRoot 'desktop\CloudOS.Host') -Recurse -File -Include *.cs,*.csproj |
    Where-Object { (Get-Content $_.FullName -Raw) -match 'CloudOS\.WindowsCapture|CapturedSurface|captured-surface' }
if ($forbiddenFiles) {
    throw ('HOST_CAPTURE_REFERENCES_REMAIN=' + (($forbiddenFiles.FullName | ForEach-Object { Resolve-Path -Relative $_ }) -join ','))
}

Write-Host 'WINDOWS_CAPTURE_RUNTIME_REMOVED_PHASE1'
