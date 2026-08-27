namespace CloudOS.WindowsCapture;

public enum WindowsCapturePresentationState
{
    Created,
    Bound,
    Active,
    Suspended,
    Faulted,
    Closed
}

public enum WindowsCapturePresentationFaultKind
{
    None,
    CaptureLost,
    SourceLost,
    RendererUnavailable,
    DeviceLost,
    InvalidLayout,
    SecurityBoundaryLost,
    InternalError
}

public sealed record WindowsCapturePresentationLayout(
    long Revision,
    int PixelX,
    int PixelY,
    int PixelWidth,
    int PixelHeight,
    double DpiScaleX,
    double DpiScaleY,
    bool Visible)
{
    public WindowsCapturePresentationLayout Validate()
    {
        if (Revision <= 0) throw new ArgumentOutOfRangeException(nameof(Revision));
        if (PixelWidth is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(PixelWidth));
        if (PixelHeight is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(PixelHeight));
        if (PixelX is < -131072 or > 131072) throw new ArgumentOutOfRangeException(nameof(PixelX));
        if (PixelY is < -131072 or > 131072) throw new ArgumentOutOfRangeException(nameof(PixelY));
        if (DpiScaleX is < 0.25 or > 8.0 || double.IsNaN(DpiScaleX) || double.IsInfinity(DpiScaleX))
            throw new ArgumentOutOfRangeException(nameof(DpiScaleX));
        if (DpiScaleY is < 0.25 or > 8.0 || double.IsNaN(DpiScaleY) || double.IsInfinity(DpiScaleY))
            throw new ArgumentOutOfRangeException(nameof(DpiScaleY));
        return this;
    }
}

public sealed record WindowsCapturePresentationFault(
    WindowsCapturePresentationFaultKind Kind,
    string Message,
    DateTimeOffset AtUtc);

public sealed record WindowsCapturePresentationSnapshot(
    string SurfaceId,
    int Generation,
    WindowsCapturePresentationState State,
    WindowsCapturePresentationLayout? Layout,
    long PresentedFrameCount,
    long DroppedFrameCount,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? ActivatedAtUtc,
    DateTimeOffset? LastPresentedFrameAtUtc,
    WindowsCapturePresentationFault? Fault)
{
    public bool IsTerminal => State is WindowsCapturePresentationState.Faulted or WindowsCapturePresentationState.Closed;
}

/// <summary>
/// Pure lifecycle contract for a CloudOS-owned captured-surface presentation target.
/// It deliberately contains no HWND parenting and no web-bridge transport. A concrete GPU
/// presenter (DirectComposition/swap-chain or another proven native surface) must obey this
/// state machine and copy/retain capture resources within native code.
/// </summary>
public sealed class WindowsCapturePresentationLifecycle
{
    private readonly object _sync = new();
    private readonly DateTimeOffset _createdAtUtc;
    private WindowsCapturePresentationState _state = WindowsCapturePresentationState.Created;
    private WindowsCapturePresentationLayout? _layout;
    private long _presentedFrameCount;
    private long _droppedFrameCount;
    private DateTimeOffset? _activatedAtUtc;
    private DateTimeOffset? _lastPresentedFrameAtUtc;
    private WindowsCapturePresentationFault? _fault;

    public WindowsCapturePresentationLifecycle(string surfaceId, int generation)
    {
        if (string.IsNullOrWhiteSpace(surfaceId)) throw new ArgumentException("Surface ID is required.", nameof(surfaceId));
        if (surfaceId.Length > 128) throw new ArgumentOutOfRangeException(nameof(surfaceId));
        if (generation <= 0) throw new ArgumentOutOfRangeException(nameof(generation));

        SurfaceId = surfaceId;
        Generation = generation;
        _createdAtUtc = DateTimeOffset.UtcNow;
    }

    public string SurfaceId { get; }
    public int Generation { get; }

    public WindowsCapturePresentationSnapshot GetSnapshot()
    {
        lock (_sync)
        {
            return new WindowsCapturePresentationSnapshot(
                SurfaceId,
                Generation,
                _state,
                _layout,
                _presentedFrameCount,
                _droppedFrameCount,
                _createdAtUtc,
                _activatedAtUtc,
                _lastPresentedFrameAtUtc,
                _fault);
        }
    }

    public void Bind(WindowsCapturePresentationLayout layout)
    {
        ArgumentNullException.ThrowIfNull(layout);
        layout.Validate();
        lock (_sync)
        {
            RequireState(WindowsCapturePresentationState.Created, nameof(Bind));
            _layout = layout;
            _state = WindowsCapturePresentationState.Bound;
        }
    }

    public void Activate()
    {
        lock (_sync)
        {
            if (_state is not (WindowsCapturePresentationState.Bound or WindowsCapturePresentationState.Suspended))
                throw InvalidTransition(nameof(Activate));
            if (_layout is null) throw new InvalidOperationException("Presentation surface has no layout.");
            _state = WindowsCapturePresentationState.Active;
            _activatedAtUtc ??= DateTimeOffset.UtcNow;
        }
    }

    public void ApplyLayout(WindowsCapturePresentationLayout layout)
    {
        ArgumentNullException.ThrowIfNull(layout);
        layout.Validate();
        lock (_sync)
        {
            RequireMutable(nameof(ApplyLayout));
            if (_state == WindowsCapturePresentationState.Created)
                throw InvalidTransition(nameof(ApplyLayout));
            if (_layout is not null && layout.Revision <= _layout.Revision)
                throw new InvalidOperationException(
                    $"Layout revision must increase monotonically. current={_layout.Revision}; requested={layout.Revision}.");
            _layout = layout;
        }
    }

    public void Suspend()
    {
        lock (_sync)
        {
            RequireState(WindowsCapturePresentationState.Active, nameof(Suspend));
            _state = WindowsCapturePresentationState.Suspended;
        }
    }

    public void RecordPresentedFrame(DateTimeOffset presentedAtUtc)
    {
        lock (_sync)
        {
            RequireState(WindowsCapturePresentationState.Active, nameof(RecordPresentedFrame));
            if (_layout is null || !_layout.Visible)
                throw new InvalidOperationException("A frame cannot be marked presented while the CloudOS surface is hidden.");
            if (_lastPresentedFrameAtUtc.HasValue && presentedAtUtc < _lastPresentedFrameAtUtc.Value)
                throw new InvalidOperationException("Presented-frame timestamps must be monotonic.");
            _presentedFrameCount++;
            _lastPresentedFrameAtUtc = presentedAtUtc;
        }
    }

    public void RecordDroppedFrame()
    {
        lock (_sync)
        {
            if (_state is not (WindowsCapturePresentationState.Active or WindowsCapturePresentationState.Suspended))
                throw InvalidTransition(nameof(RecordDroppedFrame));
            _droppedFrameCount++;
        }
    }

    public void Fail(WindowsCapturePresentationFaultKind kind, string message)
    {
        if (kind == WindowsCapturePresentationFaultKind.None)
            throw new ArgumentOutOfRangeException(nameof(kind));
        if (string.IsNullOrWhiteSpace(message)) throw new ArgumentException("Fault message is required.", nameof(message));
        lock (_sync)
        {
            if (_state == WindowsCapturePresentationState.Closed) throw InvalidTransition(nameof(Fail));
            if (_state == WindowsCapturePresentationState.Faulted) return;
            _fault = new WindowsCapturePresentationFault(kind, message, DateTimeOffset.UtcNow);
            _state = WindowsCapturePresentationState.Faulted;
        }
    }

    public void Close()
    {
        lock (_sync)
        {
            if (_state == WindowsCapturePresentationState.Closed) return;
            _state = WindowsCapturePresentationState.Closed;
        }
    }

    private void RequireMutable(string operation)
    {
        if (_state is WindowsCapturePresentationState.Faulted or WindowsCapturePresentationState.Closed)
            throw InvalidTransition(operation);
    }

    private void RequireState(WindowsCapturePresentationState expected, string operation)
    {
        if (_state != expected) throw InvalidTransition(operation);
    }

    private InvalidOperationException InvalidTransition(string operation) =>
        new($"Presentation operation '{operation}' is invalid while surface '{SurfaceId}' generation {Generation} is {_state}.");
}
