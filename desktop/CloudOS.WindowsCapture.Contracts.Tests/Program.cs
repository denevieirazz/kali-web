using CloudOS.WindowsCapture;

var failures = new List<string>();
Run("happy path", TestHappyPath);
Run("layout revision monotonic", TestLayoutRevision);
Run("hidden surface cannot present", TestHiddenSurface);
Run("fault is terminal until close", TestFaultTerminal);
Run("generation validation", TestGenerationValidation);
Run("layout validation", TestLayoutValidation);

if (failures.Count > 0)
{
    Console.Error.WriteLine($"PRESENTATION_CONTRACT_TESTS=FAIL ({failures.Count})");
    foreach (var failure in failures) Console.Error.WriteLine(failure);
    return 1;
}

Console.WriteLine("PRESENTATION_CONTRACT_TESTS=PASS");
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

static WindowsCapturePresentationLayout Layout(long revision, bool visible = true) =>
    new(revision, 10, 20, 800, 600, 1.25, 1.25, visible);

static void TestHappyPath()
{
    var lifecycle = new WindowsCapturePresentationLifecycle("surface-opaque-1", 1);
    lifecycle.Bind(Layout(1));
    lifecycle.Activate();
    lifecycle.RecordPresentedFrame(DateTimeOffset.UtcNow);
    lifecycle.RecordDroppedFrame();
    lifecycle.Suspend();
    lifecycle.ApplyLayout(Layout(2));
    lifecycle.Activate();
    lifecycle.RecordPresentedFrame(DateTimeOffset.UtcNow.AddMilliseconds(1));
    lifecycle.Close();

    var snapshot = lifecycle.GetSnapshot();
    Require(snapshot.State == WindowsCapturePresentationState.Closed, "surface did not close");
    Require(snapshot.PresentedFrameCount == 2, "presented frame count mismatch");
    Require(snapshot.DroppedFrameCount == 1, "dropped frame count mismatch");
    Require(snapshot.Layout?.Revision == 2, "layout revision mismatch");
    Require(snapshot.Generation == 1, "generation mismatch");
}

static void TestLayoutRevision()
{
    var lifecycle = new WindowsCapturePresentationLifecycle("surface-opaque-2", 3);
    lifecycle.Bind(Layout(10));
    lifecycle.Activate();
    ExpectThrows<InvalidOperationException>(() => lifecycle.ApplyLayout(Layout(10)));
    ExpectThrows<InvalidOperationException>(() => lifecycle.ApplyLayout(Layout(9)));
    lifecycle.ApplyLayout(Layout(11));
}

static void TestHiddenSurface()
{
    var lifecycle = new WindowsCapturePresentationLifecycle("surface-opaque-3", 1);
    lifecycle.Bind(Layout(1, visible: false));
    lifecycle.Activate();
    ExpectThrows<InvalidOperationException>(() => lifecycle.RecordPresentedFrame(DateTimeOffset.UtcNow));
    lifecycle.RecordDroppedFrame();
}

static void TestFaultTerminal()
{
    var lifecycle = new WindowsCapturePresentationLifecycle("surface-opaque-4", 2);
    lifecycle.Bind(Layout(1));
    lifecycle.Activate();
    lifecycle.Fail(WindowsCapturePresentationFaultKind.DeviceLost, "simulated device loss");
    lifecycle.Fail(WindowsCapturePresentationFaultKind.InternalError, "second fault must not replace first");

    var faulted = lifecycle.GetSnapshot();
    Require(faulted.State == WindowsCapturePresentationState.Faulted, "surface did not fault");
    Require(faulted.Fault?.Kind == WindowsCapturePresentationFaultKind.DeviceLost, "first fault was replaced");
    ExpectThrows<InvalidOperationException>(lifecycle.Activate);
    ExpectThrows<InvalidOperationException>(() => lifecycle.ApplyLayout(Layout(2)));
    ExpectThrows<InvalidOperationException>(() => lifecycle.RecordDroppedFrame());
    lifecycle.Close();
    Require(lifecycle.GetSnapshot().State == WindowsCapturePresentationState.Closed, "faulted surface did not close");
}

static void TestGenerationValidation()
{
    ExpectThrows<ArgumentOutOfRangeException>(() => new WindowsCapturePresentationLifecycle("surface", 0));
    ExpectThrows<ArgumentException>(() => new WindowsCapturePresentationLifecycle("", 1));
}

static void TestLayoutValidation()
{
    ExpectThrows<ArgumentOutOfRangeException>(() => new WindowsCapturePresentationLayout(0, 0, 0, 800, 600, 1, 1, true).Validate());
    ExpectThrows<ArgumentOutOfRangeException>(() => new WindowsCapturePresentationLayout(1, 0, 0, 0, 600, 1, 1, true).Validate());
    ExpectThrows<ArgumentOutOfRangeException>(() => new WindowsCapturePresentationLayout(1, 0, 0, 800, 600, 0.1, 1, true).Validate());
    _ = Layout(1).Validate();
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
