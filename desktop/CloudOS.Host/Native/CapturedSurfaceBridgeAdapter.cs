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
    // Lock order is lifecycle -> per-session gate -> _sync. Runtime calls may hold the first
    // two, but never _sync. This lets independent apps progress concurrently while making one
    // surface's attach/layout/input/close sequence linear and teardown globally draining.
    private readonly object _sync = new();
    private readonly ReaderWriterLockSlim _lifecycle = new(LockRecursionPolicy.NoRecursion);
    private readonly ICapturedSurfaceSessionRuntime _runtime;
    private readonly long _ownerWindowHandle;
    private readonly Dictionary<string, BridgeSession> _sessions = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _lastGenerationBySessionId = new(StringComparer.Ordinal);
    private readonly Dictionary<string, object> _operationGates = new(StringComparer.Ordinal);
    private readonly object _disposedOperationGate = new();
    private bool _disposed;

    public CapturedSurfaceBridgeAdapter(long ownerWindowHandle, ICapturedSurfaceSessionRuntime runtime)
    {
        if (ownerWindowHandle == 0) throw new ArgumentOutOfRangeException(nameof(ownerWindowHandle));
        _runtime = runtime ?? throw new ArgumentNullException(nameof(runtime));
        _ownerWindowHandle = ownerWindowHandle;
    }

    public static bool CandidateEnabled =>
        !string.Equals(
            Environment.GetEnvironmentVariable("CLOUDOS_CAPTURED_SURFACE"),
            "0",
            StringComparison.Ordinal);

    public CapturedSurfaceBridgeState Attach(
        string sessionId,
        long sourceWindowHandle,
        NativeWindowBounds bounds,
        bool visible,
        double dpiScaleX,
        double dpiScaleY)
    {
        ValidateSessionId(sessionId);
        ValidateScale(dpiScaleX, nameof(dpiScaleX));
        ValidateScale(dpiScaleY, nameof(dpiScaleY));

        return WithSessionGate(sessionId, () =>
        {
            BridgeSession? replaced = null;
            int generation;
            lock (_sync)
            {
                ThrowIfDisposed();
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
            var committed = false;
            try
            {
                lock (_sync)
                {
                    ThrowIfDisposed();
                    if (_sessions.ContainsKey(sessionId))
                        throw new InvalidOperationException($"Captured-surface session '{sessionId}' was concurrently attached.");
                    _sessions.Add(sessionId, state);
                    committed = true;
                }
            }
            finally
            {
                if (!committed) _runtime.Close(sessionId, generation);
            }

            return new CapturedSurfaceBridgeState(
                sessionId,
                generation,
                revision,
                visible,
                bounds,
                runtimeSnapshot);
        });
    }

    public CapturedSurfaceBridgeState Layout(
        string sessionId,
        NativeWindowBounds bounds,
        bool visible,
        double dpiScaleX,
        double dpiScaleY)
    {
        ValidateSessionId(sessionId);
        ValidateScale(dpiScaleX, nameof(dpiScaleX));
        ValidateScale(dpiScaleY, nameof(dpiScaleY));

        return WithSessionGate(sessionId, () =>
        {
            BridgeSession current;
            lock (_sync)
            {
                ThrowIfDisposed();
                if (!_sessions.TryGetValue(sessionId, out current!))
                    throw new KeyNotFoundException($"Captured-surface session '{sessionId}' is not attached.");
            }
            var revision = checked(current.LayoutRevision + 1);
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
                _sessions[sessionId] = updated;
            }

            return new CapturedSurfaceBridgeState(
                sessionId,
                updated.Generation,
                updated.LayoutRevision,
                updated.Visible,
                updated.Bounds,
                runtimeSnapshot);
        });
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
        return WithSessionGate(sessionId, () =>
        {
            BridgeSession current;
            lock (_sync) current = GetRequiredSessionLocked(sessionId, generation);
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
        });
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
        return WithSessionGate(sessionId, () =>
        {
            BridgeSession current;
            lock (_sync) current = GetRequiredSessionLocked(sessionId, generation);
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
        });
    }

    public bool TryGetState(string sessionId, out CapturedSurfaceBridgeState? state)
    {
        state = null;
        if (string.IsNullOrWhiteSpace(sessionId)) return false;
        CapturedSurfaceBridgeState? resolved = null;
        var found = WithSessionGate(sessionId, () =>
        {
            BridgeSession current;
            lock (_sync)
            {
                if (_disposed || !_sessions.TryGetValue(sessionId, out current!)) return false;
            }
            if (!_runtime.TryGetSnapshot(sessionId, current.Generation, out var runtimeSnapshot) || runtimeSnapshot is null)
                return false;
            resolved = new CapturedSurfaceBridgeState(
                sessionId,
                current.Generation,
                current.LayoutRevision,
                current.Visible,
                current.Bounds,
                runtimeSnapshot);
            return true;
        });
        state = resolved;
        return found;
    }

    public bool Close(string sessionId)
    {
        return WithSessionGate(sessionId, () =>
        {
            BridgeSession? state;
            lock (_sync)
            {
                if (_disposed || !_sessions.Remove(sessionId, out state)) return false;
            }
            return _runtime.Close(sessionId, state.Generation);
        });
    }

    /// <summary>
    /// Closes all current surfaces without invalidating the adapter itself. Document reset
    /// uses this path so a fresh trusted WebView document can attach new captured sessions
    /// through the same Host bridge instance. Generation history intentionally survives reset.
    /// Final Host shutdown still uses Dispose().
    /// </summary>
    public void CloseAll()
    {
        _lifecycle.EnterWriteLock();
        try
        {
            KeyValuePair<string, BridgeSession>[] sessions;
            lock (_sync)
            {
                if (_disposed) return;
                sessions = _sessions.ToArray();
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
                    // Process/Job termination remains the outer fail-closed boundary. One broken
                    // renderer teardown must not leave later captured surfaces alive during reset.
                }
            }
        }
        finally
        {
            _lifecycle.ExitWriteLock();
        }
    }

    public void Dispose()
    {
        _lifecycle.EnterWriteLock();
        try
        {
            KeyValuePair<string, BridgeSession>[] sessions;
            lock (_sync)
            {
                if (_disposed) return;
                _disposed = true;
                sessions = _sessions.ToArray();
                _sessions.Clear();
                _lastGenerationBySessionId.Clear();
                _operationGates.Clear();
            }
            foreach (var session in sessions)
            {
                try
                {
                    _runtime.Close(session.Key, session.Value.Generation);
                }
                catch (Exception error) when (error is not OutOfMemoryException)
                {
                    // Continue closing the remaining surfaces during terminal Host teardown.
                }
            }
        }
        finally
        {
            _lifecycle.ExitWriteLock();
        }
    }

    private T WithSessionGate<T>(string sessionId, Func<T> operation)
    {
        _lifecycle.EnterReadLock();
        try
        {
            object gate;
            lock (_sync)
            {
                if (_disposed)
                {
                    gate = _disposedOperationGate;
                }
                else if (!_operationGates.TryGetValue(sessionId, out gate!))
                {
                    gate = new object();
                    _operationGates.Add(sessionId, gate);
                }
            }
            lock (gate) return operation();
        }
        finally
        {
            _lifecycle.ExitReadLock();
        }
    }

    private BridgeSession GetRequiredSessionLocked(string sessionId, int generation)
    {
        ThrowIfDisposed();
        ValidateSessionId(sessionId);
        if (generation <= 0) throw new ArgumentOutOfRangeException(nameof(generation));
        if (!_sessions.TryGetValue(sessionId, out var current))
            throw new KeyNotFoundException($"Captured-surface session '{sessionId}' is not attached.");
        if (current.Generation != generation)
            throw new InvalidOperationException(
                $"Stale captured-surface generation. session={sessionId}; current={current.Generation}; requested={generation}.");
        return current;
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
