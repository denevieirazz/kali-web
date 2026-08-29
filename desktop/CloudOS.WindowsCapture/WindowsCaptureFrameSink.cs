using Windows.Graphics.DirectX.Direct3D11;

namespace CloudOS.WindowsCapture;

/// <summary>
/// Synchronous native frame handoff used by WindowsCaptureSession while the
/// Direct3D11CaptureFrame is still alive. Implementations must copy or consume
/// the GPU resource before returning; they must never retain the WinRT surface
/// past the callback and must never marshal pixels through JavaScript.
/// </summary>
public interface IWindowsCaptureFrameSink
{
    void OnFrame(WindowsCaptureFrameEnvelope frame);
}

public sealed record WindowsCaptureFrameEnvelope(
    IDirect3DSurface Surface,
    long FrameNumber,
    int PixelWidth,
    int PixelHeight,
    DateTimeOffset CapturedAtUtc)
{
    public WindowsCaptureFrameEnvelope Validate()
    {
        ArgumentNullException.ThrowIfNull(Surface);
        if (FrameNumber <= 0) throw new ArgumentOutOfRangeException(nameof(FrameNumber));
        if (PixelWidth is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(PixelWidth));
        if (PixelHeight is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(PixelHeight));
        return this;
    }
}

public sealed record WindowsCaptureFrameSinkSnapshot(
    long DeliveredFrames,
    long FailedFrames,
    DateTimeOffset? LastDeliveredAtUtc,
    string? LastFailure);

internal sealed class WindowsCaptureFrameSinkDispatcher
{
    private readonly object _sync = new();
    private readonly IWindowsCaptureFrameSink _sink;
    private long _deliveredFrames;
    private long _failedFrames;
    private DateTimeOffset? _lastDeliveredAtUtc;
    private string? _lastFailure;

    public WindowsCaptureFrameSinkDispatcher(IWindowsCaptureFrameSink sink)
    {
        _sink = sink ?? throw new ArgumentNullException(nameof(sink));
    }

    public void TryDeliver(WindowsCaptureFrameEnvelope frame)
    {
        frame.Validate();
        try
        {
            _sink.OnFrame(frame);
            lock (_sync)
            {
                _deliveredFrames++;
                _lastDeliveredAtUtc = frame.CapturedAtUtc;
            }
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            lock (_sync)
            {
                _failedFrames++;
                _lastFailure = $"{error.GetType().Name}: {error.Message}";
            }
        }
    }

    public WindowsCaptureFrameSinkSnapshot GetSnapshot()
    {
        lock (_sync)
        {
            return new WindowsCaptureFrameSinkSnapshot(
                _deliveredFrames,
                _failedFrames,
                _lastDeliveredAtUtc,
                _lastFailure);
        }
    }
}
