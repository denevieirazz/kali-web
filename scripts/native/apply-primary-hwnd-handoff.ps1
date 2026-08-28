[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$path = Join-Path $root 'desktop\CloudOS.Host\Bridge\WebMessageBridge.cs'
$text = [IO.File]::ReadAllText($path).Replace("`r`n", "`n")

if ($text.Contains('PrimaryWindowReplacementGraceMilliseconds = 5_000', [StringComparison]::Ordinal)) {
    Write-Host 'PRIMARY_HWND_HANDOFF_ALREADY_APPLIED'
    exit 0
}

function Normalize([string]$value) {
    return $value.Replace("`r`n", "`n")
}

function Replace-Exact([string]$name, [string]$old, [string]$new) {
    $old = Normalize $old
    $new = Normalize $new
    if (-not $script:text.Contains($old, [StringComparison]::Ordinal)) {
        throw "PATCH_ANCHOR_NOT_FOUND:$name"
    }
    $script:text = $script:text.Replace($old, $new, [StringComparison]::Ordinal)
}

Replace-Exact 'constants' @'
    private const int WindowCandidateStabilityMilliseconds = 350;
'@ @'
    private const int WindowCandidateStabilityMilliseconds = 350;
    private const int PrimaryWindowReplacementGraceMilliseconds = 5_000;
'@

Replace-Exact 'recovery-fields' @'
    private readonly Dictionary<int, (DateTimeOffset Deadline, NativeContainmentFailure Failure)> _terminationRetriesByRoot = new();
    private readonly Dictionary<long, AttachedSurfaceRequest> _surfacesByHandle = new();
'@ @'
    private readonly Dictionary<int, (DateTimeOffset Deadline, NativeContainmentFailure Failure)> _terminationRetriesByRoot = new();
    private readonly Dictionary<int, string> _recoveringSessionByRoot = new();
    private readonly HashSet<string> _recoveringSessionIds = new(StringComparer.Ordinal);
    private readonly Dictionary<long, AttachedSurfaceRequest> _surfacesByHandle = new();
'@

Replace-Exact 'dispatch-attach-layout' @'
            case "native.session.attach":
                return Attach(parameters);
            case "native.session.layout":
                return Layout(parameters);
'@ @'
            case "native.session.attach":
                return await AttachAsync(parameters);
            case "native.session.layout":
                return await LayoutAsync(parameters);
'@

Replace-Exact 'attach-async' @'
    private object Attach(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId", "bounds", "visible");
        var sessionId = ReadString(parameters, "sessionId");
        var handle = GetHandle(sessionId);
'@ @'
    private async Task<object> AttachAsync(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId", "bounds", "visible");
        var sessionId = ReadString(parameters, "sessionId");
        await WaitForSessionRecoveryAsync(sessionId);
        var handle = GetHandle(sessionId);
'@

Replace-Exact 'layout-async' @'
    private object Layout(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId", "bounds", "visible");
        var sessionId = ReadString(parameters, "sessionId");
        var handle = GetHandle(sessionId);
'@ @'
    private async Task<object> LayoutAsync(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId", "bounds", "visible");
        var sessionId = ReadString(parameters, "sessionId");
        await WaitForSessionRecoveryAsync(sessionId);
        var handle = GetHandle(sessionId);
'@

$oldWindowChanged = @'
    private void OnNativeWindowChanged(object? sender, NativeWindowChangedEventArgs eventArgs)
    {
        _dispatcher.BeginInvoke(() =>
        {
            if (_disposed) return;
            var handle = eventArgs.Window.Handle;
            if (eventArgs.Kind == NativeWindowChangeKind.Removed)
            {
                _surfacesByHandle.Remove(handle);
                _pendingAttachDeadlinesByHandle.Remove(handle);
                if (_sessionIdsByHandle.Remove(handle, out var removed))
                {
                    _capturedSurfaceBridge?.Close(removed);
                    _handlesBySessionId.Remove(removed);
                    if (_processIdsBySessionId.Remove(removed, out var removedProcessId))
                    {
                        BrowserDiagnostics.Write(
                            "native_primary_window_removed",
                            $"session={removed} pid={removedProcessId}");
                        TerminateProcessAndForget(removedProcessId, NativeContainmentFailure.AttachmentLost);
                    }
                }
            }
            else if (_sessionIdsByHandle.TryGetValue(handle, out var sessionId))
            {
                // Only a HWND explicitly selected by native.launchApp is a public CloudOS
                // session. Splash screens, helper windows and other Job-owned roots remain
                // quarantined, but they never receive their own attach deadline and therefore
                // cannot kill the whole application merely because the frontend did not dock them.
                var isCaptured = _capturedSurfaceBridge is not null
                    && _capturedSurfaceBridge.TryGetState(sessionId, out _);
                if (!eventArgs.Window.IsAttached && !isCaptured && !_pendingAttachDeadlinesByHandle.ContainsKey(handle))
                {
                    _pendingAttachDeadlinesByHandle[handle] = DateTimeOffset.UtcNow.AddMilliseconds(
                        NativeLaunchContainmentPolicy.PendingAttachTimeoutMilliseconds);
                }
            }
            PostEvent("native.sessionsChanged", new { sessions = GetPublicSessions() });
        }, DispatcherPriority.Background);
    }
'@

$newWindowChanged = @'
    private void OnNativeWindowChanged(object? sender, NativeWindowChangedEventArgs eventArgs)
    {
        _dispatcher.BeginInvoke(() =>
        {
            if (_disposed) return;
            var handle = eventArgs.Window.Handle;
            var recoveryStarted = false;
            if (eventArgs.Kind == NativeWindowChangeKind.Removed)
            {
                _surfacesByHandle.Remove(handle);
                _pendingAttachDeadlinesByHandle.Remove(handle);
                if (_sessionIdsByHandle.Remove(handle, out var removed))
                {
                    _capturedSurfaceBridge?.Close(removed);
                    if (_processIdsBySessionId.TryGetValue(removed, out var removedProcessId))
                    {
                        var rootProcessId = ResolveLaunchRoot(removedProcessId);
                        if (_launchLeasesByProcessId.ContainsKey(rootProcessId))
                        {
                            _recoveringSessionByRoot[rootProcessId] = removed;
                            _recoveringSessionIds.Add(removed);
                            BrowserDiagnostics.Write(
                                "native_primary_window_recovery_started",
                                $"session={removed} rootPid={rootProcessId} oldPid={removedProcessId} oldHwnd={handle}");
                            _ = RecoverPrimaryWindowAsync(rootProcessId, removed, handle, removedProcessId);
                            recoveryStarted = true;
                        }
                        else
                        {
                            _handlesBySessionId.Remove(removed);
                            _processIdsBySessionId.Remove(removed);
                            BrowserDiagnostics.Write(
                                "native_primary_window_removed",
                                $"session={removed} pid={removedProcessId}");
                            TerminateProcessAndForget(removedProcessId, NativeContainmentFailure.AttachmentLost);
                        }
                    }
                    else
                    {
                        _handlesBySessionId.Remove(removed);
                    }
                }
            }
            else if (_sessionIdsByHandle.TryGetValue(handle, out var sessionId))
            {
                // Only a HWND explicitly selected by native.launchApp is a public CloudOS
                // session. Splash screens, helper windows and other Job-owned roots remain
                // quarantined, but they never receive their own attach deadline and therefore
                // cannot kill the whole application merely because the frontend did not dock them.
                var isCaptured = _capturedSurfaceBridge is not null
                    && _capturedSurfaceBridge.TryGetState(sessionId, out _);
                if (!eventArgs.Window.IsAttached && !isCaptured && !_pendingAttachDeadlinesByHandle.ContainsKey(handle))
                {
                    _pendingAttachDeadlinesByHandle[handle] = DateTimeOffset.UtcNow.AddMilliseconds(
                        NativeLaunchContainmentPolicy.PendingAttachTimeoutMilliseconds);
                }
            }

            // Never publish a transient empty session list while the selected primary HWND is
            // being replaced by another HWND inside the same contained Job. The logical session
            // remains alive and is rebound atomically once a stable replacement is observed.
            if (!recoveryStarted && _recoveringSessionIds.Count == 0)
                PostEvent("native.sessionsChanged", new { sessions = GetPublicSessions() });
        }, DispatcherPriority.Background);
    }

    private async Task WaitForSessionRecoveryAsync(string sessionId)
    {
        var deadline = DateTimeOffset.UtcNow.AddMilliseconds(PrimaryWindowReplacementGraceMilliseconds + 1_000);
        while (!_disposed && _recoveringSessionIds.Contains(sessionId) && DateTimeOffset.UtcNow < deadline)
            await Task.Delay(25);

        if (_recoveringSessionIds.Contains(sessionId))
            throw new BridgeException(
                "WINDOW_REPLACEMENT_PENDING",
                "A janela nativa ainda está sendo reconectada dentro da mesma sessão do CloudOS.");
    }

    private async Task RecoverPrimaryWindowAsync(
        int rootProcessId,
        string sessionId,
        long removedHandle,
        int removedProcessId)
    {
        var started = DateTimeOffset.UtcNow;
        var deadline = started.AddMilliseconds(PrimaryWindowReplacementGraceMilliseconds);
        long preferredHandle = 0;
        var preferredSince = DateTimeOffset.MinValue;
        string? failureReason = null;

        try
        {
            while (!_disposed && DateTimeOffset.UtcNow < deadline)
            {
                if (!_recoveringSessionByRoot.TryGetValue(rootProcessId, out var currentSession)
                    || !string.Equals(currentSession, sessionId, StringComparison.Ordinal))
                    return;
                if (!_launchLeasesByProcessId.TryGetValue(rootProcessId, out var lease))
                {
                    failureReason = "launch-lease-lost";
                    break;
                }

                var processIds = SynchronizeTrackedJob(lease);
                if (processIds.Count == 0)
                {
                    failureReason = "job-empty";
                    break;
                }

                _windows.Refresh();
                foreach (var processId in processIds)
                {
                    if (!_windows.TryGetContainmentFailure(processId, out var containmentError)) continue;
                    failureReason = string.IsNullOrWhiteSpace(containmentError)
                        ? $"containment-failed:{processId}"
                        : $"containment-failed:{processId}:{containmentError}";
                    break;
                }
                if (failureReason is not null) break;

                var memberSet = processIds.ToHashSet();
                var candidates = _windows.GetWindows()
                    .Where(item => memberSet.Contains(item.ProcessId))
                    .Where(item => item.Handle != removedHandle)
                    .Where(item => !item.IsAttached && !item.IsVisible)
                    .ToArray();

                if (candidates.Length > 0)
                {
                    var candidate = candidates
                        .OrderByDescending(item => !string.IsNullOrWhiteSpace(item.Title))
                        .ThenByDescending(item => (long)item.Bounds.Width * item.Bounds.Height)
                        .ThenBy(item => item.ProcessId)
                        .First();
                    var now = DateTimeOffset.UtcNow;
                    if (candidate.Handle != preferredHandle)
                    {
                        preferredHandle = candidate.Handle;
                        preferredSince = now;
                    }
                    else if (now - preferredSince >= TimeSpan.FromMilliseconds(WindowCandidateStabilityMilliseconds))
                    {
                        if (!_recoveringSessionByRoot.TryGetValue(rootProcessId, out currentSession)
                            || !string.Equals(currentSession, sessionId, StringComparison.Ordinal))
                            return;

                        _recoveringSessionByRoot.Remove(rootProcessId);
                        _recoveringSessionIds.Remove(sessionId);
                        _sessionIdsByHandle[candidate.Handle] = sessionId;
                        _handlesBySessionId[sessionId] = candidate.Handle;
                        _processIdsBySessionId[sessionId] = candidate.ProcessId;
                        _pendingAttachDeadlinesByHandle[candidate.Handle] = DateTimeOffset.UtcNow.AddMilliseconds(
                            NativeLaunchContainmentPolicy.PendingAttachTimeoutMilliseconds);

                        BrowserDiagnostics.Write(
                            "native_primary_window_recovered",
                            $"session={sessionId} rootPid={rootProcessId} oldPid={removedProcessId} newPid={candidate.ProcessId} oldHwnd={removedHandle} newHwnd={candidate.Handle} elapsedMs={(long)(DateTimeOffset.UtcNow - started).TotalMilliseconds}");
                        PostEvent("native.sessionsChanged", new { sessions = GetPublicSessions() });
                        return;
                    }
                }
                else
                {
                    preferredHandle = 0;
                    preferredSince = DateTimeOffset.MinValue;
                }

                await Task.Delay(25);
            }
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            failureReason = $"{error.GetType().Name}:{error.Message}";
        }

        if (!_recoveringSessionByRoot.TryGetValue(rootProcessId, out var recoveringSession)
            || !string.Equals(recoveringSession, sessionId, StringComparison.Ordinal))
            return;

        _recoveringSessionByRoot.Remove(rootProcessId);
        _recoveringSessionIds.Remove(sessionId);
        _handlesBySessionId.Remove(sessionId);
        _processIdsBySessionId.Remove(sessionId);
        BrowserDiagnostics.Write(
            "native_primary_window_recovery_failed",
            $"session={sessionId} rootPid={rootProcessId} oldPid={removedProcessId} oldHwnd={removedHandle} reason={failureReason ?? "timeout"} elapsedMs={(long)(DateTimeOffset.UtcNow - started).TotalMilliseconds}");
        TerminateProcessAndForget(rootProcessId, NativeContainmentFailure.AttachmentLost);
        PostEvent("native.sessionsChanged", new { sessions = GetPublicSessions() });
    }
'@

Replace-Exact 'window-replacement' $oldWindowChanged $newWindowChanged

Replace-Exact 'complete-exited-recovery-cleanup' @'
    private void CompleteExitedLaunch(int rootProcessId)
    {
        _terminationRetriesByRoot.Remove(rootProcessId);
        var members = GetKnownLaunchMembers(rootProcessId);
'@ @'
    private void CompleteExitedLaunch(int rootProcessId)
    {
        _terminationRetriesByRoot.Remove(rootProcessId);
        if (_recoveringSessionByRoot.Remove(rootProcessId, out var recoveringSessionId))
        {
            _recoveringSessionIds.Remove(recoveringSessionId);
            _handlesBySessionId.Remove(recoveringSessionId);
            _processIdsBySessionId.Remove(recoveringSessionId);
        }
        var members = GetKnownLaunchMembers(rootProcessId);
'@

Replace-Exact 'dispose-recovery-state' @'
        _launchRootByMemberProcessId.Clear();
        _terminationRetriesByRoot.Clear();
        _surfacesByHandle.Clear();
'@ @'
        _launchRootByMemberProcessId.Clear();
        _terminationRetriesByRoot.Clear();
        _recoveringSessionByRoot.Clear();
        _recoveringSessionIds.Clear();
        _surfacesByHandle.Clear();
'@

[IO.File]::WriteAllText($path, $text.Replace("`n", [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Host 'PRIMARY_HWND_HANDOFF_APPLIED'
