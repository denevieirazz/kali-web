using CloudOS.WindowsCapture;

namespace CloudOS.WindowsCapture.Presenter;

public sealed record HostOwnedCaptureSurfacePointerEvent(
    WindowsCapturePointerEventKind Kind,
    WindowsCapturePointerButton Button,
    int LocalPixelX,
    int LocalPixelY,
    int WheelDelta,
    bool Shift,
    bool Control,
    bool Alt);

/// <summary>
/// Pure Win32 mouse-message decoder for the Host-owned presentation HWND. It never accepts
/// or produces a foreign HWND or screen destination. WM_MOUSEWHEEL coordinates must be
/// converted to presentation-client pixels by the owning window before calling this decoder.
/// </summary>
public static class HostOwnedCaptureSurfacePointerDecoder
{
    public const uint WmMouseMove = 0x0200;
    public const uint WmLeftButtonDown = 0x0201;
    public const uint WmLeftButtonUp = 0x0202;
    public const uint WmRightButtonDown = 0x0204;
    public const uint WmRightButtonUp = 0x0205;
    public const uint WmMiddleButtonDown = 0x0207;
    public const uint WmMiddleButtonUp = 0x0208;
    public const uint WmMouseWheel = 0x020A;

    private const uint MkShift = 0x0004;
    private const uint MkControl = 0x0008;

    public static bool TryDecode(
        uint message,
        IntPtr wParam,
        int localPixelX,
        int localPixelY,
        bool alt,
        out HostOwnedCaptureSurfacePointerEvent? pointerEvent)
    {
        pointerEvent = null;
        if (localPixelX is < -32768 or > 32767 || localPixelY is < -32768 or > 32767)
            return false;

        WindowsCapturePointerEventKind kind;
        WindowsCapturePointerButton button;
        switch (message)
        {
            case WmMouseMove:
                kind = WindowsCapturePointerEventKind.Move;
                button = WindowsCapturePointerButton.None;
                break;
            case WmLeftButtonDown:
                kind = WindowsCapturePointerEventKind.ButtonDown;
                button = WindowsCapturePointerButton.Left;
                break;
            case WmLeftButtonUp:
                kind = WindowsCapturePointerEventKind.ButtonUp;
                button = WindowsCapturePointerButton.Left;
                break;
            case WmRightButtonDown:
                kind = WindowsCapturePointerEventKind.ButtonDown;
                button = WindowsCapturePointerButton.Right;
                break;
            case WmRightButtonUp:
                kind = WindowsCapturePointerEventKind.ButtonUp;
                button = WindowsCapturePointerButton.Right;
                break;
            case WmMiddleButtonDown:
                kind = WindowsCapturePointerEventKind.ButtonDown;
                button = WindowsCapturePointerButton.Middle;
                break;
            case WmMiddleButtonUp:
                kind = WindowsCapturePointerEventKind.ButtonUp;
                button = WindowsCapturePointerButton.Middle;
                break;
            case WmMouseWheel:
                kind = WindowsCapturePointerEventKind.Wheel;
                button = WindowsCapturePointerButton.None;
                break;
            default:
                return false;
        }

        var raw = unchecked((uint)wParam.ToInt64());
        var wheelDelta = kind == WindowsCapturePointerEventKind.Wheel
            ? unchecked((short)((raw >> 16) & 0xFFFF))
            : 0;
        if (kind == WindowsCapturePointerEventKind.Wheel && wheelDelta == 0)
            return false;

        pointerEvent = new HostOwnedCaptureSurfacePointerEvent(
            kind,
            button,
            localPixelX,
            localPixelY,
            wheelDelta,
            (raw & MkShift) != 0,
            (raw & MkControl) != 0,
            alt);
        return true;
    }
}
