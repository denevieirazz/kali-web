using CloudOS.WindowsCapture;
using CloudOS.WindowsCapture.Presenter;

var tests = new (string Name, Action Run)[]
{
    ("mouse move keeps local coordinates and modifiers", TestMove),
    ("button messages preserve exact button and transition", TestButtons),
    ("wheel delta is signed and local coordinates are Host supplied", TestWheel),
    ("unsupported and zero-delta messages fail closed", TestRejectedMessages),
};

var failures = new List<string>();
foreach (var test in tests)
{
    try
    {
        test.Run();
        Console.WriteLine($"PASS {test.Name}");
    }
    catch (Exception error)
    {
        var failure = $"{test.Name}: {error.GetType().Name}: {error.Message}";
        failures.Add(failure);
        Console.Error.WriteLine($"FAIL {failure}");
    }
}

if (failures.Count > 0)
{
    Console.Error.WriteLine($"PRESENTER_INPUT_CONTRACTS=FAIL count={failures.Count}");
    return 1;
}

Console.WriteLine($"PRESENTER_INPUT_CONTRACTS=PASS count={tests.Length}");
return 0;

static void TestMove()
{
    var wParam = new IntPtr(0x0004 | 0x0008);
    Require(
        HostOwnedCaptureSurfacePointerDecoder.TryDecode(
            HostOwnedCaptureSurfacePointerDecoder.WmMouseMove,
            wParam,
            123,
            456,
            alt: true,
            out var input),
        "move was rejected");
    Require(input is not null, "move result missing");
    Require(input.Kind == WindowsCapturePointerEventKind.Move, "wrong move kind");
    Require(input.Button == WindowsCapturePointerButton.None, "move unexpectedly carries a button");
    Require(input.LocalPixelX == 123 && input.LocalPixelY == 456, "move coordinates changed");
    Require(input.WheelDelta == 0, "move unexpectedly carries wheel delta");
    Require(input.Shift && input.Control && input.Alt, "move modifiers were not preserved");
}

static void TestButtons()
{
    var cases = new[]
    {
        (HostOwnedCaptureSurfacePointerDecoder.WmLeftButtonDown, WindowsCapturePointerEventKind.ButtonDown, WindowsCapturePointerButton.Left),
        (HostOwnedCaptureSurfacePointerDecoder.WmLeftButtonUp, WindowsCapturePointerEventKind.ButtonUp, WindowsCapturePointerButton.Left),
        (HostOwnedCaptureSurfacePointerDecoder.WmRightButtonDown, WindowsCapturePointerEventKind.ButtonDown, WindowsCapturePointerButton.Right),
        (HostOwnedCaptureSurfacePointerDecoder.WmRightButtonUp, WindowsCapturePointerEventKind.ButtonUp, WindowsCapturePointerButton.Right),
        (HostOwnedCaptureSurfacePointerDecoder.WmMiddleButtonDown, WindowsCapturePointerEventKind.ButtonDown, WindowsCapturePointerButton.Middle),
        (HostOwnedCaptureSurfacePointerDecoder.WmMiddleButtonUp, WindowsCapturePointerEventKind.ButtonUp, WindowsCapturePointerButton.Middle),
    };

    foreach (var item in cases)
    {
        Require(
            HostOwnedCaptureSurfacePointerDecoder.TryDecode(item.Item1, IntPtr.Zero, 10, 20, false, out var input),
            $"button message 0x{item.Item1:X} rejected");
        Require(input is not null, "button result missing");
        Require(input.Kind == item.Item2, $"wrong transition for 0x{item.Item1:X}");
        Require(input.Button == item.Item3, $"wrong button for 0x{item.Item1:X}");
        Require(input.WheelDelta == 0, "button unexpectedly carries wheel delta");
    }
}

static void TestWheel()
{
    foreach (var delta in new short[] { 120, -120 })
    {
        var raw = unchecked((uint)(ushort)delta) << 16;
        Require(
            HostOwnedCaptureSurfacePointerDecoder.TryDecode(
                HostOwnedCaptureSurfacePointerDecoder.WmMouseWheel,
                new IntPtr(unchecked((int)raw)),
                40,
                50,
                false,
                out var input),
            $"wheel {delta} rejected");
        Require(input is not null, "wheel result missing");
        Require(input.Kind == WindowsCapturePointerEventKind.Wheel, "wrong wheel kind");
        Require(input.Button == WindowsCapturePointerButton.None, "wheel unexpectedly carries a button");
        Require(input.WheelDelta == delta, $"wheel sign changed: expected {delta}, got {input.WheelDelta}");
        Require(input.LocalPixelX == 40 && input.LocalPixelY == 50, "Host supplied local wheel point changed");
    }
}

static void TestRejectedMessages()
{
    Require(
        !HostOwnedCaptureSurfacePointerDecoder.TryDecode(0x000F, IntPtr.Zero, 1, 1, false, out _),
        "unrelated WM_PAINT-like message was accepted");
    Require(
        !HostOwnedCaptureSurfacePointerDecoder.TryDecode(
            HostOwnedCaptureSurfacePointerDecoder.WmMouseWheel,
            IntPtr.Zero,
            1,
            1,
            false,
            out _),
        "zero-delta wheel was accepted");
    Require(
        !HostOwnedCaptureSurfacePointerDecoder.TryDecode(
            HostOwnedCaptureSurfacePointerDecoder.WmMouseMove,
            IntPtr.Zero,
            40000,
            1,
            false,
            out _),
        "out-of-range native coordinate was accepted");
}

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
