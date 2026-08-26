using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;

namespace CloudOS.WindowsCapture;

public sealed record WindowsCaptureSnapshot(
    long FrameCount,
    int Width,
    int Height,
    int ResizeCount,
    DateTimeOffset? FirstFrameAtUtc,
    DateTimeOffset? LastFrameAtUtc,
    string? Failure)
{
    public bool HasFrames => FrameCount > 0 && Width > 0 && Height > 0;
}

public sealed class WindowsCaptureSession : IDisposable
{
    private readonly object _sync = new();
    private readonly IDirect3DDevice _device;
    private readonly GraphicsCaptureItem _item;
    private readonly Direct3D11CaptureFramePool _framePool;
    private readonly GraphicsCaptureSession _session;
    private long _frameCount;
    private int _width;
    private int _height;
    private int _resizeCount;
    private DateTimeOffset? _firstFrameAtUtc;
    private DateTimeOffset? _lastFrameAtUtc;
    private string? _failure;
    private bool _started;
    private bool _disposed;

    public WindowsCaptureSession(IntPtr windowHandle)
    {
        if (!GraphicsCaptureSession.IsSupported())
            throw new PlatformNotSupportedException("Windows.Graphics.Capture is not supported in this Windows session.");

        WindowHandle = windowHandle;
        _item = WindowsCaptureInterop.CreateItemForWindow(windowHandle);
        if (_item.Size.Width <= 0 || _item.Size.Height <= 0)
            throw new InvalidOperationException("The capture target reported an empty content size.");

        _device = WindowsCaptureInterop.CreateDirect3DDevice();
        _width = _item.Size.Width;
        _height = _item.Size.Height;
        _framePool = Direct3D11CaptureFramePool.CreateFreeThreaded(
            _device,
            DirectXPixelFormat.B8G8R8A8UIntNormalized,
            3,
            _item.Size);
        _session = _framePool.CreateCaptureSession(_item);
        _framePool.FrameArrived += OnFrameArrived;
    }

    public IntPtr WindowHandle { get; }

    public void Start()
    {
        ThrowIfDisposed();
        lock (_sync)
        {
            if (_started) return;
            _session.StartCapture();
            _started = true;
        }
    }

    public WindowsCaptureSnapshot GetSnapshot()
    {
        lock (_sync)
        {
            return new WindowsCaptureSnapshot(
                _frameCount,
                _width,
                _height,
                _resizeCount,
                _firstFrameAtUtc,
                _lastFrameAtUtc,
                _failure);
        }
    }

    public async Task<WindowsCaptureSnapshot> WaitForFramesAsync(
        int minimumFrameCount,
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        if (minimumFrameCount <= 0) throw new ArgumentOutOfRangeException(nameof(minimumFrameCount));
        if (timeout <= TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(timeout));

        Start();
        var deadline = DateTimeOffset.UtcNow + timeout;
        while (DateTimeOffset.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var snapshot = GetSnapshot();
            if (snapshot.Failure is not null || snapshot.FrameCount >= minimumFrameCount) return snapshot;
            await Task.Delay(25, cancellationToken).ConfigureAwait(false);
        }
        return GetSnapshot();
    }

    private void OnFrameArrived(Direct3D11CaptureFramePool sender, object args)
    {
        try
        {
            var resize = false;
            Windows.Graphics.SizeInt32 newSize = default;
            using (var frame = sender.TryGetNextFrame())
            {
                if (frame is null) return;
                newSize = frame.ContentSize;
                var now = DateTimeOffset.UtcNow;
                lock (_sync)
                {
                    _frameCount++;
                    _firstFrameAtUtc ??= now;
                    _lastFrameAtUtc = now;
                    if (newSize.Width > 0 && newSize.Height > 0 &&
                        (newSize.Width != _width || newSize.Height != _height))
                    {
                        _width = newSize.Width;
                        _height = newSize.Height;
                        _resizeCount++;
                        resize = true;
                    }
                }
            }

            if (resize)
            {
                sender.Recreate(
                    _device,
                    DirectXPixelFormat.B8G8R8A8UIntNormalized,
                    3,
                    newSize);
            }
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            lock (_sync) _failure ??= $"{error.GetType().Name}: {error.Message}";
        }
    }

    public void Dispose()
    {
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true;
        }

        _framePool.FrameArrived -= OnFrameArrived;
        _session.Dispose();
        _framePool.Dispose();
        _device.Dispose();
    }

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(WindowsCaptureSession));
    }
}
