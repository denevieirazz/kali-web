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
            if (_sessions.TryGetValue(surfaceId, out var current))
            {
                if (generation <= current.Generation)
                    throw new InvalidOperationException(
                        $"Captured-surface generation must increase. surface={surfaceId}; current={current.Generation}; requested={generation}.");
                _sessions.Remove(surfaceId);
                stale = current;
            }
        }
        stale?.Dispose();

        var source = new IntPtr(sourceWindowHandle);
        var owner = new IntPtr(ownerWindowHandle);
        HostOwnedCaptureSurfacePresenter? presenter = null;
        WindowsCaptureSurfaceCoordinator? coordinator = null;
        WindowsCaptureSession? capture = null;
        try
        {
            presenter = new HostOwnedCaptureSurfacePresenter(owner);
            coordinator = new WindowsCaptureSurfaceCoordinator(surfaceId, generation, presenter);
            coordinator.Bind(initialLayout);
            coordinator.Activate();

            capture = new WindowsCaptureSession(
                source,
                WindowsCaptureTargetKind.Window,
                WindowsCaptureItemFactoryKind.RawActivationFactory,
                WindowsCaptureItemProjectionKind.MarshalInterfaceFromAbi,
                WindowsCaptureAbiLifetimeKind.HoldUntilSessionDispose,
                frameHealthOptions ?? new WindowsFrameHealthOptions(),
                coordinator);
            capture.Start();

            var inputGate = new WindowsCaptureInputGate(generation);
            inputGate.SetActive(initialLayout.Visible);
            var state = new SessionState(
                surfaceId,
                generation,
                sourceWindowHandle,
                capture,
                coordinator,
                inputGate);

            lock (_sync)
            {
                ThrowIfDisposed();
                if (_sessions.ContainsKey(surfaceId))
                    throw new InvalidOperationException($"Captured surface '{surfaceId}' was concurrently replaced.");
                _sessions.Add(surfaceId, state);
            }

            capture = null;
            coordinator = null;
            presenter = null;
            return state.GetSnapshot();
        }
        finally
        {
            capture?.Dispose();
            coordinator?.Dispose();
            if (coordinator is null) presenter?.Dispose();
        }
    }

    public bool TryGetSnapshot(string surfaceId, int generation, out CapturedSurfaceSessionSnapshot? snapshot)
    {
        snapshot = null;
        if (string.IsNullOrWhiteSpace(surfaceId) || generation <= 0) return false;
        lock (_sync)
        {
            if (_disposed || !_sessions.TryGetValue(surfaceId, out var state) || state.Generation != generation)
                return false;
            snapshot = state.GetSnapshot();
            return true;
        }
    }

    public void ApplyLayout(
        string surfaceId,
        int generation,
        WindowsCapturePresentationLayout layout)
    {
        ArgumentNullException.ThrowIfNull(layout);
        layout.Validate();
        var state = GetRequired(surfaceId, generation);
        state.Coordinator.ApplyLayout(layout);
        state.InputGate.SetActive(layout.Visible);
    }

    public void Suspend(string surfaceId, int generation)
    {
        var state = GetRequired(surfaceId, generation);
        state.InputGate.SetActive(false);
        state.Coordinator.Suspend();
    }

    public void Resume(string surfaceId, int generation)
    {
        var state = GetRequired(surfaceId, generation);
        state.Coordinator.Activate();
        var visible = state.Coordinator.GetSnapshot().Presentation.Layout?.Visible == true;
        state.InputGate.SetActive(visible);
    }

    public WindowsCaptureInputAdmission AdmitInput(
        string surfaceId,
        int generation,
        long sequence)
    {
        var state = GetRequired(surfaceId, generation);
        return state.InputGate.Admit(generation, sequence);
    }

    public bool Close(string surfaceId, int generation)
    {
        SessionState? state;
        lock (_sync)
        {
            if (_disposed || !_sessions.TryGetValue(surfaceId, out state) || state.Generation != generation)
                return false;
            _sessions.Remove(surfaceId);
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

        public SessionState(
            string surfaceId,
            int generation,
            long sourceWindowHandle,
            WindowsCaptureSession capture,
            WindowsCaptureSurfaceCoordinator coordinator,
            WindowsCaptureInputGate inputGate)
        {
            SurfaceId = surfaceId;
            Generation = generation;
            SourceWindowHandle = sourceWindowHandle;
            Capture = capture;
            Coordinator = coordinator;
            InputGate = inputGate;
        }

        public string SurfaceId { get; }
        public int Generation { get; }
        public long SourceWindowHandle { get; }
        public WindowsCaptureSession Capture { get; }
        public WindowsCaptureSurfaceCoordinator Coordinator { get; }
        public WindowsCaptureInputGate InputGate { get; }

        public CapturedSurfaceSessionSnapshot GetSnapshot() => new(
            SurfaceId,
            Generation,
            SourceWindowHandle,
            Capture.GetSnapshot(),
            Coordinator.GetSnapshot(),
            InputGate.IsActive);

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            InputGate.ResetForDeactivation();
            Capture.Dispose();
            Coordinator.Dispose();
        }
    }
}
