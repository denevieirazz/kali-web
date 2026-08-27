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
/// Small Host-side adapter intended for WebMessageBridge routing after the physical presenter
/// gate passes. It owns generation/layout-revision bookkeeping so the web contract never needs
/// to transport native handles or mutable renderer state. The adapter itself has no fallback to
/// NativeWindowManager.TryAttach.
/// </summary>
public sealed class CapturedSurfaceBridgeAdapter : IDisposable
{
    private readonly object _sync = new();
    private readonly CapturedSurfaceSessionManager _runtime;
    private readonly long _ownerWindowHandle;
    private readonly Dictionary<string, BridgeSession> _sessions = new(StringComparer.Ordinal);
    private bool _disposed;

    public CapturedSurfaceBridgeAdapter(long ownerWindowHandle, CapturedSurfaceSessionManager runtime)
    {
        if (ownerWindowHandle == 0) throw new ArgumentOutOfRangeException(nameof(ownerWindowHandle));
        _runtime = runtime ?? throw new ArgumentNullException(nameof(runtime));
        _ownerWindowHandle = ownerWindowHandle;
    }

    public static bool CandidateEnabled =>
        string.Equals(
            Environment.GetEnvironmentVariable("CLOUDOS_CAPTURED_SURFACE"),
            "1",
            StringComparison.Ordinal);

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
            if (_sessions.TryGetValue(sessionId, out var current))
            {
                replaced = current;
                generation = checked(current.Generation + 1);
                _sessions.Remove(sessionId);
            }
            else
            {
                generation = 1;
            }
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
            _runtime.Close(session.Key, session.Value.Generation);
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
