using System.Runtime.InteropServices;
using CloudOS.WindowsCapture;

namespace CloudOS.WindowsCapture.Presenter;

public enum HostOwnedCapturedSurfaceSessionState
{
    Created,
    Active,
    Suspended,
    Faulted,
    Closed
}

public sealed record HostOwnedCapturedSurfaceSessionSnapshot(
    string SurfaceId,
    int Generation,
    long SourceWindowHandle,
    long PresentationWindowHandle,
    HostOwnedCapturedSurfaceSessionState State,
    WindowsCaptureSnapshot Capture,
    WindowsCaptureSurfaceCoordinatorSnapshot Surface,
    WindowsCaptureInputRoutingSnapshot Input,
    bool SourceWindowAlive,
    string? Failure);

/// <summary>
/// Product-candidate composition for one already-correlated Windows HWND.
///
/// Security boundary intentionally remains outside this class: the Host must prove the
/// process/HWND belongs to the tracked launch generation before constructing a session.
/// This type never launches a process, never reparents a foreign HWND and never falls back
/// to an external/anchored window. It only composes WGC -> Host-owned D3D presentation ->
/// targeted input for an HWND that has already passed the Host's process boundary.
/// </summary>
public sealed class HostOwnedCapturedSurfaceSession : IDisposable
{
    private const int HealthPollMilliseconds = 250;

    private readonly object _sync = new();
    private readonly IntPtr _sourceWindowHandle;
    private readonly HostOwnedCaptureSurfacePresenter _presenter;
    private readonly WindowsCaptureSurfaceCoordinator _surface;
    private readonly WindowsCaptureSession _capture;
    private readonly WindowsCaptureInputGate _targetedInputGate;
    private readonly WindowsCaptureTargetedInputInjector _targetedInjector;
    private readonly WindowsCaptureInputRouter _inputRouter;
    private readonly Timer _healthTimer;
    private HostOwnedCapturedSurfaceSessionState _state = HostOwnedCapturedSurfaceSessionState.Created;
    private WindowsCapturePresentationLayout _layout;
    private string? _failure;
    private bool _disposed;

    public HostOwnedCapturedSurfaceSession(
        IntPtr cloudOsOwnerWindowHandle,
        IntPtr sourceWindowHandle,
        string surfaceId,
        int generation,
        WindowsCapturePresentationLayout initialLayout,
        WindowsFrameHealthOptions? frameHealthOptions = null)
    {
        if (cloudOsOwnerWindowHandle == IntPtr.Zero)
            throw new ArgumentException("CloudOS owner HWND is required.", nameof(cloudOsOwnerWindowHandle));
        if (sourceWindowHandle == IntPtr.Zero || !IsWindow(sourceWindowHandle))
            throw new ArgumentException("A live, already-correlated source HWND is required.", nameof(sourceWindowHandle));
        ArgumentException.ThrowIfNullOrWhiteSpace(surfaceId);
        if (generation <= 0) throw new ArgumentOutOfRangeException(nameof(generation));
        ArgumentNullException.ThrowIfNull(initialLayout);
        initialLayout.Validate();

        _sourceWindowHandle = sourceWindowHandle;
        _layout = initialLayout;
        _presenter = new HostOwnedCaptureSurfacePresenter(cloudOsOwnerWindowHandle);
        _surface = new WindowsCaptureSurfaceCoordinator(surfaceId, generation, _presenter);

        try
        {
            // Construction validates CreateForWindow/D3D/frame-pool/session before a
            // presentation HWND is created by Bind. Capture does not start yet.
            _capture = new WindowsCaptureSession(
                sourceWindowHandle,
                WindowsCaptureTargetKind.Window,
                WindowsCaptureItemFactoryKind.RawActivationFactory,
                WindowsCaptureItemProjectionKind.MarshalInterfaceFromAbi,
                WindowsCaptureAbiLifetimeKind.HoldUntilSessionDispose,
                frameHealthOptions,
                frameSink: _surface);

            _surface.Bind(initialLayout);

            _targetedInputGate = new WindowsCaptureInputGate(generation);
            _targetedInjector = new WindowsCaptureTargetedInputInjector(
                sourceWindowHandle,
                _targetedInputGate);
            _inputRouter = new WindowsCaptureInputRouter(
                generation,
                new TargetedInputAdapter(_targetedInjector));

            _healthTimer = new Timer(
                static state => ((HostOwnedCapturedSurfaceSession)state!).PollHealth(),
                this,
                Timeout.Infinite,
                Timeout.Infinite);
        }
        catch
        {
            _surface.Dispose();
            throw;
        }
    }

    public string SurfaceId => _surface.SurfaceId;
    public int Generation => _surface.Generation;
    public IntPtr SourceWindowHandle => _sourceWindowHandle;
    public IntPtr PresentationWindowHandle => _presenter.PresentationWindowHandle;

    public void Start()
    {
        lock (_sync)
        {
            ThrowIfDisposed();
            if (_state != HostOwnedCapturedSurfaceSessionState.Created)
                throw InvalidTransition(nameof(Start));
        }

        try
        {
            _surface.Activate();
            _capture.Start();

            lock (_sync)
            {
                if (_state == HostOwnedCapturedSurfaceSessionState.Faulted)
                    throw new InvalidOperationException("Captured surface faulted while starting.");
                _state = HostOwnedCapturedSurfaceSessionState.Active;
                SetInputActiveLocked(_layout.Visible);
                _healthTimer.Change(HealthPollMilliseconds, HealthPollMilliseconds);
            }
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            TransitionToFault(
                WindowsCapturePresentationFaultKind.CaptureLost,
                $"Captured app session failed to start: {error.Message}");
            throw;
        }
    }

    public void ApplyLayout(WindowsCapturePresentationLayout layout)
    {
        ArgumentNullException.ThrowIfNull(layout);
        layout.Validate();
        PollHealth();

        lock (_sync)
        {
            ThrowIfDisposed();
            if (_state is HostOwnedCapturedSurfaceSessionState.Faulted or HostOwnedCapturedSurfaceSessionState.Closed)
                throw InvalidTransition(nameof(ApplyLayout));
        }

        try
        {
            _surface.ApplyLayout(layout);
            lock (_sync)
            {
                _layout = layout;
                if (_state == HostOwnedCapturedSurfaceSessionState.Active)
                    SetInputActiveLocked(layout.Visible);
            }
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            TransitionToFault(
                WindowsCapturePresentationFaultKind.RendererUnavailable,
                $"Captured surface layout failed: {error.Message}");
            throw;
        }
    }

    public void Suspend()
    {
        PollHealth();
        lock (_sync)
        {
            ThrowIfDisposed();
            if (_state != HostOwnedCapturedSurfaceSessionState.Active)
                throw InvalidTransition(nameof(Suspend));
            SetInputActiveLocked(false);
        }

        try
        {
            _surface.Suspend();
            lock (_sync) _state = HostOwnedCapturedSurfaceSessionState.Suspended;
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            TransitionToFault(
                WindowsCapturePresentationFaultKind.RendererUnavailable,
                $"Captured surface suspend failed: {error.Message}");
            throw;
        }
    }

    public void Resume()
    {
        PollHealth();
        lock (_sync)
        {
            ThrowIfDisposed();
            if (_state != HostOwnedCapturedSurfaceSessionState.Suspended)
                throw InvalidTransition(nameof(Resume));
        }

        try
        {
            _surface.Activate();
            lock (_sync)
            {
                _state = HostOwnedCapturedSurfaceSessionState.Active;
                SetInputActiveLocked(_layout.Visible);
            }
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            TransitionToFault(
                WindowsCapturePresentationFaultKind.RendererUnavailable,
                $"Captured surface resume failed: {error.Message}");
            throw;
        }
    }

    public WindowsCaptureInputAdmission AdmitInput(long sequence)
    {
        PollHealth();
        return _targetedInputGate.Admit(Generation, sequence);
    }

    public WindowsCaptureInputInjectionResult InjectPointer(WindowsCapturePointerInput input)
    {
        ArgumentNullException.ThrowIfNull(input);
        PollHealth();
        if (input.Generation != Generation)
            throw new InvalidOperationException(
                $"Pointer input generation does not match session generation. session={Generation}; input={input.Generation}.");
        return _targetedInjector.InjectPointer(input);
    }

    public WindowsCaptureInputInjectionResult InjectKey(WindowsCaptureKeyInput input)
    {
        ArgumentNullException.ThrowIfNull(input);
        PollHealth();
        if (input.Generation != Generation)
            throw new InvalidOperationException(
                $"Key input generation does not match session generation. session={Generation}; input={input.Generation}.");
        return _targetedInjector.InjectKey(input);
    }

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
        double localCssY)
    {
        PollHealth();
        if (!CanAcceptInput()) return false;

        var capture = _capture.GetSnapshot();
        if (!capture.HasFrames) return false;
        if (!WindowsCaptureSourceInputGeometry.TryMeasure(
                _sourceWindowHandle,
                capture.Width,
                capture.Height,
                out var clientGeometry) ||
            clientGeometry is null)
        {
            return false;
        }

        var surfaceGeometry = WindowsCaptureInputGeometry.FullFrame(
            capture.Width,
            capture.Height,
            surfaceCssWidth,
            surfaceCssHeight);

        return _inputRouter.TryRoutePointer(
            sequence,
            Generation,
            kind,
            button,
            wheelDelta,
            shift,
            control,
            alt,
            surfaceGeometry,
            clientGeometry,
            localCssX,
            localCssY);
    }

    public bool TryRouteKey(
        long sequence,
        WindowsCaptureKeyEventKind kind,
        int virtualKey,
        int scanCode,
        bool extended,
        bool repeat)
    {
        PollHealth();
        if (!CanAcceptInput()) return false;

        return _inputRouter.TryRouteKey(new WindowsCaptureKeyInput(
            sequence,
            Generation,
            kind,
            virtualKey,
            scanCode,
            extended,
            repeat));
    }

    public HostOwnedCapturedSurfaceSessionSnapshot GetSnapshot()
    {
        PollHealth();
        lock (_sync)
        {
            return new HostOwnedCapturedSurfaceSessionSnapshot(
                SurfaceId,
                Generation,
                _sourceWindowHandle.ToInt64(),
                PresentationWindowHandle.ToInt64(),
                _state,
                _capture.GetSnapshot(),
                _surface.GetSnapshot(),
                _inputRouter.GetSnapshot(),
                IsWindow(_sourceWindowHandle),
                _failure);
        }
    }

    public void Close()
    {
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true;
            _state = HostOwnedCapturedSurfaceSessionState.Closed;
            SetInputActiveLocked(false);
        }

        _healthTimer.Change(Timeout.Infinite, Timeout.Infinite);
        _healthTimer.Dispose();

        // Stop frame callbacks before tearing down the native presentation HWND/device.
        _capture.Dispose();
        _surface.Dispose();
    }

    public void Dispose() => Close();

    private void PollHealth()
    {
        WindowsCapturePresentationFaultKind? faultKind = null;
        string? message = null;

        lock (_sync)
        {
            if (_disposed || _state is HostOwnedCapturedSurfaceSessionState.Faulted or HostOwnedCapturedSurfaceSessionState.Closed)
                return;
        }

        if (!IsWindow(_sourceWindowHandle))
        {
            faultKind = WindowsCapturePresentationFaultKind.SourceLost;
            message = "The correlated source HWND no longer exists.";
        }
        else
        {
            var capture = _capture.GetSnapshot();
            if (!string.IsNullOrWhiteSpace(capture.Failure))
            {
                faultKind = WindowsCapturePresentationFaultKind.CaptureLost;
                message = $"Windows capture reported a terminal frame failure: {capture.Failure}";
            }
        }

        if (faultKind.HasValue && message is not null)
            TransitionToFault(faultKind.Value, message);
    }

    private void TransitionToFault(WindowsCapturePresentationFaultKind kind, string message)
    {
        lock (_sync)
        {
            if (_disposed || _state is HostOwnedCapturedSurfaceSessionState.Faulted or HostOwnedCapturedSurfaceSessionState.Closed)
                return;
            _state = HostOwnedCapturedSurfaceSessionState.Faulted;
            _failure = message;
            SetInputActiveLocked(false);
            _healthTimer.Change(Timeout.Infinite, Timeout.Infinite);
        }

        try
        {
            _surface.Fail(kind, message);
        }
        catch (ObjectDisposedException)
        {
            // Concurrent Close already established the stronger terminal boundary.
        }
    }

    private bool CanAcceptInput()
    {
        lock (_sync)
        {
            return !_disposed &&
                   _state == HostOwnedCapturedSurfaceSessionState.Active &&
                   _layout.Visible;
        }
    }

    private void SetInputActiveLocked(bool active)
    {
        _inputRouter.SetActive(active);
        _targetedInputGate.SetActive(active);
    }

    private InvalidOperationException InvalidTransition(string operation) =>
        new($"Captured surface operation '{operation}' is invalid while surface '{SurfaceId}' generation {Generation} is {_state}.");

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(HostOwnedCapturedSurfaceSession));
    }

    private sealed class TargetedInputAdapter : IWindowsCaptureInputInjector
    {
        private readonly WindowsCaptureTargetedInputInjector _inner;

        public TargetedInputAdapter(WindowsCaptureTargetedInputInjector inner)
        {
            _inner = inner;
        }

        public void InjectPointer(WindowsCapturePointerInput input)
        {
            var result = _inner.InjectPointer(input);
            EnsureDelivered(result, "pointer");
        }

        public void InjectKey(WindowsCaptureKeyInput input)
        {
            var result = _inner.InjectKey(input);
            EnsureDelivered(result, "keyboard");
        }

        private static void EnsureDelivered(WindowsCaptureInputInjectionResult result, string kind)
        {
            if (result.Delivered) return;
            throw new InvalidOperationException(
                $"Targeted {kind} injection was not delivered. status={result.Status}; rejection={result.Rejection}; failure={result.Failure ?? "<none>"}.");
        }
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr windowHandle);
}
