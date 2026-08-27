using System.ComponentModel;
using System.Runtime.InteropServices;
using CloudOS.WindowsCapture;

namespace CloudOS.WindowsCapture.Presenter;

/// <summary>
/// Delivers conventional Win32 mouse and keyboard messages directly to the exact
/// correlated source HWND. It never moves the global cursor and never uses SendInput.
/// Apps that require raw input or a foreground-only input path must fail qualification
/// as INPUT_UNSUPPORTED rather than silently switching to global injection.
/// </summary>
public sealed class Win32WindowMessageInputInjector : IWindowsCaptureInputInjector
{
    private const uint WmMouseMove = 0x0200;
    private const uint WmLeftButtonDown = 0x0201;
    private const uint WmLeftButtonUp = 0x0202;
    private const uint WmRightButtonDown = 0x0204;
    private const uint WmRightButtonUp = 0x0205;
    private const uint WmMiddleButtonDown = 0x0207;
    private const uint WmMiddleButtonUp = 0x0208;
    private const uint WmMouseWheel = 0x020A;
    private const uint WmKeyDown = 0x0100;
    private const uint WmKeyUp = 0x0101;
    private const int MkLButton = 0x0001;
    private const int MkRButton = 0x0002;
    private const int MkShift = 0x0004;
    private const int MkControl = 0x0008;
    private const int MkMButton = 0x0010;

    private readonly IntPtr _windowHandle;

    public Win32WindowMessageInputInjector(IntPtr windowHandle)
    {
        if (windowHandle == IntPtr.Zero || !IsWindow(windowHandle))
            throw new ArgumentException("A live source HWND is required.", nameof(windowHandle));
        _windowHandle = windowHandle;
    }

    public void InjectPointer(WindowsCapturePointerInput input)
    {
        input.Validate();
        EnsureLiveTarget();

        var message = input.Kind switch
        {
            WindowsCapturePointerEventKind.Move => WmMouseMove,
            WindowsCapturePointerEventKind.Wheel => WmMouseWheel,
            WindowsCapturePointerEventKind.ButtonDown when input.Button == WindowsCapturePointerButton.Left => WmLeftButtonDown,
            WindowsCapturePointerEventKind.ButtonUp when input.Button == WindowsCapturePointerButton.Left => WmLeftButtonUp,
            WindowsCapturePointerEventKind.ButtonDown when input.Button == WindowsCapturePointerButton.Right => WmRightButtonDown,
            WindowsCapturePointerEventKind.ButtonUp when input.Button == WindowsCapturePointerButton.Right => WmRightButtonUp,
            WindowsCapturePointerEventKind.ButtonDown when input.Button == WindowsCapturePointerButton.Middle => WmMiddleButtonDown,
            WindowsCapturePointerEventKind.ButtonUp when input.Button == WindowsCapturePointerButton.Middle => WmMiddleButtonUp,
            _ => throw new NotSupportedException("Unsupported pointer event for targeted Win32 injection.")
        };

        var keyState = 0;
        if (input.Shift) keyState |= MkShift;
        if (input.Control) keyState |= MkControl;
        if (input.Kind == WindowsCapturePointerEventKind.ButtonDown)
        {
            keyState |= input.Button switch
            {
                WindowsCapturePointerButton.Left => MkLButton,
                WindowsCapturePointerButton.Right => MkRButton,
                WindowsCapturePointerButton.Middle => MkMButton,
                _ => 0
            };
        }

        IntPtr wParam;
        IntPtr lParam;
        if (input.Kind == WindowsCapturePointerEventKind.Wheel)
        {
            var point = new NativePoint { X = input.ClientPixelX, Y = input.ClientPixelY };
            if (!ClientToScreen(_windowHandle, ref point))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "ClientToScreen failed while routing wheel input.");
            var wheelWord = unchecked((ushort)(short)input.WheelDelta);
            var packedWParam = (long)(uint)(keyState & 0xFFFF) | ((long)wheelWord << 16);
            wParam = new IntPtr(packedWParam);
            lParam = PackCoordinates(point.X, point.Y);
        }
        else
        {
            wParam = new IntPtr(keyState);
            lParam = PackCoordinates(input.ClientPixelX, input.ClientPixelY);
        }

        if (!PostMessageW(_windowHandle, message, wParam, lParam))
            throw new Win32Exception(Marshal.GetLastWin32Error(), $"PostMessageW failed for pointer message 0x{message:X4}.");
    }

    public void InjectKey(WindowsCaptureKeyInput input)
    {
        input.Validate();
        EnsureLiveTarget();

        var message = input.Kind == WindowsCaptureKeyEventKind.KeyDown ? WmKeyDown : WmKeyUp;
        uint bits = 1;
        bits |= (uint)(input.ScanCode & 0xFF) << 16;
        if (input.Extended) bits |= 1u << 24;
        if (input.Repeat || input.Kind == WindowsCaptureKeyEventKind.KeyUp) bits |= 1u << 30;
        if (input.Kind == WindowsCaptureKeyEventKind.KeyUp) bits |= 1u << 31;

        if (!PostMessageW(_windowHandle, message, new IntPtr(input.VirtualKey), new IntPtr(unchecked((int)bits))))
            throw new Win32Exception(Marshal.GetLastWin32Error(), $"PostMessageW failed for key message 0x{message:X4}.");
    }

    private void EnsureLiveTarget()
    {
        if (!IsWindow(_windowHandle)) throw new InvalidOperationException("Source HWND no longer exists.");
    }

    private static IntPtr PackCoordinates(int x, int y)
    {
        if (x is < short.MinValue or > short.MaxValue || y is < short.MinValue or > short.MaxValue)
            throw new ArgumentOutOfRangeException("Win32 message coordinates exceed signed 16-bit LPARAM range.");
        var packed = (uint)(ushort)(short)x | ((uint)(ushort)(short)y << 16);
        return new IntPtr(unchecked((int)packed));
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
    private static extern bool PostMessageW(IntPtr windowHandle, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ClientToScreen(IntPtr windowHandle, ref NativePoint point);
}
