using System.Text.RegularExpressions;
using CloudOS.WindowsCapture;

namespace CloudOS.WindowsCapture.Presenter;

public sealed class CapturedSurfaceSessionManagerException : InvalidOperationException
{
    public CapturedSurfaceSessionManagerException(string code, string message)
        : base(message)
    {
        Code = code;
    }

    public string Code { get; }
}

public sealed record HostOwnedCapturedSurfaceManagedSnapshot(
    string SessionId,
    int Generation,
    HostOwnedCapturedSurfaceSessionState State,
    long CaptureFrameCount,
    long PresentedFrameCount,
    long DroppedFrameCount,
    bool HasFrames,
    bool InputActive,
    bool SourceWindowAlive,
    string? Failure);

public interface ICapturedSurfaceRuntimeSession : IDisposable
{
    int Generation { get; }
    IntPtr SourceWindowHandle { get; }
    void Start();
    void ApplyLayout(WindowsCapturePresentationLayout layout);
    void Suspend();
    void Resume();
    bool TryRoutePointer(
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
        double localCssY);
    bool TryRouteKey(
        long sequence,
        WindowsCaptureKeyEventKind kind,
        int virtualKey,
        int scanCode,
        bool extended,
        bool repeat);
    HostOwnedCapturedSurfaceSessionSnapshot GetSnapshot();
    void Close();
}

public interface ICapturedSurfaceRuntimeSessionFactory
{
    ICapturedSurfaceRuntimeSession Create(
        IntPtr cloudOsOwnerWindowHandle,
        IntPtr sourceWindowHandle,
        string surfaceId,
        int generation,
        WindowsCapturePresentationLayout initialLayout);
}

public sealed class HostOwnedCapturedSurfaceSessionFactory : ICapturedSurfaceRuntimeSessionFactory
{
    public ICapturedSurfaceRuntimeSession Create(
        IntPtr cloudOsOwnerWindowHandle,
        IntPtr sourceWindowHandle,
        string surfaceId,
        int generation,
        WindowsCapturePresentationLayout initialLayout) =>
        new RuntimeAdapter(new HostOwnedCapturedSurfaceSession(
            cloudOsOwnerWindowHandle,
            sourceWindowHandle,
            surfaceId,
            generation,
            initialLayout));

    private sealed class RuntimeAdapter : ICapturedSurfaceRuntimeSession
    {
        private readonly HostOwnedCapturedSurfaceSession _inner;

        public RuntimeAdapter(HostOwnedCapturedSurfaceSession inner)
        {
            _inner = inner;
        }

        public int Generation => _inner.Generation;
        public IntPtr SourceWindowHandle => _inner.SourceWindowHandle;
        public void Start() => _inner.Start();
        public void ApplyLayout(WindowsCapturePresentationLayout layout) => _inner.ApplyLayout(layout);
        public void Suspend() => _inner.Suspend();
        public void Resume() => _inner.Resume();
        public bool TryRoutePointer(
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
            double localCssY) =>
            _inner.TryRoutePointer(
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
        public bool TryRouteKey(
            long sequence,
            WindowsCaptureKeyEventKind kind,
            int virtualKey,
            int scanCode,
            bool extended,
            bool repeat) =>
            _inner.TryRouteKey(sequence, kind, virtualKey, scanCode, extended, repeat);
        public HostOwnedCapturedSurfaceSessionSnapshot GetSnapshot() => _inner.GetSnapshot();
        public void Close() => _inner.Close();
        public void Dispose() => _inner.Dispose();
    }
}

/// <summary>
/// Owns the Host-side identity and lifetime of captured Windows app surfaces.
///
/// The web document never selects an HWND and never chooses a generation. The Host bridge
/// must first resolve its opaque native session ID to an already-correlated source HWND;
/// this manager then assigns a monotonically increasing generation, prevents duplicate HWND
/// ownership, and routes only exact-generation input. There is deliberately no anchored or
/// external-window fallback anywhere in this type.
/// </summary>
public sealed class HostOwnedCapturedSurfaceSessionManager : IDisposable
{
    private static readonly Regex SessionIdPattern = new(
        "^native-[a-f0-9]{24}$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private readonly object _sync = new();
    private readonly IntPtr _cloudOsOwnerWindowHandle;
    private readonly ICapturedSurfaceRuntimeSessionFactory _factory;
    private readonly Dictionary<string, ManagedSession> _sessions = new(StringComparer.Ordinal);
    private readonly Dictionary<IntPtr, string> _sessionIdBySourceWindow = new();
    private readonly HashSet<string> _attachInProgress = new(StringComparer.Ordinal);
    private int _nextGeneration;
    private bool _disposed;

    public HostOwnedCapturedSurfaceSessionManager(IntPtr cloudOsOwnerWindowHandle)
        : this(cloudOsOwnerWindowHandle, new HostOwnedCapturedSurfaceSessionFactory())
    {
    }

    public HostOwnedCapturedSurfaceSessionManager(
        IntPtr cloudOsOwnerWindowHandle,
        ICapturedSurfaceRuntimeSessionFactory factory)
    {
        if (cloudOsOwnerWindowHandle == IntPtr.Zero)
            throw new ArgumentException("CloudOS owner HWND is required.", nameof(cloudOsOwnerWindowHandle));
        _cloudOsOwnerWindowHandle = cloudOsOwnerWindowHandle;
        _factory = factory ?? throw new ArgumentNullException(nameof(factory));
    }

    public HostOwnedCapturedSurfaceManagedSnapshot Attach(
        string sessionId,
        IntPtr alreadyCorrelatedSourceWindowHandle,
        WindowsCapturePresentationLayout initialLayout)
    {
        ValidateSessionId(sessionId);
        if (alreadyCorrelatedSourceWindowHandle == IntPtr.Zero)
            throw new ArgumentException("A correlated source HWND is required.", nameof(alreadyCorrelatedSourceWindowHandle));
        ArgumentNullException.ThrowIfNull(initialLayout);
        initialLayout.Validate();

        int generation;
        lock (_sync)
        {
            ThrowIfDisposed();
            if (_sessions.ContainsKey(sessionId))
                throw Error("CAPTURE_SESSION_ALREADY_ATTACHED", "The native session already owns a captured surface.");
            if (_attachInProgress.Contains(sessionId))
                throw Error("CAPTURE_ATTACH_IN_PROGRESS", "The native session capture attach is already in progress.");
            if (_sessionIdBySourceWindow.ContainsKey(alreadyCorrelatedSourceWindowHandle))
                throw Error("CAPTURE_SOURCE_ALREADY_ATTACHED", "The correlated source HWND is already owned by another captured surface.");

            generation = checked(++_nextGeneration);
            _attachInProgress.Add(sessionId);
        }

        ICapturedSurfaceRuntimeSession? runtime = null;
        try
        {
            runtime = _factory.Create(
                _cloudOsOwnerWindowHandle,
                alreadyCorrelatedSourceWindowHandle,
                sessionId,
                generation,
                initialLayout);
            if (runtime.Generation != generation || runtime.SourceWindowHandle != alreadyCorrelatedSourceWindowHandle)
                throw Error("CAPTURE_RUNTIME_IDENTITY_MISMATCH", "Captured runtime did not preserve the Host-assigned identity.");

            runtime.Start();

            lock (_sync)
            {
                ThrowIfDisposed();
                if (_sessions.ContainsKey(sessionId) || _sessionIdBySourceWindow.ContainsKey(alreadyCorrelatedSourceWindowHandle))
                    throw Error("CAPTURE_ATTACH_RACE", "Captured surface identity changed while attach was starting.");

                _sessions.Add(sessionId, new ManagedSession(generation, runtime));
                _sessionIdBySourceWindow.Add(alreadyCorrelatedSourceWindowHandle, sessionId);
                _attachInProgress.Remove(sessionId);
                runtime = null;
                return ToManagedSnapshot(_sessions[sessionId].Runtime.GetSnapshot());
            }
        }
        catch
        {
            lock (_sync) _attachInProgress.Remove(sessionId);
            if (runtime is not null)
            {
                try { runtime.Close(); }
                catch (Exception error) when (error is not OutOfMemoryException) { }
            }
            throw;
        }
    }

    public HostOwnedCapturedSurfaceManagedSnapshot ApplyLayout(
        string sessionId,
        WindowsCapturePresentationLayout layout)
    {
        ArgumentNullException.ThrowIfNull(layout);
        layout.Validate();
        var runtime = GetRuntime(sessionId, generation: null);
        runtime.ApplyLayout(layout);
        return ToManagedSnapshot(runtime.GetSnapshot());
    }

    public HostOwnedCapturedSurfaceManagedSnapshot Suspend(string sessionId)
    {
        var runtime = GetRuntime(sessionId, generation: null);
        runtime.Suspend();
        return ToManagedSnapshot(runtime.GetSnapshot());
    }

    public HostOwnedCapturedSurfaceManagedSnapshot Resume(string sessionId)
    {
        var runtime = GetRuntime(sessionId, generation: null);
        runtime.Resume();
        return ToManagedSnapshot(runtime.GetSnapshot());
    }

    public bool TryRoutePointer(
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
        var runtime = GetRuntime(sessionId, generation);
        return runtime.TryRoutePointer(
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

    public bool TryRouteKey(
        string sessionId,
        int generation,
        long sequence,
        WindowsCaptureKeyEventKind kind,
        int virtualKey,
        int scanCode,
        bool extended,
        bool repeat)
    {
        var runtime = GetRuntime(sessionId, generation);
        return runtime.TryRouteKey(sequence, kind, virtualKey, scanCode, extended, repeat);
    }

    public HostOwnedCapturedSurfaceManagedSnapshot GetSnapshot(string sessionId)
    {
        var runtime = GetRuntime(sessionId, generation: null);
        return ToManagedSnapshot(runtime.GetSnapshot());
    }

    public IReadOnlyList<HostOwnedCapturedSurfaceManagedSnapshot> GetSnapshots()
    {
        ICapturedSurfaceRuntimeSession[] runtimes;
        lock (_sync)
        {
            ThrowIfDisposed();
            runtimes = _sessions.Values.Select(entry => entry.Runtime).ToArray();
        }

        return runtimes.Select(runtime => ToManagedSnapshot(runtime.GetSnapshot())).ToArray();
    }

    public bool Detach(string sessionId)
    {
        ValidateSessionId(sessionId);
        ICapturedSurfaceRuntimeSession? runtime = null;
        lock (_sync)
        {
            ThrowIfDisposed();
            if (!_sessions.Remove(sessionId, out var entry)) return false;
            runtime = entry.Runtime;
            _sessionIdBySourceWindow.Remove(runtime.SourceWindowHandle);
        }

        runtime.Close();
        return true;
    }

    public void DetachAll()
    {
        ICapturedSurfaceRuntimeSession[] runtimes;
        lock (_sync)
        {
            ThrowIfDisposed();
            runtimes = _sessions.Values.Select(entry => entry.Runtime).ToArray();
            _sessions.Clear();
            _sessionIdBySourceWindow.Clear();
            _attachInProgress.Clear();
        }

        foreach (var runtime in runtimes)
        {
            try { runtime.Close(); }
            catch (Exception error) when (error is not OutOfMemoryException) { }
        }
    }

    public void Dispose()
    {
        ICapturedSurfaceRuntimeSession[] runtimes;
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true;
            runtimes = _sessions.Values.Select(entry => entry.Runtime).ToArray();
            _sessions.Clear();
            _sessionIdBySourceWindow.Clear();
            _attachInProgress.Clear();
        }

        foreach (var runtime in runtimes)
        {
            try { runtime.Close(); }
            catch (Exception error) when (error is not OutOfMemoryException) { }
        }
    }

    public static bool IsValidSessionId(string? sessionId) =>
        sessionId is not null && SessionIdPattern.IsMatch(sessionId);

    private ICapturedSurfaceRuntimeSession GetRuntime(string sessionId, int? generation)
    {
        ValidateSessionId(sessionId);
        lock (_sync)
        {
            ThrowIfDisposed();
            if (!_sessions.TryGetValue(sessionId, out var entry))
                throw Error("CAPTURE_SESSION_NOT_FOUND", "Captured surface session does not exist.");
            if (generation.HasValue && generation.Value != entry.Generation)
                throw Error("CAPTURE_STALE_GENERATION", "Captured surface generation is stale or invalid.");
            return entry.Runtime;
        }
    }

    private static HostOwnedCapturedSurfaceManagedSnapshot ToManagedSnapshot(
        HostOwnedCapturedSurfaceSessionSnapshot snapshot) =>
        new(
            snapshot.SurfaceId,
            snapshot.Generation,
            snapshot.State,
            snapshot.Capture.FrameCount,
            snapshot.Surface.AcceptedFrames,
            snapshot.Surface.Presentation.DroppedFrameCount,
            snapshot.Capture.HasFrames,
            snapshot.State == HostOwnedCapturedSurfaceSessionState.Active &&
                snapshot.Surface.Presentation.Layout?.Visible == true &&
                snapshot.SourceWindowAlive &&
                string.IsNullOrWhiteSpace(snapshot.Failure),
            snapshot.SourceWindowAlive,
            snapshot.Failure ?? snapshot.Capture.Failure ?? snapshot.Surface.LastPresenterFailure);

    private static void ValidateSessionId(string sessionId)
    {
        if (!IsValidSessionId(sessionId))
            throw Error("CAPTURE_SESSION_ID_INVALID", "Captured surface session ID is invalid.");
    }

    private static CapturedSurfaceSessionManagerException Error(string code, string message) => new(code, message);

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(HostOwnedCapturedSurfaceSessionManager));
    }

    private sealed record ManagedSession(int Generation, ICapturedSurfaceRuntimeSession Runtime);
}
