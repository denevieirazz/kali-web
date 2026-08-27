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

public sealed class WindowsCaptureSetupException : InvalidOperationException
{
    public WindowsCaptureSetupException(
        string stage,
        WindowsCaptureTargetKind targetKind,
        IntPtr targetHandle,
        WindowsCaptureItemFactoryKind itemFactoryKind,
        WindowsCaptureItemProjectionKind itemProjectionKind,
        WindowsCaptureAbiLifetimeKind abiLifetimeKind,
        string message,
        Exception innerException,
        int itemWidth = 0,
        int itemHeight = 0,
        int bufferWidth = 0,
        int bufferHeight = 0,
        string? initialSizeSource = null,
        string? displayName = null)
        : base(message, innerException)
    {
        Stage = stage;
        TargetKind = targetKind;
        TargetHandle = targetHandle;
        ItemFactoryKind = itemFactoryKind;
        ItemProjectionKind = itemProjectionKind;
        AbiLifetimeKind = abiLifetimeKind;
        ItemWidth = itemWidth;
        ItemHeight = itemHeight;
        BufferWidth = bufferWidth;
        BufferHeight = bufferHeight;
        InitialSizeSource = initialSizeSource;
        DisplayName = displayName;
    }

    public string Stage { get; }
    public WindowsCaptureTargetKind TargetKind { get; }
    public IntPtr TargetHandle { get; }
    public WindowsCaptureItemFactoryKind ItemFactoryKind { get; }
    public WindowsCaptureItemProjectionKind ItemProjectionKind { get; }
    public WindowsCaptureAbiLifetimeKind AbiLifetimeKind { get; }
    public int ItemWidth { get; }
    public int ItemHeight { get; }
    public int BufferWidth { get; }
    public int BufferHeight { get; }
    public string? InitialSizeSource { get; }
    public string? DisplayName { get; }
    public int NativeHResult => InnerException?.HResult ?? HResult;
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
    string ItemFactory,
    string ItemProjection,
    string AbiLifetime,
    bool HoldsAbiReference,
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
    private readonly WindowsCaptureItemLease _itemLease;
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

    public WindowsCaptureSession(
        IntPtr targetHandle,
        WindowsCaptureTargetKind targetKind = WindowsCaptureTargetKind.Window,
        WindowsCaptureItemFactoryKind itemFactoryKind = WindowsCaptureItemFactoryKind.RawActivationFactory,
        WindowsCaptureItemProjectionKind itemProjectionKind = WindowsCaptureItemProjectionKind.MarshalInterfaceFromAbi,
        WindowsCaptureAbiLifetimeKind abiLifetimeKind = WindowsCaptureAbiLifetimeKind.HoldUntilSessionDispose)
    {
        if (!GraphicsCaptureSession.IsSupported())
            throw new PlatformNotSupportedException("Windows.Graphics.Capture is not supported in this Windows session.");
        if (targetHandle == IntPtr.Zero)
            throw new ArgumentException("The capture target handle must be non-zero.", nameof(targetHandle));
        if (targetKind == WindowsCaptureTargetKind.Window && !IsWindow(targetHandle))
            throw new ArgumentException("The capture target must be a live HWND.", nameof(targetHandle));

        TargetHandle = targetHandle;
        TargetKind = targetKind;
        ItemFactoryKind = itemFactoryKind;
        ItemProjectionKind = itemProjectionKind;
        AbiLifetimeKind = abiLifetimeKind;

        InitialCaptureSize? nativeInitial = targetKind switch
        {
            WindowsCaptureTargetKind.Window => TryResolveNativeWindowSize(targetHandle),
            WindowsCaptureTargetKind.Monitor => TryResolveNativeMonitorSize(targetHandle),
            _ => throw new ArgumentOutOfRangeException(nameof(targetKind))
        };

        try
        {
            _itemLease = targetKind switch
            {
                WindowsCaptureTargetKind.Window => WindowsCaptureInterop.CreateItemForWindow(
                    targetHandle,
                    itemFactoryKind,
                    itemProjectionKind,
                    abiLifetimeKind),
                WindowsCaptureTargetKind.Monitor => WindowsCaptureInterop.CreateItemForMonitor(
                    targetHandle,
                    itemFactoryKind,
                    itemProjectionKind,
                    abiLifetimeKind),
                _ => throw new ArgumentOutOfRangeException(nameof(targetKind))
            };
            _item = _itemLease.Item;
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            throw SetupFailure(
                "item-factory",
                targetHandle,
                targetKind,
                itemFactoryKind,
                itemProjectionKind,
                abiLifetimeKind,
                error);
        }

        SizeInt32 itemSize;
        try
        {
            itemSize = _item.Size;
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            _itemLease.Dispose();
            throw SetupFailure(
                "item-metadata",
                targetHandle,
                targetKind,
                itemFactoryKind,
                itemProjectionKind,
                abiLifetimeKind,
                error);
        }

        _initialItemWidth = itemSize.Width;
        _initialItemHeight = itemSize.Height;

        InitialCaptureSize initial;
        try
        {
            initial = ResolveInitialBufferSize(targetHandle, targetKind, itemSize, nativeInitial);
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            var displayName = TryGetDisplayName(_item);
            _itemLease.Dispose();
            throw SetupFailure(
                "initial-size",
                targetHandle,
                targetKind,
                itemFactoryKind,
                itemProjectionKind,
                abiLifetimeKind,
                error,
                itemSize.Width,
                itemSize.Height,
                displayName: displayName);
        }

        _initialBufferWidth = initial.Size.Width;
        _initialBufferHeight = initial.Size.Height;
        _initialSizeSource = initial.Source;

        try
        {
            _device = WindowsCaptureInterop.CreateDirect3DDevice();
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            var displayName = TryGetDisplayName(_item);
            _itemLease.Dispose();
            throw SetupFailure(
                "d3d-device",
                targetHandle,
                targetKind,
                itemFactoryKind,
                itemProjectionKind,
                abiLifetimeKind,
                error,
                itemSize.Width,
                itemSize.Height,
                initial.Size.Width,
                initial.Size.Height,
                initial.Source,
                displayName);
        }

        _width = initial.Size.Width;
        _height = initial.Size.Height;

        try
        {
            _framePool = Direct3D11CaptureFramePool.CreateFreeThreaded(
                _device,
                DirectXPixelFormat.B8G8R8A8UIntNormalized,
                3,
                initial.Size);
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            var displayName = TryGetDisplayName(_item);
            _device.Dispose();
            _itemLease.Dispose();
            throw SetupFailure(
                "frame-pool",
                targetHandle,
                targetKind,
                itemFactoryKind,
                itemProjectionKind,
                abiLifetimeKind,
                error,
                itemSize.Width,
                itemSize.Height,
                initial.Size.Width,
                initial.Size.Height,
                initial.Source,
                displayName);
        }

        try
        {
            _session = _framePool.CreateCaptureSession(_item);
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            var displayName = TryGetDisplayName(_item);
            _framePool.Dispose();
            _device.Dispose();
            _itemLease.Dispose();
            throw SetupFailure(
                "capture-session",
                targetHandle,
                targetKind,
                itemFactoryKind,
                itemProjectionKind,
                abiLifetimeKind,
                error,
                itemSize.Width,
                itemSize.Height,
                initial.Size.Width,
                initial.Size.Height,
                initial.Source,
                displayName);
        }

        _framePool.FrameArrived += OnFrameArrived;
    }

    public IntPtr TargetHandle { get; }
    public WindowsCaptureTargetKind TargetKind { get; }
    public WindowsCaptureItemFactoryKind ItemFactoryKind { get; }
    public WindowsCaptureItemProjectionKind ItemProjectionKind { get; }
    public WindowsCaptureAbiLifetimeKind AbiLifetimeKind { get; }

    public void Start()
    {
        ThrowIfDisposed();
        lock (_sync)
        {
            if (_started) return;
            try
            {
                _session.StartCapture();
                _started = true;
            }
            catch (Exception error) when (error is not OutOfMemoryException)
            {
                throw SetupFailure(
                    "start-capture",
                    TargetHandle,
                    TargetKind,
                    ItemFactoryKind,
                    ItemProjectionKind,
                    AbiLifetimeKind,
                    error,
                    _initialItemWidth,
                    _initialItemHeight,
                    _initialBufferWidth,
                    _initialBufferHeight,
                    _initialSizeSource,
                    TryGetDisplayName(_item));
            }
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
                ItemFactoryKind.ToString(),
                ItemProjectionKind.ToString(),
                AbiLifetimeKind.ToString(),
                _itemLease.HoldsAbiReference,
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
        _itemLease.Dispose();
    }

    private static WindowsCaptureSetupException SetupFailure(
        string stage,
        IntPtr targetHandle,
        WindowsCaptureTargetKind targetKind,
        WindowsCaptureItemFactoryKind itemFactoryKind,
        WindowsCaptureItemProjectionKind itemProjectionKind,
        WindowsCaptureAbiLifetimeKind abiLifetimeKind,
        Exception error,
        int itemWidth = 0,
        int itemHeight = 0,
        int bufferWidth = 0,
        int bufferHeight = 0,
        string? initialSizeSource = null,
        string? displayName = null)
    {
        var message =
            $"Windows capture setup failed at {stage}; target={targetKind}; factory={itemFactoryKind}; " +
            $"projection={itemProjectionKind}; abiLifetime={abiLifetimeKind}; " +
            $"handle=0x{targetHandle.ToInt64():X}; item={itemWidth}x{itemHeight}; " +
            $"buffer={bufferWidth}x{bufferHeight}; source={initialSizeSource ?? "<none>"}; " +
            $"displayName={displayName ?? "<unavailable>"}; inner=0x{error.HResult:X8} {error.Message}";

        return new WindowsCaptureSetupException(
            stage,
            targetKind,
            targetHandle,
            itemFactoryKind,
            itemProjectionKind,
            abiLifetimeKind,
            message,
            error,
            itemWidth,
            itemHeight,
            bufferWidth,
            bufferHeight,
            initialSizeSource,
            displayName);
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
