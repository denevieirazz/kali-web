using CloudOS.WindowsCapture;

var failures = new List<string>();
Run("client center maps inside content", ClientCenterMapsInsideContent);
Run("non-client titlebar rejects", NonClientTitlebarRejects);
Run("source bounds reject", SourceBoundsReject);
Run("pointer input validates", PointerInputValidates);
Run("key input validates", KeyInputValidates);
Run("input gate rejects stale generation", InputGateRejectsStaleGeneration);
Run("input gate rejects replay", InputGateRejectsReplay);
Run("input gate rejects inactive surface", InputGateRejectsInactiveSurface);

if (failures.Count > 0)
{
    Console.Error.WriteLine($"INPUT_CONTRACT_TESTS=FAIL ({failures.Count})");
    foreach (var failure in failures) Console.Error.WriteLine(failure);
    return 1;
}

Console.WriteLine("INPUT_CONTRACT_TESTS=PASS");
return 0;

void Run(string name, Action test)
{
    try
    {
        test();
        Console.WriteLine($"PASS: {name}");
    }
    catch (Exception error)
    {
        failures.Add($"FAIL: {name}: {error.GetType().Name}: {error.Message}");
    }
}

static WindowsCaptureClientGeometry TypicalWindowGeometry() => new(
    SourcePixelWidth: 642,
    SourcePixelHeight: 452,
    CaptureScreenX: 100,
    CaptureScreenY: 100,
    CapturePixelWidth: 642,
    CapturePixelHeight: 452,
    ClientScreenX: 101,
    ClientScreenY: 131,
    ClientPixelWidth: 640,
    ClientPixelHeight: 420);

static void ClientCenterMapsInsideContent()
{
    var geometry = TypicalWindowGeometry().Validate();
    Require(WindowsCaptureClientInputMapper.TryMapSourcePixel(geometry, 321, 241, out var mapped), "center pixel did not map");
    Require(mapped is not null, "center mapping is null");
    Require(mapped.ClientPixelX is >= 0 and < 640, "mapped X escaped client area");
    Require(mapped.ClientPixelY is >= 0 and < 420, "mapped Y escaped client area");
}

static void NonClientTitlebarRejects()
{
    var geometry = TypicalWindowGeometry().Validate();
    Require(!WindowsCaptureClientInputMapper.TryMapSourcePixel(geometry, 320, 5, out _), "titlebar pixel was accepted as client input");
    Require(!WindowsCaptureClientInputMapper.TryMapSourcePixel(geometry, 0, 200, out _), "left border pixel was accepted as client input");
}

static void SourceBoundsReject()
{
    var geometry = TypicalWindowGeometry().Validate();
    Require(!WindowsCaptureClientInputMapper.TryMapSourcePixel(geometry, -1, 0, out _), "negative source pixel accepted");
    Require(!WindowsCaptureClientInputMapper.TryMapSourcePixel(geometry, 642, 0, out _), "right-exclusive source pixel accepted");
    Require(!WindowsCaptureClientInputMapper.TryMapSourcePixel(geometry, 0, 452, out _), "bottom-exclusive source pixel accepted");
}

static void PointerInputValidates()
{
    _ = new WindowsCapturePointerInput(
        1,
        2,
        WindowsCapturePointerEventKind.ButtonDown,
        WindowsCapturePointerButton.Left,
        10,
        20,
        0,
        false,
        false,
        false).Validate();

    ExpectThrows<ArgumentOutOfRangeException>(() => new WindowsCapturePointerInput(
        2,
        2,
        WindowsCapturePointerEventKind.Move,
        WindowsCapturePointerButton.Left,
        10,
        20,
        0,
        false,
        false,
        false).Validate());

    ExpectThrows<ArgumentOutOfRangeException>(() => new WindowsCapturePointerInput(
        3,
        2,
        WindowsCapturePointerEventKind.Wheel,
        WindowsCapturePointerButton.None,
        10,
        20,
        0,
        false,
        false,
        false).Validate());
}

static void KeyInputValidates()
{
    _ = new WindowsCaptureKeyInput(1, 3, WindowsCaptureKeyEventKind.KeyDown, 0x41, 0x1E, false, false).Validate();
    ExpectThrows<ArgumentOutOfRangeException>(() => new WindowsCaptureKeyInput(2, 3, WindowsCaptureKeyEventKind.KeyDown, 0, 0, false, false).Validate());
    ExpectThrows<ArgumentOutOfRangeException>(() => new WindowsCaptureKeyInput(3, 0, WindowsCaptureKeyEventKind.KeyUp, 0x41, 0x1E, false, false).Validate());
}

static void InputGateRejectsStaleGeneration()
{
    var gate = new WindowsCaptureInputGate(4);
    gate.SetActive(true);
    var stale = gate.Admit(3, 1);
    Require(!stale.Allowed, "stale generation was admitted");
    Require(stale.Rejection == WindowsCaptureInputRejection.StaleGeneration, "wrong stale-generation rejection");
    var current = gate.Admit(4, 1);
    Require(current.Allowed, "current generation was not admitted after stale event");
}

static void InputGateRejectsReplay()
{
    var gate = new WindowsCaptureInputGate(2);
    gate.SetActive(true);
    Require(gate.Admit(2, 10).Allowed, "initial sequence rejected");
    var replay = gate.Admit(2, 10);
    Require(!replay.Allowed && replay.Rejection == WindowsCaptureInputRejection.ReplayedSequence, "same sequence replay was admitted");
    var old = gate.Admit(2, 9);
    Require(!old.Allowed && old.Rejection == WindowsCaptureInputRejection.ReplayedSequence, "older sequence was admitted");
    Require(gate.Admit(2, 11).Allowed, "next monotonic sequence rejected");
}

static void InputGateRejectsInactiveSurface()
{
    var gate = new WindowsCaptureInputGate(9);
    var inactive = gate.Admit(9, 1);
    Require(!inactive.Allowed && inactive.Rejection == WindowsCaptureInputRejection.SurfaceInactive, "inactive surface accepted input");
    gate.SetActive(true);
    Require(gate.Admit(9, 1).Allowed, "active surface rejected valid input");
    gate.ResetForDeactivation();
    Require(!gate.Admit(9, 2).Allowed, "deactivated surface accepted input");
}

static void ExpectThrows<T>(Action action) where T : Exception
{
    try
    {
        action();
    }
    catch (T)
    {
        return;
    }
    throw new InvalidOperationException($"Expected {typeof(T).Name}.");
}

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
