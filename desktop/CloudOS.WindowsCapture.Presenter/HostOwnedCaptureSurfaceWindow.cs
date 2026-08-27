using System.ComponentModel;
using System.Runtime.InteropServices;
using CloudOS.WindowsCapture;

namespace CloudOS.WindowsCapture.Presenter;

/// <summary>
/// Same-process Win32 presentation HWND owned by the CloudOS Host. It is a tool window,
/// never a taskbar/Alt+Tab application window, and it never reparents the captured app's HWND.
/// </summary>
public sealed class HostOwnedCaptureSurfaceWindow : IDisposable
{
    private const string WindowClassName = "CloudOS.CapturedSurface.Presenter.v1";
    private const uint WsPopup = 0x80000000;
    private const uint WsClipChildren = 0x02000000;
    private const uint WsClipSiblings = 0x04000000;
    private const uint WsExToolWindow = 0x00000080;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpNoOwnerZOrder = 0x0200;
    private const int SwHide = 0;
    private const int SwShowNoActivate = 4;
    private static readonly IntPtr HwndTop = IntPtr.Zero;
    private static readonly object RegistrationSync = new();
    private static readonly WindowProcedureDelegate WindowProcedureInstance = HandleWindowMessage;
    private static bool _registered;

    private bool _disposed;

    public HostOwnedCaptureSurfaceWindow(IntPtr ownerWindowHandle, WindowsCapturePresentationLayout initialLayout)
    {
        if (ownerWindowHandle == IntPtr.Zero) throw new ArgumentException("Owner HWND is required.", nameof(ownerWindowHandle));
        initialLayout.Validate();
        EnsureWindowClass();

        var handle = CreateWindowExW(
            WsExToolWindow,
            WindowClassName,
            "CloudOS Captured Surface",
            WsPopup | WsClipChildren | WsClipSiblings,
            initialLayout.PixelX,
            initialLayout.PixelY,
            initialLayout.PixelWidth,
            initialLayout.PixelHeight,
            ownerWindowHandle,
            IntPtr.Zero,
            GetModuleHandleW(null),
            IntPtr.Zero);
        if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateWindowExW failed for captured-surface presenter.");

        Handle = handle;
        ApplyLayout(initialLayout);
    }

    public IntPtr Handle { get; private set; }

    public void ApplyLayout(WindowsCapturePresentationLayout layout)
    {
        ThrowIfDisposed();
        layout.Validate();
        if (!SetWindowPos(
                Handle,
                HwndTop,
                layout.PixelX,
                layout.PixelY,
                layout.PixelWidth,
                layout.PixelHeight,
                SwpNoActivate | SwpNoOwnerZOrder))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "SetWindowPos failed for captured-surface presenter.");
        }

        ShowWindow(Handle, layout.Visible ? SwShowNoActivate : SwHide);
    }

    public void Show()
    {
        ThrowIfDisposed();
        ShowWindow(Handle, SwShowNoActivate);
    }

    public void Hide()
    {
        ThrowIfDisposed();
        ShowWindow(Handle, SwHide);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        var handle = Handle;
        Handle = IntPtr.Zero;
        if (handle != IntPtr.Zero && !DestroyWindow(handle))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "DestroyWindow failed for captured-surface presenter.");
    }

    private static void EnsureWindowClass()
    {
        if (_registered) return;
        lock (RegistrationSync)
        {
            if (_registered) return;
            var module = GetModuleHandleW(null);
            var windowClass = new WindowClassEx
            {
                Size = (uint)Marshal.SizeOf<WindowClassEx>(),
                Instance = module,
                WindowProcedure = Marshal.GetFunctionPointerForDelegate(WindowProcedureInstance),
                ClassName = WindowClassName
            };
            var atom = RegisterClassExW(ref windowClass);
            if (atom == 0)
            {
                var error = Marshal.GetLastWin32Error();
                const int ErrorClassAlreadyExists = 1410;
                if (error != ErrorClassAlreadyExists)
                    throw new Win32Exception(error, "RegisterClassExW failed for captured-surface presenter.");
            }
            _registered = true;
        }
    }

    private static IntPtr HandleWindowMessage(IntPtr windowHandle, uint message, IntPtr wParam, IntPtr lParam) =>
        DefWindowProcW(windowHandle, message, wParam, lParam);

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(HostOwnedCaptureSurfaceWindow));
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate IntPtr WindowProcedureDelegate(IntPtr windowHandle, uint message, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WindowClassEx
    {
        public uint Size;
        public uint Style;
        public IntPtr WindowProcedure;
        public int ClassExtra;
        public int WindowExtra;
        public IntPtr Instance;
        public IntPtr Icon;
        public IntPtr Cursor;
        public IntPtr Background;
        public string? MenuName;
        public string ClassName;
        public IntPtr SmallIcon;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr GetModuleHandleW(string? moduleName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClassExW(ref WindowClassEx windowClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowExW(
        uint extendedStyle,
        string className,
        string windowName,
        uint style,
        int x,
        int y,
        int width,
        int height,
        IntPtr parentOrOwner,
        IntPtr menu,
        IntPtr instance,
        IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProcW(IntPtr windowHandle, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr windowHandle, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr windowHandle, int command);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyWindow(IntPtr windowHandle);
}
