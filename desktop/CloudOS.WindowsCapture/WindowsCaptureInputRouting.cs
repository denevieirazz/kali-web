namespace CloudOS.WindowsCapture;

public interface IWindowsCaptureInputInjector
{
    void InjectPointer(WindowsCapturePointerInput input);
    void InjectKey(WindowsCaptureKeyInput input);
}

public sealed record WindowsCaptureInputRoutingSnapshot(
    int Generation,
    long AcceptedEvents,
    long RejectedEvents,
    WindowsCaptureInputRejection LastRejection,
    string? LastFailure);

/// <summary>
/// Combines surface-coordinate mapping, source-window client mapping and replay/stale
/// generation protection before a platform injector can see an input event.
/// </summary>
public sealed class WindowsCaptureInputRouter
{
    private readonly object _sync = new();
    private readonly WindowsCaptureInputGate _gate;
    private readonly IWindowsCaptureInputInjector _injector;
    private long _acceptedEvents;
    private long _rejectedEvents;
    private WindowsCaptureInputRejection _lastRejection;
    private string? _lastFailure;

    public WindowsCaptureInputRouter(int generation, IWindowsCaptureInputInjector injector)
    {
        _gate = new WindowsCaptureInputGate(generation);
        _injector = injector ?? throw new ArgumentNullException(nameof(injector));
    }

    public int Generation => _gate.Generation;

    public void SetActive(bool active) => _gate.SetActive(active);

    public bool TryRoutePointer(
        long sequence,
        int generation,
        WindowsCapturePointerEventKind kind,
        WindowsCapturePointerButton button,
        int wheelDelta,
        bool shift,
        bool control,
        bool alt,
        WindowsCaptureInputGeometry surfaceGeometry,
        WindowsCaptureClientGeometry clientGeometry,
        double localCssX,
        double localCssY)
    {
        if (!WindowsCaptureInputMapper.TryMapPointer(surfaceGeometry, localCssX, localCssY, out var source) || source is null)
            return Reject(WindowsCaptureInputRejection.OutsideSurface, "Pointer is outside the visible captured surface.");
        if (!WindowsCaptureClientInputMapper.TryMapSourcePixel(clientGeometry, source.SourcePixelX, source.SourcePixelY, out var client) || client is null)
            return Reject(WindowsCaptureInputRejection.OutsideClientArea, "Pointer lands outside the source HWND client area.");

        var admission = _gate.Admit(generation, sequence);
        if (!admission.Allowed) return Reject(admission.Rejection, null);

        var input = new WindowsCapturePointerInput(
            sequence,
            generation,
            kind,
            button,
            client.ClientPixelX,
            client.ClientPixelY,
            wheelDelta,
            shift,
            control,
            alt).Validate();

        try
        {
            _injector.InjectPointer(input);
            lock (_sync)
            {
                _acceptedEvents++;
                _lastRejection = WindowsCaptureInputRejection.None;
                _lastFailure = null;
            }
            return true;
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            return Reject(WindowsCaptureInputRejection.InjectorFailed, $"{error.GetType().Name}: {error.Message}");
        }
    }

    public bool TryRouteKey(WindowsCaptureKeyInput input)
    {
        input.Validate();
        var admission = _gate.Admit(input.Generation, input.Sequence);
        if (!admission.Allowed) return Reject(admission.Rejection, null);
        try
        {
            _injector.InjectKey(input);
            lock (_sync)
            {
                _acceptedEvents++;
                _lastRejection = WindowsCaptureInputRejection.None;
                _lastFailure = null;
            }
            return true;
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            return Reject(WindowsCaptureInputRejection.InjectorFailed, $"{error.GetType().Name}: {error.Message}");
        }
    }

    public WindowsCaptureInputRoutingSnapshot GetSnapshot()
    {
        lock (_sync)
        {
            return new WindowsCaptureInputRoutingSnapshot(
                _gate.Generation,
                _acceptedEvents,
                _rejectedEvents,
                _lastRejection,
                _lastFailure);
        }
    }

    private bool Reject(WindowsCaptureInputRejection rejection, string? failure)
    {
        lock (_sync)
        {
            _rejectedEvents++;
            _lastRejection = rejection;
            _lastFailure = failure;
        }
        return false;
    }
}
