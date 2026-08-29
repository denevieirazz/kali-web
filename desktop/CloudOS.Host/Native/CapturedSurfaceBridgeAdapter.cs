using CloudOS.WindowsCapture;

namespace CloudOS.Host.Native;

public sealed record CapturedSurfaceBridgeState(
    string SessionId,
    int Generation,
    long LayoutRevision,
    bool Visible,
    NativeWindowBounds Bounds,
    CapturedSurfaceSessionSnapshot Runtime);

/// <summary>
/// Host-side adapter for the WGC/D3D captured-surface renderer. Generation and layout
/// revision state stays native so the WebView never receives HWNDs, D3D resources or any
/// mutable renderer capability.
/// </summary>
public sealed class CapturedSurfaceBridgeAdapter : IDisposable
{
    private readonly object _sync = new();
    private readonly CapturedSurfaceSessionManager _runtime;
    private readonly long _ownerWindowHandle;
    private readonly Dictionary<string, BridgeSession> _sessions = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _lastGenerationBySessionId = new(StringComparer.Ordinal);
    private bool _disposed;

    public CapturedSurfaceBridgeAdapter(long ownerWindowHandle, CapturedSurfaceSessionManager runtime)
    {
        if (ownerWindowHandle == 0) throw new ArgumentOutOfRangeException(nameof(ownerWindowHandle));
        _runtime = runtime ?? throw new ArgumentNullException(nameof(runtime));
        _ownerWindowHandle = ownerWindowHandle;
    }

    /// <summary>
    /// Captured surfaces are the compatibility renderer by default. Set
    /// CLOUDOS_CAPTURED_SURFACE=0 (or "off") only for diagnostics/rollback.
    /// </summary>
    public static bool CandidateEnabled
    {
        get
        {
            var mode = Environment.GetEnvironmentVariable("CLOUDOS_CAPTURED_SURFACE")?.Trim();
            return !string.Equals(mode, "0", StringComparison.OrdinalIgnoreCase)
                && !string.Equals(mode, "off", StringComparison.OrdinalIgnoreCase)
                && !string.Equals(mode, "false", StringComparison.OrdinalIgnoreCase);
        }
    }

    public CapturedSurfaceBridgeState Attach(
        string sessionId,
        long sourceWindowHandle,
        NativeWindowBounds bounds,
        bool visible,
        double dpiScaleX,
        double dpiScaleY)
    {
        ThrowIfDisposed();
        ValidateSessionId(sessionId);
        ValidateScale(dpiScaleX, nameof(dpiScaleX));
        ValidateScale(dpiScaleY, nameof(dpiScaleY));

        BridgeSession? replaced = null;
        int generation;
        lock (_sync)
        {
            if (_sessions.Remove(sessionId, out var current))
                replaced = current;

            var lastGeneration = _lastGenerationBySessionId.TryGetValue(sessionId, out var previous)
                ? previous
                : 0;
            generation = checked(lastGeneration + 1);
            _lastGenerationBySessionId[sessionId] = generation;
        }
        if (replaced is not null) _runtime.Close(sessionId, replaced.Generation);

        const long revision = 1;
        var layout = ToLayout(revision, bounds, visible, dpiScaleX, dpiScaleY);
        var runtimeSnapshot = _runtime.CreateAndStart(
            sessionId,
            generation,
            sourceWindowHandle,
            _ownerWindowHandle,
            layout);

        var state = new BridgeSession(
            generation,
            revision,
            bounds,
            visible,
            dpiScaleX,
            dpiScaleY);
        lock (_sync)
        {
            ThrowIfDisposed();
            if (_sessions.ContainsKey(sessionId))
            {
                _runtime.Close(sessionId, generation);
                throw new InvalidOperationException($"Captured-surface session '{sessionId}' was concurrently attached.");
            }
            _sessions.Add(sessionId, state);
        }

        return new CapturedSurfaceBridgeState(
            sessionId,
            generation,
            revision,
            visible,
            bounds,
            runtimeSnapshot);
    }

    public CapturedSurfaceBridgeState Layout(
        string sessionId,
        NativeWindowBounds bounds,
        bool visible,
        double dpiScaleX,
        double dpiScaleY)
    {
        ThrowIfDisposed();
        ValidateSessionId(sessionId);
        ValidateScale(dpiScaleX, nameof(dpiScaleX));
        ValidateScale(dpiScaleY, nameof(dpiScaleY));

        BridgeSession current;
        long revision;
        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out current!))
                throw new KeyNotFoundException($"Captured-surface session '{sessionId}' is not attached.");
            revision = checked(current.LayoutRevision + 1);
        }

        var layout = ToLayout(revision, bounds, visible, dpiScaleX, dpiScaleY);
        _runtime.ApplyLayout(sessionId, current.Generation, layout);
        if (!_runtime.TryGetSnapshot(sessionId, current.Generation, out var runtimeSnapshot) || runtimeSnapshot is null)
            throw new InvalidOperationException($"Captured-surface session '{sessionId}' disappeared during layout.");

        var updated = current with
        {
            LayoutRevision = revision,
            Bounds = bounds,
            Visible = visible,
            DpiScaleX = dpiScaleX,
            DpiScaleY = dpiScaleY
        };
        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var latest) || latest.Generation != current.Generation)
                throw new InvalidOperationException($"Captured-surface session '{sessionId}' was replaced during layout.");
            if (latest.LayoutRevision >= revision)
                throw new InvalidOperationException($"Captured-surface layout revision raced for '{sessionId}'.");
            _sessions[sessionId] = updated;
        }

        return new CapturedSurfaceBridgeState(
            sessionId,
            updated.Generation,
            updated.LayoutRevision,
            updated.Visible,
            updated.Bounds,
            runtimeSnapshot);
    }

    public bool RoutePointer(
        string sessionId,
        int generation,
        long sequence,
        WindowsCapturePointerEventKind kind,
        WindowsCapturePointerButton button,
        int wheelDelta,
        bool shift,
        bool control,
        bool alt,
        double surfaceCssWidth,
        double surfaceCssHeight,
        double localCssX,
        double localCssY)
    {
        var current = GetRequiredSession(sessionId, generation);
        if (!current.Visible) return false;
        return _runtime.RoutePointer(
            sessionId,
            generation,
            sequence,
            kind,
            button,
            wheelDelta,
            shift,
            control,
            alt,
            surfaceCssWidth,
            surfaceCssHeight,
            localCssX,
            localCssY);
    }

    public bool RouteKey(
        string sessionId,
        int generation,
        long sequence,
        WindowsCaptureKeyEventKind kind,
        int virtualKey,
        int scanCode,
        bool extended,
        bool repeat)
    {
        var current = GetRequiredSession(sessionId, generation);
        if (!current.Visible) return false;
        return _runtime.RouteKey(
            sessionId,
            generation,
            sequence,
            kind,
            virtualKey,
            scanCode,
            extended,
            repeat);
    }

    public bool TryGetState(string sessionId, out CapturedSurfaceBridgeState? state)
    {
        state = null;
        if (string.IsNullOrWhiteSpace(sessionId)) return false;
        BridgeSession current;
        lock (_sync)
        {
            if (_disposed || !_sessions.TryGetValue(sessionId, out current!)) return false;
        }
        if (!_runtime.TryGetSnapshot(sessionId, current.Generation, out var runtimeSnapshot) || runtimeSnapshot is null)
            return false;
        state = new CapturedSurfaceBridgeState(
            sessionId,
            current.Generation,
            current.LayoutRevision,
            current.Visible,
            current.Bounds,
            runtimeSnapshot);
        return true;
    }

    public bool Close(string sessionId)
    {
        BridgeSession? state;
        lock (_sync)
        {
            if (_disposed || !_sessions.Remove(sessionId, out state)) return false;
        }
        return _runtime.Close(sessionId, state.Generation);
    }

    public void CloseAll()
    {
        List<KeyValuePair<string, BridgeSession>> sessions;
        lock (_sync)
        {
            if (_disposed) return;
            sessions = [.. _sessions];
            _sessions.Clear();
        }

        foreach (var session in sessions)
        {
            try
            {
                _runtime.Close(session.Key, session.Value.Generation);
            }
            catch (Exception error) when (error is not OutOfMemoryException)
            {
                // Process/Job termination remains the outer fail-closed boundary.
            }
        }
    }

    public void Dispose()
    {
        List<KeyValuePair<string, BridgeSession>> sessions;
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true;
            sessions = [.. _sessions];
            _sessions.Clear();
        }
        foreach (var session in sessions)
        {
            try
            {
                _runtime.Close(session.Key, session.Value.Generation);
            }
            catch (Exception error) when (error is not OutOfMemoryException)
            {
                // Continue closing remaining surfaces during Host teardown.
            }
        }
    }

    private BridgeSession GetRequiredSession(string sessionId, int generation)
    {
        ThrowIfDisposed();
        ValidateSessionId(sessionId);
        if (generation <= 0) throw new ArgumentOutOfRangeException(nameof(generation));
        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var current))
                throw new KeyNotFoundException($"Captured-surface session '{sessionId}' is not attached.");
            if (current.Generation != generation)
                throw new InvalidOperationException(
                    $"Stale captured-surface generation. session={sessionId}; current={current.Generation}; requested={generation}.");
            return current;
        }
    }

    private static WindowsCapturePresentationLayout ToLayout(
        long revision,
        NativeWindowBounds bounds,
        bool visible,
        double dpiScaleX,
        double dpiScaleY) =>
        new WindowsCapturePresentationLayout(
            revision,
            bounds.X,
            bounds.Y,
            bounds.Width,
            bounds.Height,
            dpiScaleX,
            dpiScaleY,
            visible).Validate();

    private static void ValidateSessionId(string sessionId)
    {
        if (string.IsNullOrWhiteSpace(sessionId)) throw new ArgumentException("Session ID is required.", nameof(sessionId));
        if (sessionId.Length > 128) throw new ArgumentOutOfRangeException(nameof(sessionId));
    }

    private static void ValidateScale(double value, string name)
    {
        if (double.IsNaN(value) || double.IsInfinity(value) || value is < 0.25 or > 8.0)
            throw new ArgumentOutOfRangeException(name);
    }

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(CapturedSurfaceBridgeAdapter));
    }

    private sealed record BridgeSession(
        int Generation,
        long LayoutRevision,
        NativeWindowBounds Bounds,
        bool Visible,
        double DpiScaleX,
        double DpiScaleY);
}
