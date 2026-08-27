using CloudOS.WindowsCapture;

var failures = new List<string>();
Run("happy path", TestHappyPath);
Run("layout revision monotonic", TestLayoutRevision);
Run("hidden surface cannot present", TestHiddenSurface);
Run("fault is terminal until close", TestFaultTerminal);
Run("generation validation", TestGenerationValidation);
Run("layout validation", TestLayoutValidation);
Run("input full-frame mapping", TestInputFullFrameMapping);
Run("input crop mapping", TestInputCropMapping);
Run("input boundary rejection", TestInputBoundaryRejection);
Run("input geometry validation", TestInputGeometryValidation);
Run("surface coordinator lifecycle", TestSurfaceCoordinatorLifecycle);
Run("surface coordinator fail closed", TestSurfaceCoordinatorFailure);

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

static void TestInputFullFrameMapping()
{
    var geometry = WindowsCaptureInputGeometry.FullFrame(1920, 1080, 960, 540);
    Require(WindowsCaptureInputMapper.TryMapPointer(geometry, 480, 270, out var center), "center pointer did not map");
    Require(center is not null, "center pointer mapping is null");
    Require(center.SourcePixelX == 960 && center.SourcePixelY == 540, "center pointer mapped to wrong source pixel");
    Require(Math.Abs(center.NormalizedX - 0.5) < 0.000001, "normalized X mismatch");
    Require(Math.Abs(center.NormalizedY - 0.5) < 0.000001, "normalized Y mismatch");

    Require(WindowsCaptureInputMapper.TryMapPointer(geometry, 959.999, 539.999, out var last), "last in-bounds pointer did not map");
    Require(last is not null && last.SourcePixelX == 1919 && last.SourcePixelY == 1079, "last in-bounds pointer did not clamp to final source pixel");
}

static void TestInputCropMapping()
{
    var geometry = new WindowsCaptureInputGeometry(
        2560,
        1440,
        320,
        180,
        1920,
        1080,
        960,
        540).Validate();

    Require(WindowsCaptureInputMapper.TryMapPointer(geometry, 0, 0, out var origin), "crop origin pointer did not map");
    Require(origin is not null && origin.SourcePixelX == 320 && origin.SourcePixelY == 180, "crop origin mapped outside crop");

    Require(WindowsCaptureInputMapper.TryMapPointer(geometry, 480, 270, out var center), "crop center pointer did not map");
    Require(center is not null && center.SourcePixelX == 1280 && center.SourcePixelY == 720, "crop center mapped incorrectly");
}

static void TestInputBoundaryRejection()
{
    var geometry = WindowsCaptureInputGeometry.FullFrame(800, 600, 800, 600);
    Require(!WindowsCaptureInputMapper.TryMapPointer(geometry, -0.001, 10, out _), "negative X was accepted");
    Require(!WindowsCaptureInputMapper.TryMapPointer(geometry, 10, -0.001, out _), "negative Y was accepted");
    Require(!WindowsCaptureInputMapper.TryMapPointer(geometry, 800, 10, out _), "right exclusive edge was accepted");
    Require(!WindowsCaptureInputMapper.TryMapPointer(geometry, 10, 600, out _), "bottom exclusive edge was accepted");
    Require(!WindowsCaptureInputMapper.TryMapPointer(geometry, double.NaN, 10, out _), "NaN pointer was accepted");
    Require(!WindowsCaptureInputMapper.TryMapPointer(geometry, double.PositiveInfinity, 10, out _), "infinite pointer was accepted");
}

static void TestInputGeometryValidation()
{
    ExpectThrows<ArgumentOutOfRangeException>(() => WindowsCaptureInputGeometry.FullFrame(0, 600, 800, 600));
    ExpectThrows<ArgumentOutOfRangeException>(() => new WindowsCaptureInputGeometry(800, 600, 790, 0, 20, 100, 800, 600).Validate());
    ExpectThrows<ArgumentOutOfRangeException>(() => new WindowsCaptureInputGeometry(800, 600, 0, 0, 800, 600, double.NaN, 600).Validate());
    _ = new WindowsCaptureInputGeometry(800, 600, 100, 50, 500, 400, 1000, 800).Validate();
}

static void TestSurfaceCoordinatorLifecycle()
{
    var presenter = new FakePresenter();
    using var coordinator = new WindowsCaptureSurfaceCoordinator("surface-coordinator-1", 7, presenter);
    coordinator.Bind(Layout(1));
    coordinator.Activate();
    coordinator.ApplyLayout(Layout(2));
    coordinator.Suspend();

    var snapshot = coordinator.GetSnapshot();
    Require(snapshot.Presentation.State == WindowsCapturePresentationState.Suspended, "coordinator did not suspend");
    Require(snapshot.Presentation.Generation == 7, "coordinator generation mismatch");
    Require(snapshot.Presentation.Layout?.Revision == 2, "coordinator layout revision mismatch");
    Require(presenter.BindCount == 1, "presenter bind count mismatch");
    Require(presenter.ResumeCount == 1, "presenter resume count mismatch");
    Require(presenter.LayoutCount == 1, "presenter layout count mismatch");
    Require(presenter.SuspendCount == 1, "presenter suspend count mismatch");
}

static void TestSurfaceCoordinatorFailure()
{
    var presenter = new FakePresenter { FailBind = true };
    using var coordinator = new WindowsCaptureSurfaceCoordinator("surface-coordinator-2", 1, presenter);
    ExpectThrows<InvalidOperationException>(() => coordinator.Bind(Layout(1)));
    var snapshot = coordinator.GetSnapshot();
    Require(snapshot.Presentation.State == WindowsCapturePresentationState.Faulted, "presenter failure did not fault surface");
    Require(snapshot.Presentation.Fault?.Kind == WindowsCapturePresentationFaultKind.RendererUnavailable, "wrong coordinator fault kind");
    Require(snapshot.LastPresenterFailure?.Contains("simulated bind failure", StringComparison.Ordinal) == true, "presenter failure was not recorded");
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

sealed class FakePresenter : IWindowsCaptureNativePresenter
{
    public bool FailBind { get; init; }
    public int BindCount { get; private set; }
    public int LayoutCount { get; private set; }
    public int SuspendCount { get; private set; }
    public int ResumeCount { get; private set; }

    public void Bind(WindowsCapturePresentationLayout layout)
    {
        if (FailBind) throw new InvalidOperationException("simulated bind failure");
        BindCount++;
    }

    public void ApplyLayout(WindowsCapturePresentationLayout layout) => LayoutCount++;
    public void Suspend() => SuspendCount++;
    public void Resume() => ResumeCount++;
    public void Present(WindowsCaptureFrameEnvelope frame) => throw new NotSupportedException("Frame presentation is not used by contract tests.");
    public void Dispose() { }
}
