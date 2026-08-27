namespace CloudOS.WindowsCapture;

public enum WindowsCaptureInputRejection
{
    None,
    SurfaceInactive,
    StaleGeneration,
    ReplayedSequence,
    OutsideSurface,
    OutsideClientArea,
    InjectorFailed
}

public sealed record WindowsCaptureInputAdmission(
    bool Allowed,
    WindowsCaptureInputRejection Rejection,
    long LastAcceptedSequence,
    int Generation);

/// <summary>
/// Fail-closed replay/staleness gate for captured-surface input. Each reopened surface
/// receives a new generation. Input sequence numbers must increase monotonically inside
/// that generation, so queued events from a previous surface can never target the new app.
/// </summary>
public sealed class WindowsCaptureInputGate
{
    private readonly object _sync = new();
    private readonly int _generation;
    private long _lastAcceptedSequence;
    private bool _active;

    public WindowsCaptureInputGate(int generation)
    {
        if (generation <= 0) throw new ArgumentOutOfRangeException(nameof(generation));
        _generation = generation;
    }

    public int Generation => _generation;

    public bool IsActive
    {
        get
        {
            lock (_sync) return _active;
        }
    }

    public void SetActive(bool active)
    {
        lock (_sync) _active = active;
    }

    public WindowsCaptureInputAdmission Admit(int generation, long sequence)
    {
        if (sequence <= 0) throw new ArgumentOutOfRangeException(nameof(sequence));
        lock (_sync)
        {
            if (!_active)
                return new WindowsCaptureInputAdmission(false, WindowsCaptureInputRejection.SurfaceInactive, _lastAcceptedSequence, _generation);
            if (generation != _generation)
                return new WindowsCaptureInputAdmission(false, WindowsCaptureInputRejection.StaleGeneration, _lastAcceptedSequence, _generation);
            if (sequence <= _lastAcceptedSequence)
                return new WindowsCaptureInputAdmission(false, WindowsCaptureInputRejection.ReplayedSequence, _lastAcceptedSequence, _generation);

            _lastAcceptedSequence = sequence;
            return new WindowsCaptureInputAdmission(true, WindowsCaptureInputRejection.None, _lastAcceptedSequence, _generation);
        }
    }

    public void ResetForDeactivation()
    {
        lock (_sync) _active = false;
    }
}
