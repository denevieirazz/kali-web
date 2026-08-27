namespace CloudOS.WindowsCapture;

public interface IWindowsCaptureNativePresenter : IDisposable
{
    void Bind(WindowsCapturePresentationLayout layout);
    void ApplyLayout(WindowsCapturePresentationLayout layout);
    void Suspend();
    void Resume();
    void Present(WindowsCaptureFrameEnvelope frame);
}

public sealed record WindowsCaptureSurfaceCoordinatorSnapshot(
    WindowsCapturePresentationSnapshot Presentation,
    long AcceptedFrames,
    long RejectedFrames,
    string? LastPresenterFailure);

/// <summary>
/// Owns the product-level relationship between WGC frame delivery and a Host-owned
/// native presenter. It contains no cross-process parenting and no JavaScript pixel
/// transport. A presenter failure is terminal and transitions the surface fail-closed.
/// </summary>
public sealed class WindowsCaptureSurfaceCoordinator : IWindowsCaptureFrameSink, IDisposable
{
    private readonly object _sync = new();
    private readonly IWindowsCaptureNativePresenter _presenter;
    private readonly WindowsCapturePresentationLifecycle _lifecycle;
    private long _acceptedFrames;
    private long _rejectedFrames;
    private string? _lastPresenterFailure;
    private bool _disposed;

    public WindowsCaptureSurfaceCoordinator(
        string surfaceId,
        int generation,
        IWindowsCaptureNativePresenter presenter)
    {
        _presenter = presenter ?? throw new ArgumentNullException(nameof(presenter));
        _lifecycle = new WindowsCapturePresentationLifecycle(surfaceId, generation);
    }

    public string SurfaceId => _lifecycle.SurfaceId;
    public int Generation => _lifecycle.Generation;

    public void Bind(WindowsCapturePresentationLayout layout)
    {
        ThrowIfDisposed();
        layout.Validate();
        try
        {
            _presenter.Bind(layout);
            _lifecycle.Bind(layout);
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            FailPresenter("bind", error);
            throw;
        }
    }

    public void Activate()
    {
        ThrowIfDisposed();
        try
        {
            _presenter.Resume();
            _lifecycle.Activate();
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            FailPresenter("activate", error);
            throw;
        }
    }

    public void ApplyLayout(WindowsCapturePresentationLayout layout)
    {
        ThrowIfDisposed();
        layout.Validate();
        try
        {
            _presenter.ApplyLayout(layout);
            _lifecycle.ApplyLayout(layout);
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            FailPresenter("layout", error);
            throw;
        }
    }

    public void Suspend()
    {
        ThrowIfDisposed();
        try
        {
            _presenter.Suspend();
            _lifecycle.Suspend();
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            FailPresenter("suspend", error);
            throw;
        }
    }

    /// <summary>
    /// Transitions the presentation surface to a terminal fail-closed state because a
    /// non-presenter boundary (capture, source identity, device/security orchestration)
    /// was lost. The last frame is hidden best-effort before the fault is published.
    /// No overlay/external-window fallback is attempted.
    /// </summary>
    public void Fail(WindowsCapturePresentationFaultKind kind, string message)
    {
        ThrowIfDisposed();
        if (kind == WindowsCapturePresentationFaultKind.None)
            throw new ArgumentOutOfRangeException(nameof(kind));
        if (string.IsNullOrWhiteSpace(message))
            throw new ArgumentException("Fault message is required.", nameof(message));

        var current = _lifecycle.GetSnapshot();
        if (current.IsTerminal) return;

        try
        {
            if (current.State is WindowsCapturePresentationState.Bound or
                WindowsCapturePresentationState.Active or
                WindowsCapturePresentationState.Suspended)
            {
                _presenter.Suspend();
            }
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            lock (_sync) _lastPresenterFailure = $"{error.GetType().Name}: {error.Message}";
            _lifecycle.Fail(
                WindowsCapturePresentationFaultKind.RendererUnavailable,
                $"Native presenter failed while hiding a faulted surface: {error.Message}");
            return;
        }

        _lifecycle.Fail(kind, message);
    }

    public void OnFrame(WindowsCaptureFrameEnvelope frame)
    {
        ThrowIfDisposed();
        frame.Validate();
        var snapshot = _lifecycle.GetSnapshot();
        if (snapshot.State != WindowsCapturePresentationState.Active || snapshot.Layout?.Visible != true)
        {
            lock (_sync) _rejectedFrames++;
            _lifecycle.RecordDroppedFrame();
            return;
        }

        try
        {
            _presenter.Present(frame);
            _lifecycle.RecordPresentedFrame(frame.CapturedAtUtc);
            lock (_sync) _acceptedFrames++;
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            lock (_sync)
            {
                _rejectedFrames++;
                _lastPresenterFailure = $"{error.GetType().Name}: {error.Message}";
            }
            _lifecycle.Fail(
                WindowsCapturePresentationFaultKind.RendererUnavailable,
                $"Native presenter failed while consuming frame {frame.FrameNumber}: {error.Message}");
            throw;
        }
    }

    public WindowsCaptureSurfaceCoordinatorSnapshot GetSnapshot()
    {
        lock (_sync)
        {
            return new WindowsCaptureSurfaceCoordinatorSnapshot(
                _lifecycle.GetSnapshot(),
                _acceptedFrames,
                _rejectedFrames,
                _lastPresenterFailure);
        }
    }

    public void Close()
    {
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true;
        }

        _lifecycle.Close();
        _presenter.Dispose();
    }

    public void Dispose() => Close();

    private void FailPresenter(string stage, Exception error)
    {
        lock (_sync) _lastPresenterFailure = $"{error.GetType().Name}: {error.Message}";
        var current = _lifecycle.GetSnapshot();
        if (!current.IsTerminal)
        {
            _lifecycle.Fail(
                WindowsCapturePresentationFaultKind.RendererUnavailable,
                $"Native presenter failed during {stage}: {error.Message}");
        }
    }

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(WindowsCaptureSurfaceCoordinator));
    }
}
