using CloudOS.WindowsCapture;
using CloudOS.WindowsCapture.Presenter;

namespace CloudOS.Host.Native;

public sealed record CapturedSurfaceSessionSnapshot(
    string SurfaceId,
    int Generation,
    long SourceWindowHandle,
    WindowsCaptureSnapshot Capture,
    WindowsCaptureSurfaceCoordinatorSnapshot Presentation,
    bool InputActive);

/// <summary>
/// Host-side owner for the captured-surface candidate runtime. This class intentionally
/// does not reuse NativeWindowManager.TryAttach: the source HWND stays a foreign top-level
/// capture target and pixels are presented only through a Host-owned native surface.
/// Source-window quarantine/isolation remains a separate physical gate; this manager never
/// falls back to showing or reparenting the source window on the normal Windows desktop.
/// </summary>
public sealed class CapturedSurfaceSessionManager : IDisposable
{
    private readonly object _sync = new();
    private readonly Dictionary<string, SessionState> _sessions = new(StringComparer.Ordinal);
    private readonly Dictionary<long, string> _surfaceBySourceWindow = new();
    private bool _disposed;

    public CapturedSurfaceSessionSnapshot CreateAndStart(
        string surfaceId,
        int generation,
        long sourceWindowHandle,
        long ownerWindowHandle,
        WindowsCapturePresentationLayout initialLayout,
        WindowsFrameHealthOptions? frameHealthOptions = null)
    {
        ThrowIfDisposed();
        ValidateSurfaceId(surfaceId);
        if (generation <= 0) throw new ArgumentOutOfRangeException(nameof(generation));
        if (sourceWindowHandle == 0) throw new ArgumentOutOfRangeException(nameof(sourceWindowHandle));
        if (ownerWindowHandle == 0) throw new ArgumentOutOfRangeException(nameof(ownerWindowHandle));
        ArgumentNullException.ThrowIfNull(initialLayout);
        initialLayout.Validate();

        SessionState? stale = null;
        lock (_sync)
        {
            ThrowIfDisposed();
            if (_sessions.TryGetValue(surfaceId, out var current))
            {
                if (generation <= current.Generation)
                    throw new InvalidOperationException(
                        $"Captured-surface generation must increase. surface={surfaceId}; current={current.Generation}; requested={generation}.");
                _sessions.Remove(surfaceId);
                _surfaceBySourceWindow.Remove(current.SourceWindowHandle);
                stale = current;
            }

            if (_surfaceBySourceWindow.TryGetValue(sourceWindowHandle, out var existingSurface))
                throw new InvalidOperationException(
                    $"Source HWND is already owned by captured surface '{existingSurface}'.");
        }
        stale?.Dispose();

        HostOwnedCapturedSurfaceSession? runtime = null;
        try
        {
            runtime = new HostOwnedCapturedSurfaceSession(
                new IntPtr(ownerWindowHandle),
                new IntPtr(sourceWindowHandle),
                surfaceId,
                generation,
                initialLayout,
                frameHealthOptions ?? new WindowsFrameHealthOptions());
            runtime.Start();

            var state = new SessionState(runtime);
            lock (_sync)
            {
                ThrowIfDisposed();
                if (_sessions.ContainsKey(surfaceId))
                    throw new InvalidOperationException($"Captured surface '{surfaceId}' was concurrently replaced.");
                if (_surfaceBySourceWindow.TryGetValue(sourceWindowHandle, out var racedSurface))
                    throw new InvalidOperationException(
                        $"Source HWND was concurrently claimed by captured surface '{racedSurface}'.");

                _sessions.Add(surfaceId, state);
                _surfaceBySourceWindow.Add(sourceWindowHandle, surfaceId);
            }

            runtime = null;
            return state.GetSnapshot();
        }
        finally
        {
            runtime?.Dispose();
        }
    }

    public bool TryGetSnapshot(string surfaceId, int generation, out CapturedSurfaceSessionSnapshot? snapshot)
    {
        snapshot = null;
        if (string.IsNullOrWhiteSpace(surfaceId) || generation <= 0) return false;
        SessionState? state;
        lock (_sync)
        {
            if (_disposed || !_sessions.TryGetValue(surfaceId, out state) || state.Generation != generation)
                return false;
        }

        snapshot = state.GetSnapshot();
        return true;
    }

    public void ApplyLayout(
        string surfaceId,
        int generation,
        WindowsCapturePresentationLayout layout)
    {
        ArgumentNullException.ThrowIfNull(layout);
        layout.Validate();
        GetRequired(surfaceId, generation).Runtime.ApplyLayout(layout);
    }

    public void Suspend(string surfaceId, int generation) =>
        GetRequired(surfaceId, generation).Runtime.Suspend();

    public void Resume(string surfaceId, int generation) =>
        GetRequired(surfaceId, generation).Runtime.Resume();

    /// <summary>
    /// Admission-only diagnostic. Do not call this immediately before InjectPointer/InjectKey,
    /// because successful admission consumes the sequence number by design.
    /// </summary>
    public WindowsCaptureInputAdmission AdmitInput(
        string surfaceId,
        int generation,
        long sequence) =>
        GetRequired(surfaceId, generation).Runtime.AdmitInput(sequence);

    public WindowsCaptureInputInjectionResult InjectPointer(
        string surfaceId,
        int generation,
        WindowsCapturePointerInput input)
    {
        ArgumentNullException.ThrowIfNull(input);
        if (input.Generation != generation)
            throw new InvalidOperationException(
                $"Pointer input generation does not match session generation. session={generation}; input={input.Generation}.");
        return GetRequired(surfaceId, generation).Runtime.InjectPointer(input);
    }

    public WindowsCaptureInputInjectionResult InjectKey(
        string surfaceId,
        int generation,
        WindowsCaptureKeyInput input)
    {
        ArgumentNullException.ThrowIfNull(input);
        if (input.Generation != generation)
            throw new InvalidOperationException(
                $"Key input generation does not match session generation. session={generation}; input={input.Generation}.");
        return GetRequired(surfaceId, generation).Runtime.InjectKey(input);
    }

    public bool Close(string surfaceId, int generation)
    {
        SessionState? state;
        lock (_sync)
        {
            if (_disposed || !_sessions.TryGetValue(surfaceId, out state) || state.Generation != generation)
                return false;
            _sessions.Remove(surfaceId);
            _surfaceBySourceWindow.Remove(state.SourceWindowHandle);
        }
        state.Dispose();
        return true;
    }

    public void Dispose()
    {
        List<SessionState> sessions;
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true;
            sessions = [.. _sessions.Values];
            _sessions.Clear();
            _surfaceBySourceWindow.Clear();
        }
        foreach (var session in sessions) session.Dispose();
    }

    private SessionState GetRequired(string surfaceId, int generation)
    {
        ThrowIfDisposed();
        ValidateSurfaceId(surfaceId);
        if (generation <= 0) throw new ArgumentOutOfRangeException(nameof(generation));
        lock (_sync)
        {
            if (!_sessions.TryGetValue(surfaceId, out var state))
                throw new KeyNotFoundException($"Captured surface '{surfaceId}' is not active.");
            if (state.Generation != generation)
                throw new InvalidOperationException(
                    $"Stale captured-surface generation. surface={surfaceId}; current={state.Generation}; requested={generation}.");
            return state;
        }
    }

    private static void ValidateSurfaceId(string surfaceId)
    {
        if (string.IsNullOrWhiteSpace(surfaceId)) throw new ArgumentException("Surface ID is required.", nameof(surfaceId));
        if (surfaceId.Length > 128) throw new ArgumentOutOfRangeException(nameof(surfaceId));
    }

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(CapturedSurfaceSessionManager));
    }

    private sealed class SessionState : IDisposable
    {
        private bool _disposed;

        public SessionState(HostOwnedCapturedSurfaceSession runtime)
        {
            Runtime = runtime ?? throw new ArgumentNullException(nameof(runtime));
        }

        public HostOwnedCapturedSurfaceSession Runtime { get; }
        public int Generation => Runtime.Generation;
        public long SourceWindowHandle => Runtime.SourceWindowHandle.ToInt64();

        public CapturedSurfaceSessionSnapshot GetSnapshot()
        {
            var snapshot = Runtime.GetSnapshot();
            var inputActive = snapshot.State == HostOwnedCapturedSurfaceSessionState.Active &&
                              snapshot.SourceWindowAlive &&
                              snapshot.Surface.Presentation.Layout?.Visible == true &&
                              string.IsNullOrWhiteSpace(snapshot.Failure) &&
                              string.IsNullOrWhiteSpace(snapshot.Capture.Failure) &&
                              !snapshot.Surface.Presentation.IsTerminal;
            return new CapturedSurfaceSessionSnapshot(
                snapshot.SurfaceId,
                snapshot.Generation,
                snapshot.SourceWindowHandle,
                snapshot.Capture,
                snapshot.Surface,
                inputActive);
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            Runtime.Dispose();
        }
    }
}
