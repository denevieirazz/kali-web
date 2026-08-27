using System.Runtime.InteropServices;
using Windows.Graphics;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;

namespace CloudOS.WindowsCapture;

public enum WindowsCaptureTargetKind
{
    Window,
    Monitor
}

public sealed record WindowsCaptureSnapshot(
    long FrameCount,
    int Width,
    int Height,
    int ResizeCount,
    int EmptyFrameCount,
    int InitialItemWidth,
    int InitialItemHeight,
    int InitialBufferWidth,
    int InitialBufferHeight,
    string InitialSizeSource,
    DateTimeOffset? FirstFrameAtUtc,
    DateTimeOffset? LastFrameAtUtc,
    string? Failure)
{
    public bool HasFrames => FrameCount > 0 && Width > 0 && Height > 0;
}

public sealed class WindowsCaptureSession : IDisposable
{
    private const uint DwmwaExtendedFrameBounds = 9;

    private readonly object _sync = new();
    private readonly IDirect3DDevice _device;
    private readonly GraphicsCaptureItem _item;
    private readonly Direct3D11CaptureFramePool _framePool;
    private readonly GraphicsCaptureSession _session;
    private readonly int _initialItemWidth;
    private readonly int _initialItemHeight;
    private readonly int _initialBufferWidth;
    private readonly int _initialBufferHeight;
    private readonly string _initialSizeSource;
    private long _frameCount;
    private int _width;
    private int _height;
    private int _resizeCount;
    private int _emptyFrameCount;
    private DateTimeOffset? _firstFrameAtUtc;
    private DateTimeOffset? _lastFrameAtUtc;
    private string? _failure;
    private bool _started;
    private bool _disposed;

    public WindowsCaptureSession(IntPtr targetHandle, WindowsCaptureTargetKind targetKind = WindowsCaptureTargetKind.Window)
    {
        if (!GraphicsCaptureSession.IsSupported())
            throw new PlatformNotSupportedException("Windows.Graphics.Capture is not supported in this Windows session.");
        if (targetHandle == IntPtr.Zero)
            throw new ArgumentException("The capture target handle must be non-zero.", nameof(targetHandle));
        if (targetKind == WindowsCaptureTargetKind.Window && !IsWindow(targetHandle))
            throw new ArgumentException("The capture target must be a live HWND.", nameof(targetHandle));

        TargetHandle = targetHandle;
        TargetKind = targetKind;

        InitialCaptureSize? nativeInitial = targetKind switch
        {
            WindowsCaptureTargetKind.Window => TryResolveNativeWindowSize(targetHandle),
            WindowsCaptureTargetKind.Monitor => TryResolveNativeMonitorSize(targetHandle),
            _ => throw new ArgumentOutOfRangeException(nameof(targetKind))
        };

        _item = targetKind switch
        {
            WindowsCaptureTargetKind.Window => WindowsCaptureInterop.CreateItemForWindow(targetHandle),
            WindowsCaptureTargetKind.Monitor => WindowsCaptureInterop.CreateItemForMonitor(targetHandle),
            _ => throw new ArgumentOutOfRangeException(nameof(targetKind))
        };

        var itemSize = _item.Size;
        _initialItemWidth = itemSize.Width;
        _initialItemHeight = itemSize.Height;

        var initial = ResolveInitialBufferSize(targetHandle, targetKind, itemSize, nativeInitial);
        _initialBufferWidth = initial.Size.Width;
        _initialBufferHeight = initial.Size.Height;
        _initialSizeSource = initial.Source;

        _device = WindowsCaptureInterop.CreateDirect3DDevice();
        _width = initial.Size.Width;
        _height = initial.Size.Height;
        _framePool = Direct3D11CaptureFramePool.CreateFreeThreaded(
            _device,
            DirectXPixelFormat.B8G8R8A8UIntNormalized,
            3,
            initial.Size);

        try
        {
            _session = _framePool.CreateCaptureSession(_item);
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            _framePool.Dispose();
            _device.Dispose();
            var displayName = TryGetDisplayName(_item);
            throw new InvalidOperationException(
                $"CreateCaptureSession failed for {targetKind}; handle=0x{targetHandle.ToInt64():X}; " +
                $"item={itemSize.Width}x{itemSize.Height}; buffer={initial.Size.Width}x{initial.Size.Height} via {initial.Source}; " +
                $"displayName={displayName ?? "<unavailable>"}; inner=0x{error.HResult:X8} {error.Message}",
                error);
        }

        _framePool.FrameArrived += OnFrameArrived;
    }

    public IntPtr TargetHandle { get; }
    public WindowsCaptureTargetKind TargetKind { get; }

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
                _emptyFrameCount,
                _initialItemWidth,
                _initialItemHeight,
                _initialBufferWidth,
                _initialBufferHeight,
                _initialSizeSource,
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
            SizeInt32 newSize = default;
            using (var frame = sender.TryGetNextFrame())
            {
                if (frame is null) return;
                newSize = frame.ContentSize;
                if (newSize.Width <= 0 || newSize.Height <= 0)
                {
                    lock (_sync) _emptyFrameCount++;
                    return;
                }

                var now = DateTimeOffset.UtcNow;
                lock (_sync)
                {
                    _frameCount++;
                    _firstFrameAtUtc ??= now;
                    _lastFrameAtUtc = now;
                    if (newSize.Width != _width || newSize.Height != _height)
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

    private static InitialCaptureSize ResolveInitialBufferSize(
        IntPtr targetHandle,
        WindowsCaptureTargetKind targetKind,
        SizeInt32 itemSize,
        InitialCaptureSize? nativeInitial)
    {
        if (IsValidSize(itemSize))
            return new InitialCaptureSize(itemSize, "graphics-capture-item");

        if (nativeInitial is { } native)
            return native;

        InitialCaptureSize? retry = targetKind switch
        {
            WindowsCaptureTargetKind.Window => TryResolveNativeWindowSize(targetHandle, "post-wgc-"),
            WindowsCaptureTargetKind.Monitor => TryResolveNativeMonitorSize(targetHandle, "post-wgc-"),
            _ => null
        };
        if (retry is { } postWgc)
            return postWgc;

        throw new InvalidOperationException(
            $"The capture target has no usable initial size. kind={targetKind}; item={itemSize.Width}x{itemSize.Height}; handle=0x{targetHandle.ToInt64():X}.");
    }

    private static InitialCaptureSize? TryResolveNativeWindowSize(
        IntPtr windowHandle,
        string sourcePrefix = "pre-wgc-")
    {
        if (DwmGetWindowAttribute(
                windowHandle,
                DwmwaExtendedFrameBounds,
                out var frameBounds,
                (uint)Marshal.SizeOf<NativeRect>()) == 0 &&
            TryConvert(frameBounds, out var dwmSize))
        {
            return new InitialCaptureSize(dwmSize, sourcePrefix + "dwm-extended-frame-bounds");
        }

        if (GetWindowRect(windowHandle, out var windowBounds) && TryConvert(windowBounds, out var windowSize))
            return new InitialCaptureSize(windowSize, sourcePrefix + "get-window-rect");

        return null;
    }

    private static InitialCaptureSize? TryResolveNativeMonitorSize(
        IntPtr monitorHandle,
        string sourcePrefix = "pre-wgc-")
    {
        var info = new MonitorInfo { Size = (uint)Marshal.SizeOf<MonitorInfo>() };
        if (GetMonitorInfo(monitorHandle, ref info) && TryConvert(info.Monitor, out var monitorSize))
            return new InitialCaptureSize(monitorSize, sourcePrefix + "get-monitor-info");
        return null;
    }

    private static string? TryGetDisplayName(GraphicsCaptureItem item)
    {
        try { return item.DisplayName; }
        catch { return null; }
    }

    private static bool IsValidSize(SizeInt32 size) => size.Width > 0 && size.Height > 0;

    private static bool TryConvert(NativeRect rectangle, out SizeInt32 size)
    {
        var width = (long)rectangle.Right - rectangle.Left;
        var height = (long)rectangle.Bottom - rectangle.Top;
        if (width is <= 0 or > int.MaxValue || height is <= 0 or > int.MaxValue)
        {
            size = default;
            return false;
        }

        size = new SizeInt32 { Width = (int)width, Height = (int)height };
        return true;
    }

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(WindowsCaptureSession));
    }

    private readonly record struct InitialCaptureSize(SizeInt32 Size, string Source);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo
    {
        public uint Size;
        public NativeRect Monitor;
        public NativeRect Work;
        public uint Flags;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr windowHandle);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr windowHandle, out NativeRect rectangle);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(IntPtr monitorHandle, ref MonitorInfo monitorInfo);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(
        IntPtr windowHandle,
        uint attribute,
        out NativeRect value,
        uint valueSize);
}
