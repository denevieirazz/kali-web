namespace CloudOS.WindowsCapture;

public sealed record WindowsCaptureClientGeometry(
    int SourcePixelWidth,
    int SourcePixelHeight,
    int CaptureScreenX,
    int CaptureScreenY,
    int CapturePixelWidth,
    int CapturePixelHeight,
    int ClientScreenX,
    int ClientScreenY,
    int ClientPixelWidth,
    int ClientPixelHeight)
{
    public WindowsCaptureClientGeometry Validate()
    {
        if (SourcePixelWidth is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(SourcePixelWidth));
        if (SourcePixelHeight is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(SourcePixelHeight));
        if (CapturePixelWidth is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(CapturePixelWidth));
        if (CapturePixelHeight is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(CapturePixelHeight));
        if (ClientPixelWidth is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(ClientPixelWidth));
        if (ClientPixelHeight is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(ClientPixelHeight));
        return this;
    }
}

public sealed record WindowsCaptureClientPointerMapping(
    int SourcePixelX,
    int SourcePixelY,
    int ScreenPixelX,
    int ScreenPixelY,
    int ClientPixelX,
    int ClientPixelY);

/// <summary>
/// Converts a pixel from the captured texture into the source HWND client area.
/// Geometry must be measured in physical screen pixels (for example DWM extended
/// frame bounds plus ClientToScreen/GetClientRect). Pixels landing on title bars,
/// resize borders or shadows are rejected instead of being guessed.
/// </summary>
public static class WindowsCaptureClientInputMapper
{
    public static bool TryMapSourcePixel(
        WindowsCaptureClientGeometry geometry,
        int sourcePixelX,
        int sourcePixelY,
        out WindowsCaptureClientPointerMapping? mapping)
    {
        ArgumentNullException.ThrowIfNull(geometry);
        geometry.Validate();
        mapping = null;

        if (sourcePixelX < 0 || sourcePixelY < 0 || sourcePixelX >= geometry.SourcePixelWidth || sourcePixelY >= geometry.SourcePixelHeight)
            return false;

        var normalizedX = (sourcePixelX + 0.5) / geometry.SourcePixelWidth;
        var normalizedY = (sourcePixelY + 0.5) / geometry.SourcePixelHeight;
        var screenX = geometry.CaptureScreenX + (int)Math.Floor(normalizedX * geometry.CapturePixelWidth);
        var screenY = geometry.CaptureScreenY + (int)Math.Floor(normalizedY * geometry.CapturePixelHeight);
        var clientX = screenX - geometry.ClientScreenX;
        var clientY = screenY - geometry.ClientScreenY;

        if (clientX < 0 || clientY < 0 || clientX >= geometry.ClientPixelWidth || clientY >= geometry.ClientPixelHeight)
            return false;

        mapping = new WindowsCaptureClientPointerMapping(
            sourcePixelX,
            sourcePixelY,
            screenX,
            screenY,
            clientX,
            clientY);
        return true;
    }
}

public enum WindowsCapturePointerEventKind
{
    Move,
    ButtonDown,
    ButtonUp,
    Wheel
}

public enum WindowsCapturePointerButton
{
    None,
    Left,
    Right,
    Middle
}

public sealed record WindowsCapturePointerInput(
    long Sequence,
    int Generation,
    WindowsCapturePointerEventKind Kind,
    WindowsCapturePointerButton Button,
    int ClientPixelX,
    int ClientPixelY,
    int WheelDelta,
    bool Shift,
    bool Control,
    bool Alt)
{
    public WindowsCapturePointerInput Validate()
    {
        if (Sequence <= 0) throw new ArgumentOutOfRangeException(nameof(Sequence));
        if (Generation <= 0) throw new ArgumentOutOfRangeException(nameof(Generation));
        if (ClientPixelX is < 0 or > 32767) throw new ArgumentOutOfRangeException(nameof(ClientPixelX));
        if (ClientPixelY is < 0 or > 32767) throw new ArgumentOutOfRangeException(nameof(ClientPixelY));
        if (Kind == WindowsCapturePointerEventKind.Wheel && WheelDelta == 0)
            throw new ArgumentOutOfRangeException(nameof(WheelDelta));
        if (Kind != WindowsCapturePointerEventKind.Wheel && WheelDelta != 0)
            throw new ArgumentOutOfRangeException(nameof(WheelDelta));
        if (Kind is WindowsCapturePointerEventKind.ButtonDown or WindowsCapturePointerEventKind.ButtonUp)
        {
            if (Button == WindowsCapturePointerButton.None) throw new ArgumentOutOfRangeException(nameof(Button));
        }
        else if (Button != WindowsCapturePointerButton.None)
        {
            throw new ArgumentOutOfRangeException(nameof(Button));
        }
        return this;
    }
}

public enum WindowsCaptureKeyEventKind
{
    KeyDown,
    KeyUp
}

public sealed record WindowsCaptureKeyInput(
    long Sequence,
    int Generation,
    WindowsCaptureKeyEventKind Kind,
    int VirtualKey,
    int ScanCode,
    bool Extended,
    bool Repeat)
{
    public WindowsCaptureKeyInput Validate()
    {
        if (Sequence <= 0) throw new ArgumentOutOfRangeException(nameof(Sequence));
        if (Generation <= 0) throw new ArgumentOutOfRangeException(nameof(Generation));
        if (VirtualKey is < 1 or > 255) throw new ArgumentOutOfRangeException(nameof(VirtualKey));
        if (ScanCode is < 0 or > 0x1FF) throw new ArgumentOutOfRangeException(nameof(ScanCode));
        return this;
    }
}
