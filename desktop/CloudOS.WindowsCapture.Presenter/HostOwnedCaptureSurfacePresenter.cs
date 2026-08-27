using CloudOS.WindowsCapture;

namespace CloudOS.WindowsCapture.Presenter;

public sealed class HostOwnedCaptureSurfacePresenter : IWindowsCaptureNativePresenter
{
    private readonly object _sync = new();
    private readonly IntPtr _ownerWindowHandle;
    private HostOwnedCaptureSurfaceWindow? _window;
    private D3D11SwapChainFramePresenter? _gpuPresenter;
    private WindowsCapturePresentationLayout? _layout;
    private bool _disposed;

    public HostOwnedCaptureSurfacePresenter(IntPtr ownerWindowHandle)
    {
        if (ownerWindowHandle == IntPtr.Zero) throw new ArgumentException("CloudOS owner HWND is required.", nameof(ownerWindowHandle));
        _ownerWindowHandle = ownerWindowHandle;
    }

    public IntPtr PresentationWindowHandle
    {
        get
        {
            lock (_sync) return _window?.Handle ?? IntPtr.Zero;
        }
    }

    public void Bind(WindowsCapturePresentationLayout layout)
    {
        layout.Validate();
        lock (_sync)
        {
            ThrowIfDisposed();
            if (_window is not null) throw new InvalidOperationException("Presenter is already bound.");
            _window = new HostOwnedCaptureSurfaceWindow(_ownerWindowHandle, layout);
            _gpuPresenter = new D3D11SwapChainFramePresenter(_window.Handle);
            _layout = layout;
        }
    }

    public void ApplyLayout(WindowsCapturePresentationLayout layout)
    {
        layout.Validate();
        lock (_sync)
        {
            ThrowIfDisposed();
            var window = _window ?? throw new InvalidOperationException("Presenter is not bound.");
            window.ApplyLayout(layout);
            _layout = layout;
        }
    }

    public void Suspend()
    {
        lock (_sync)
        {
            ThrowIfDisposed();
            var window = _window ?? throw new InvalidOperationException("Presenter is not bound.");
            window.Hide();
        }
    }

    public void Resume()
    {
        lock (_sync)
        {
            ThrowIfDisposed();
            var window = _window ?? throw new InvalidOperationException("Presenter is not bound.");
            if (_layout?.Visible == true) window.Show();
        }
    }

    public void Present(WindowsCaptureFrameEnvelope frame)
    {
        frame.Validate();
        lock (_sync)
        {
            ThrowIfDisposed();
            var gpu = _gpuPresenter ?? throw new InvalidOperationException("Presenter is not bound.");
            if (_layout?.Visible != true) throw new InvalidOperationException("Presenter cannot present while surface is hidden.");
            gpu.Present(frame.Surface, frame.PixelWidth, frame.PixelHeight);
        }
    }

    public void Dispose()
    {
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true;
            _gpuPresenter?.Dispose();
            _gpuPresenter = null;
            _window?.Dispose();
            _window = null;
            _layout = null;
        }
    }

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(HostOwnedCaptureSurfacePresenter));
    }
}
