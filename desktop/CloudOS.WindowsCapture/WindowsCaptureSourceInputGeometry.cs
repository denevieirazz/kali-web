using System.Runtime.InteropServices;

namespace CloudOS.WindowsCapture;

public static class WindowsCaptureSourceInputGeometry
{
    private const uint DwmwaExtendedFrameBounds = 9;

    public static bool TryMeasure(
        IntPtr windowHandle,
        int sourcePixelWidth,
        int sourcePixelHeight,
        out WindowsCaptureClientGeometry? geometry)
    {
        geometry = null;
        if (windowHandle == IntPtr.Zero || !IsWindow(windowHandle)) return false;
        if (sourcePixelWidth is < 1 or > 32768 || sourcePixelHeight is < 1 or > 32768) return false;

        NativeRect captureRect;
        if (DwmGetWindowAttribute(
                windowHandle,
                DwmwaExtendedFrameBounds,
                out captureRect,
                (uint)Marshal.SizeOf<NativeRect>()) != 0 ||
            captureRect.Right <= captureRect.Left || captureRect.Bottom <= captureRect.Top)
        {
            if (!GetWindowRect(windowHandle, out captureRect) ||
                captureRect.Right <= captureRect.Left || captureRect.Bottom <= captureRect.Top)
                return false;
        }

        if (!GetClientRect(windowHandle, out var clientRect)) return false;
        var clientWidth = clientRect.Right - clientRect.Left;
        var clientHeight = clientRect.Bottom - clientRect.Top;
        if (clientWidth <= 0 || clientHeight <= 0) return false;

        var clientOrigin = new NativePoint { X = 0, Y = 0 };
        if (!ClientToScreen(windowHandle, ref clientOrigin)) return false;

        var measured = new WindowsCaptureClientGeometry(
            SourcePixelWidth: sourcePixelWidth,
            SourcePixelHeight: sourcePixelHeight,
            CaptureScreenX: captureRect.Left,
            CaptureScreenY: captureRect.Top,
            CapturePixelWidth: captureRect.Right - captureRect.Left,
            CapturePixelHeight: captureRect.Bottom - captureRect.Top,
            ClientScreenX: clientOrigin.X,
            ClientScreenY: clientOrigin.Y,
            ClientPixelWidth: clientWidth,
            ClientPixelHeight: clientHeight);
        measured.Validate();
        geometry = measured;
        return true;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr windowHandle);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr windowHandle, out NativeRect rectangle);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetClientRect(IntPtr windowHandle, out NativeRect rectangle);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ClientToScreen(IntPtr windowHandle, ref NativePoint point);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr windowHandle, uint attribute, out NativeRect value, uint valueSize);
}
