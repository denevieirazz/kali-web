using CloudOS.WindowsCapture;
using CloudOS.WindowsCapture.Presenter;

var tests = new (string Name, Action Run)[]
{
    ("opaque session id contract", TestOpaqueSessionIds),
    ("attach assigns monotonic host generations", TestMonotonicGenerations),
    ("duplicate session and source HWND fail closed", TestDuplicateIdentityRejection),
    ("stale generation cannot route input", TestStaleGenerationRejected),
    ("detach releases source HWND without reusing generation", TestDetachReleasesSource),
    ("failed start rolls back identity reservation", TestFailedStartRollsBackReservation),
    ("manager dispose closes every active runtime", TestDisposeClosesSessions),
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
        failures.Add($"{test.Name}: {error.GetType().Name}: {error.Message}");
        Console.Error.WriteLine($"FAIL {failures[^1]}");
    }
}

if (failures.Count > 0)
{
    Console.Error.WriteLine($"CAPTURE_SESSION_MANAGER_CONTRACTS=FAIL count={failures.Count}");
    return 1;
}

Console.WriteLine($"CAPTURE_SESSION_MANAGER_CONTRACTS=PASS count={tests.Length}");
return 0;

static void TestOpaqueSessionIds()
{
    Require(HostOwnedCapturedSurfaceSessionManager.IsValidSessionId("window-0123456789abcdef0123456789abcdef"), "canonical opaque id rejected");
    Require(!HostOwnedCapturedSurfaceSessionManager.IsValidSessionId("window-0123456789ABCDEF0123456789ABCDEF"), "uppercase id accepted");
    Require(!HostOwnedCapturedSurfaceSessionManager.IsValidSessionId("window-0123"), "short id accepted");
    Require(!HostOwnedCapturedSurfaceSessionManager.IsValidSessionId("../../window-0123456789abcdef0123456789abcdef"), "path-like id accepted");
}

static void TestMonotonicGenerations()
{
    var factory = new FakeFactory();
    using var manager = new HostOwnedCapturedSurfaceSessionManager(new IntPtr(0x77), factory);

    var first = manager.Attach(Id(1), new IntPtr(0x101), Layout(1));
    var second = manager.Attach(Id(2), new IntPtr(0x202), Layout(1));

    Require(first.Generation == 1, $"expected generation 1, got {first.Generation}");
    Require(second.Generation == 2, $"expected generation 2, got {second.Generation}");
    Require(first.State == HostOwnedCapturedSurfaceSessionState.Active, "first runtime not active after attach");
    Require(second.State == HostOwnedCapturedSurfaceSessionState.Active, "second runtime not active after attach");
    Require(factory.Created.Count == 2, "factory did not create two independent runtimes");
    Require(factory.Created[0].StartCalls == 1 && factory.Created[1].StartCalls == 1, "runtime start count mismatch");
}

static void TestDuplicateIdentityRejection()
{
    var factory = new FakeFactory();
    using var manager = new HostOwnedCapturedSurfaceSessionManager(new IntPtr(0x77), factory);
    var source = new IntPtr(0x303);
    manager.Attach(Id(3), source, Layout(1));

    ExpectCode(
        () => manager.Attach(Id(3), new IntPtr(0x404), Layout(1)),
        "CAPTURE_SESSION_ALREADY_ATTACHED");
    ExpectCode(
        () => manager.Attach(Id(4), source, Layout(1)),
        "CAPTURE_SOURCE_ALREADY_ATTACHED");
}

static void TestStaleGenerationRejected()
{
    var factory = new FakeFactory();
    using var manager = new HostOwnedCapturedSurfaceSessionManager(new IntPtr(0x77), factory);
    var attached = manager.Attach(Id(5), new IntPtr(0x505), Layout(1));

    ExpectCode(
        () => manager.TryRouteKey(
            Id(5),
            attached.Generation + 1,
            sequence: 1,
            WindowsCaptureKeyEventKind.KeyDown,
            virtualKey: 0x41,
            scanCode: 0x1E,
            extended: false,
            repeat: false),
        "CAPTURE_STALE_GENERATION");

    var delivered = manager.TryRouteKey(
        Id(5),
        attached.Generation,
        sequence: 1,
        WindowsCaptureKeyEventKind.KeyDown,
        virtualKey: 0x41,
        scanCode: 0x1E,
        extended: false,
        repeat: false);

    Require(delivered, "valid exact-generation key was not routed");
    Require(factory.Created.Single().KeyCalls == 1, "stale input reached runtime or valid input was lost");
}

static void TestDetachReleasesSource()
{
    var factory = new FakeFactory();
    using var manager = new HostOwnedCapturedSurfaceSessionManager(new IntPtr(0x77), factory);
    var source = new IntPtr(0x606);
    var first = manager.Attach(Id(6), source, Layout(1));

    Require(manager.Detach(Id(6)), "detach did not remove active session");
    Require(factory.Created[0].CloseCalls == 1, "detach did not close runtime exactly once");

    var second = manager.Attach(Id(7), source, Layout(1));
    Require(second.Generation > first.Generation, "generation was reused after detach");
}

static void TestFailedStartRollsBackReservation()
{
    var factory = new FakeFactory { FailNextStart = true };
    using var manager = new HostOwnedCapturedSurfaceSessionManager(new IntPtr(0x77), factory);
    var sessionId = Id(8);
    var source = new IntPtr(0x808);

    var failed = false;
    try
    {
        manager.Attach(sessionId, source, Layout(1));
    }
    catch (InvalidOperationException error) when (error.Message == FakeSession.StartFailureMessage)
    {
        failed = true;
    }

    Require(failed, "synthetic start failure did not propagate");
    Require(factory.Created[0].CloseCalls == 1, "failed runtime was not closed during rollback");

    var retry = manager.Attach(sessionId, source, Layout(1));
    Require(retry.State == HostOwnedCapturedSurfaceSessionState.Active, "retry could not reclaim rolled-back identity");
    Require(retry.Generation == 2, $"failed generation should remain consumed; got {retry.Generation}");
}

static void TestDisposeClosesSessions()
{
    var factory = new FakeFactory();
    var manager = new HostOwnedCapturedSurfaceSessionManager(new IntPtr(0x77), factory);
    manager.Attach(Id(9), new IntPtr(0x909), Layout(1));
    manager.Attach(Id(10), new IntPtr(0xA10), Layout(1));

    manager.Dispose();
    manager.Dispose();

    Require(factory.Created.All(session => session.CloseCalls == 1), "manager dispose did not close each runtime exactly once");
    var disposed = false;
    try
    {
        _ = manager.GetSnapshots();
    }
    catch (ObjectDisposedException)
    {
        disposed = true;
    }
    Require(disposed, "disposed manager still accepted operations");
}

static WindowsCapturePresentationLayout Layout(long revision, bool visible = true) =>
    new(revision, 20, 30, 640, 480, 1.0, 1.0, visible);

static string Id(int value) => $"window-{value:x32}";

static void ExpectCode(Action action, string expectedCode)
{
    try
    {
        action();
    }
    catch (CapturedSurfaceSessionManagerException error)
    {
        Require(error.Code == expectedCode, $"expected {expectedCode}, got {error.Code}");
        return;
    }

    throw new InvalidOperationException($"Expected manager error {expectedCode}.");
}

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

sealed class FakeFactory : ICapturedSurfaceRuntimeSessionFactory
{
    public List<FakeSession> Created { get; } = new();
    public bool FailNextStart { get; set; }

    public ICapturedSurfaceRuntimeSession Create(
        IntPtr cloudOsOwnerWindowHandle,
        IntPtr sourceWindowHandle,
        string surfaceId,
        int generation,
        WindowsCapturePresentationLayout initialLayout)
    {
        if (cloudOsOwnerWindowHandle == IntPtr.Zero) throw new InvalidOperationException("owner missing");
        var session = new FakeSession(surfaceId, sourceWindowHandle, generation, initialLayout)
        {
            FailStart = FailNextStart
        };
        FailNextStart = false;
        Created.Add(session);
        return session;
    }
}

sealed class FakeSession : ICapturedSurfaceRuntimeSession
{
    public const string StartFailureMessage = "synthetic capture start failure";
    private readonly string _surfaceId;
    private WindowsCapturePresentationLayout _layout;
    private HostOwnedCapturedSurfaceSessionState _state = HostOwnedCapturedSurfaceSessionState.Created;
    private long _captureFrames;
    private long _presentedFrames;
    private long _droppedFrames;
    private string? _failure;

    public FakeSession(
        string surfaceId,
        IntPtr sourceWindowHandle,
        int generation,
        WindowsCapturePresentationLayout initialLayout)
    {
        _surfaceId = surfaceId;
        SourceWindowHandle = sourceWindowHandle;
        Generation = generation;
        _layout = initialLayout;
    }

    public int Generation { get; }
    public IntPtr SourceWindowHandle { get; }
    public bool FailStart { get; set; }
    public int StartCalls { get; private set; }
    public int CloseCalls { get; private set; }
    public int KeyCalls { get; private set; }

    public void Start()
    {
        StartCalls++;
        if (FailStart)
        {
            _failure = StartFailureMessage;
            _state = HostOwnedCapturedSurfaceSessionState.Faulted;
            throw new InvalidOperationException(StartFailureMessage);
        }
        _state = HostOwnedCapturedSurfaceSessionState.Active;
        _captureFrames = 3;
        _presentedFrames = 3;
    }

    public void ApplyLayout(WindowsCapturePresentationLayout layout)
    {
        _layout = layout.Validate();
    }

    public void Suspend()
    {
        _state = HostOwnedCapturedSurfaceSessionState.Suspended;
    }

    public void Resume()
    {
        _state = HostOwnedCapturedSurfaceSessionState.Active;
    }

    public bool TryRoutePointer(
        long sequence,
        WindowsCapturePointerEventKind kind,
        WindowsCapturePointerButton button,
        int wheelDelta,
        bool shift,
        bool control,
        bool alt,
        double surfaceCssWidth,
        double surfaceCssHeight,
        double localCssX,
        double localCssY) =>
        _state == HostOwnedCapturedSurfaceSessionState.Active;

    public bool TryRouteKey(
        long sequence,
        WindowsCaptureKeyEventKind kind,
        int virtualKey,
        int scanCode,
        bool extended,
        bool repeat)
    {
        KeyCalls++;
        return _state == HostOwnedCapturedSurfaceSessionState.Active;
    }

    public HostOwnedCapturedSurfaceSessionSnapshot GetSnapshot()
    {
        var now = DateTimeOffset.UtcNow;
        var capture = new WindowsCaptureSnapshot(
            _captureFrames,
            640,
            480,
            0,
            0,
            640,
            480,
            640,
            480,
            "fake",
            "raw",
            "marshal-interface",
            "hold",
            true,
            _captureFrames > 0 ? now : null,
            _captureFrames > 0 ? now : null,
            null,
            null,
            _failure);
        var presentationState = _state switch
        {
            HostOwnedCapturedSurfaceSessionState.Created => WindowsCapturePresentationState.Bound,
            HostOwnedCapturedSurfaceSessionState.Active => WindowsCapturePresentationState.Active,
            HostOwnedCapturedSurfaceSessionState.Suspended => WindowsCapturePresentationState.Suspended,
            HostOwnedCapturedSurfaceSessionState.Faulted => WindowsCapturePresentationState.Faulted,
            HostOwnedCapturedSurfaceSessionState.Closed => WindowsCapturePresentationState.Closed,
            _ => WindowsCapturePresentationState.Faulted
        };
        var presentation = new WindowsCapturePresentationSnapshot(
            _surfaceId,
            Generation,
            presentationState,
            _layout,
            _presentedFrames,
            _droppedFrames,
            now,
            _state == HostOwnedCapturedSurfaceSessionState.Active ? now : null,
            _presentedFrames > 0 ? now : null,
            null);
        var surface = new WindowsCaptureSurfaceCoordinatorSnapshot(
            presentation,
            _presentedFrames,
            _droppedFrames,
            _failure);
        var input = new WindowsCaptureInputRoutingSnapshot(
            Generation,
            KeyCalls,
            0,
            default,
            null);

        return new HostOwnedCapturedSurfaceSessionSnapshot(
            _surfaceId,
            Generation,
            SourceWindowHandle.ToInt64(),
            0xBEEF,
            _state,
            capture,
            surface,
            input,
            _state != HostOwnedCapturedSurfaceSessionState.Closed,
            _failure);
    }

    public void Close()
    {
        if (_state == HostOwnedCapturedSurfaceSessionState.Closed) return;
        CloseCalls++;
        _state = HostOwnedCapturedSurfaceSessionState.Closed;
    }

    public void Dispose() => Close();
}
