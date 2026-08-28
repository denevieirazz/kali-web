[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Temporary migration patcher. CI validates the production bridge before committing it.
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$bridgePath = Join-Path $repoRoot 'desktop\CloudOS.Host\Bridge\WebMessageBridge.cs'
$content = [IO.File]::ReadAllText($bridgePath)

function Replace-ExactlyOnce([string]$Old, [string]$New, [string]$Name) {
    $count = ([regex]::Matches($script:content, [regex]::Escape($Old))).Count
    if ($count -ne 1) { throw "${Name}_EXPECTED_1_FOUND_$count" }
    $script:content = $script:content.Replace($Old, $New)
}

Replace-ExactlyOnce @'
    private readonly Dictionary<string, int> _processIdsBySessionId = new(StringComparer.Ordinal);
    private readonly Dictionary<int, NativeContainedProcessLease> _launchLeasesByProcessId = new();
'@ @'
    private readonly Dictionary<string, int> _processIdsBySessionId = new(StringComparer.Ordinal);
    private readonly Dictionary<string, NativeAppSession> _nativeSessionsById = new(StringComparer.Ordinal);
    private readonly Dictionary<int, NativeContainedProcessLease> _launchLeasesByProcessId = new();
'@ 'FIELD'

Replace-ExactlyOnce @'
    private string GetOrCreateSession(NativeWindowSnapshot window)
    {
        if (!_sessionIdsByHandle.TryGetValue(window.Handle, out var sessionId))
        {
            sessionId = $"window-{Guid.NewGuid():N}";
            _sessionIdsByHandle[window.Handle] = sessionId;
            _handlesBySessionId[sessionId] = window.Handle;
        }
        _processIdsBySessionId[sessionId] = window.ProcessId;
        return sessionId;
    }
'@ @'
    private string GetOrCreateSession(NativeWindowSnapshot window)
    {
        if (!_sessionIdsByHandle.TryGetValue(window.Handle, out var sessionId))
        {
            sessionId = $"window-{Guid.NewGuid():N}";
            _sessionIdsByHandle[window.Handle] = sessionId;
            _handlesBySessionId[sessionId] = window.Handle;
        }
        _processIdsBySessionId[sessionId] = window.ProcessId;

        var rootProcessId = ResolveLaunchRoot(window.ProcessId);
        if (_nativeSessionsById.TryGetValue(sessionId, out var nativeSession))
            nativeSession.BindWindow(window.ProcessId, window.Handle);
        else
            _nativeSessionsById[sessionId] = new NativeAppSession(
                sessionId,
                rootProcessId,
                window.ProcessId,
                window.Handle);

        return sessionId;
    }
'@ 'CREATE_SESSION'

Replace-ExactlyOnce @'
        _pendingAttachDeadlinesByHandle.Remove(handle);
        _surfacesByHandle[handle] = surface with { Visible = visible, LastNativeBounds = bounds };
        return new { sessionId, accepted = true, contained = true, containmentMode = "anchored-overlay" };
'@ @'
        _pendingAttachDeadlinesByHandle.Remove(handle);
        _surfacesByHandle[handle] = surface with { Visible = visible, LastNativeBounds = bounds };
        if (_nativeSessionsById.TryGetValue(sessionId, out var nativeSession)) nativeSession.MarkAttached();
        return new { sessionId, accepted = true, contained = true, containmentMode = "anchored-overlay" };
'@ 'ATTACH_STATE'

Replace-ExactlyOnce @'
                            _recoveringSessionByRoot[rootProcessId] = removed;
                            _recoveringSessionIds.Add(removed);
                            BrowserDiagnostics.Write(
'@ @'
                            _recoveringSessionByRoot[rootProcessId] = removed;
                            _recoveringSessionIds.Add(removed);
                            if (_nativeSessionsById.TryGetValue(removed, out var recoveringNativeSession))
                                recoveringNativeSession.MarkWindowRecovery();
                            BrowserDiagnostics.Write(
'@ 'RECOVERY_START'

Replace-ExactlyOnce @'
                        _sessionIdsByHandle[candidate.Handle] = sessionId;
                        _handlesBySessionId[sessionId] = candidate.Handle;
                        _processIdsBySessionId[sessionId] = candidate.ProcessId;
                        _pendingAttachDeadlinesByHandle[candidate.Handle] = DateTimeOffset.UtcNow.AddMilliseconds(
'@ @'
                        _sessionIdsByHandle[candidate.Handle] = sessionId;
                        _handlesBySessionId[sessionId] = candidate.Handle;
                        _processIdsBySessionId[sessionId] = candidate.ProcessId;
                        if (_nativeSessionsById.TryGetValue(sessionId, out var recoveredNativeSession))
                            recoveredNativeSession.BindWindow(candidate.ProcessId, candidate.Handle);
                        _pendingAttachDeadlinesByHandle[candidate.Handle] = DateTimeOffset.UtcNow.AddMilliseconds(
'@ 'RECOVERY_BIND'

Replace-ExactlyOnce @'
        _recoveringSessionByRoot.Remove(rootProcessId);
        _recoveringSessionIds.Remove(sessionId);
        _handlesBySessionId.Remove(sessionId);
        _processIdsBySessionId.Remove(sessionId);
        BrowserDiagnostics.Write(
'@ @'
        _recoveringSessionByRoot.Remove(rootProcessId);
        _recoveringSessionIds.Remove(sessionId);
        _handlesBySessionId.Remove(sessionId);
        _processIdsBySessionId.Remove(sessionId);
        if (_nativeSessionsById.Remove(sessionId, out var failedNativeSession)) failedNativeSession.MarkFailed();
        BrowserDiagnostics.Write(
'@ 'RECOVERY_FAIL'

Replace-ExactlyOnce @'
        var rootProcessId = ResolveLaunchRoot(processId);
        if (!_windows.TryClose(handle, out var error))
'@ @'
        var rootProcessId = ResolveLaunchRoot(processId);
        if (_nativeSessionsById.TryGetValue(sessionId, out var closingNativeSession)) closingNativeSession.MarkClosing();
        if (!_windows.TryClose(handle, out var error))
'@ 'CLOSE_STATE'

Replace-ExactlyOnce @'
    private void CompleteExitedLaunch(int rootProcessId)
    {
        _terminationRetriesByRoot.Remove(rootProcessId);
        var members = GetKnownLaunchMembers(rootProcessId);
'@ @'
    private void CompleteExitedLaunch(int rootProcessId)
    {
        _terminationRetriesByRoot.Remove(rootProcessId);
        foreach (var session in _nativeSessionsById.Values
            .Where(item => item.RootProcessId == rootProcessId)
            .ToArray())
        {
            session.MarkExited();
            _nativeSessionsById.Remove(session.SessionId);
        }
        var members = GetKnownLaunchMembers(rootProcessId);
'@ 'EXIT_STATE'

Replace-ExactlyOnce @'
        _sessionIdsByHandle.Clear();
        _handlesBySessionId.Clear();
        _processIdsBySessionId.Clear();
        foreach (var lease in _launchLeasesByProcessId.Values) lease.Dispose();
'@ @'
        _sessionIdsByHandle.Clear();
        _handlesBySessionId.Clear();
        _processIdsBySessionId.Clear();
        _nativeSessionsById.Clear();
        foreach (var lease in _launchLeasesByProcessId.Values) lease.Dispose();
'@ 'DISPOSE'

[IO.File]::WriteAllText($bridgePath, $content, [Text.UTF8Encoding]::new($false))

$updated = [IO.File]::ReadAllText($bridgePath)
foreach ($needle in @(
    'Dictionary<string, NativeAppSession> _nativeSessionsById',
    'new NativeAppSession(',
    'recoveringNativeSession.MarkWindowRecovery()',
    'recoveredNativeSession.BindWindow(candidate.ProcessId, candidate.Handle)',
    'closingNativeSession.MarkClosing()',
    'item.RootProcessId == rootProcessId'
)) {
    if (-not $updated.Contains($needle)) { throw "MISSING_$needle" }
}

Write-Host 'JOB_OWNED_NATIVE_SESSION_MODEL_PATCHED'
