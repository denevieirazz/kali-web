using System.Text.Json;
using CloudOS.WindowsCapture;
using CloudOS.WindowsCapture.Presenter;

ApplicationConfiguration.Initialize();

if (args.Contains("--help", StringComparer.Ordinal))
{
    Console.WriteLine("CloudOS captured-surface presenter probe");
    Console.WriteLine("  --hwnd <decimal|0xHEX>");
    Console.WriteLine("  --seconds <1-30>             default 5");
    Console.WriteLine("  --minimum-frames <1-600>     default 10");
    Console.WriteLine("  --output <path>               optional JSON report");
    return 0;
}

var parsed = ParseArguments(args);
if (!parsed.Success)
{
    Console.Error.WriteLine(parsed.Error);
    return 64;
}

var startedAt = DateTimeOffset.UtcNow;
var stage = "owner-window";
using var owner = new Form
{
    Text = "CloudOS Captured Surface Presenter Probe Owner",
    StartPosition = FormStartPosition.Manual,
    Left = 80,
    Top = 80,
    Width = 1000,
    Height = 760,
    ShowInTaskbar = true
};

HostOwnedCaptureSurfacePresenter? presenter = null;
WindowsCaptureSurfaceCoordinator? coordinator = null;
WindowsCaptureSession? capture = null;
object? report = null;
var exitCode = 1;

try
{
    owner.Show();
    Application.DoEvents();
    if (owner.Handle == IntPtr.Zero) throw new InvalidOperationException("Owner HWND was not created.");

    stage = "presenter-bind";
    presenter = new HostOwnedCaptureSurfacePresenter(owner.Handle);
    coordinator = new WindowsCaptureSurfaceCoordinator("presenter-probe-surface", 1, presenter);
    var layout = new WindowsCapturePresentationLayout(
        Revision: 1,
        PixelX: owner.Left + 24,
        PixelY: owner.Top + 72,
        PixelWidth: 900,
        PixelHeight: 620,
        ScaleX: 1,
        ScaleY: 1,
        Visible: true).Validate();
    coordinator.Bind(layout);
    coordinator.Activate();

    stage = "capture-session";
    capture = new WindowsCaptureSession(
        parsed.SourceHwnd,
        WindowsCaptureTargetKind.Window,
        WindowsCaptureItemFactoryKind.RawActivationFactory,
        WindowsCaptureItemProjectionKind.MarshalInterfaceFromAbi,
        WindowsCaptureAbiLifetimeKind.HoldUntilSessionDispose,
        frameHealthOptions: new WindowsFrameHealthOptions(
            SampleEveryNthFrame: 2,
            MaxSamples: 16,
            RegionSize: 256,
            GridSize: 32),
        frameSink: coordinator);
    capture.Start();

    stage = "frame-delivery";
    var deadline = DateTimeOffset.UtcNow.AddSeconds(parsed.Seconds);
    while (DateTimeOffset.UtcNow < deadline)
    {
        Application.DoEvents();
        var snapshot = capture.GetSnapshot();
        if (snapshot.Failure is not null || snapshot.FrameCount >= parsed.MinimumFrames) break;
        Thread.Sleep(16);
    }

    var captureSnapshot = capture.GetSnapshot();
    var presentationSnapshot = coordinator.GetSnapshot();
    var passed = captureSnapshot.FrameCount >= parsed.MinimumFrames
        && captureSnapshot.FrameSink?.DeliveredFrames >= parsed.MinimumFrames
        && presentationSnapshot.AcceptedFrames >= parsed.MinimumFrames
        && presentationSnapshot.Presentation.PresentedFrameCount >= parsed.MinimumFrames
        && presentationSnapshot.Presentation.State == WindowsCapturePresentationState.Active
        && presenter.PresentationWindowHandle != IntPtr.Zero
        && string.IsNullOrEmpty(captureSnapshot.Failure)
        && string.IsNullOrEmpty(presentationSnapshot.LastPresenterFailure);

    exitCode = passed ? 0 : 2;
    report = new
    {
        schemaVersion = 1,
        probe = "CloudOS captured-surface presenter end-to-end",
        startedAt,
        completedAt = DateTimeOffset.UtcNow,
        verdict = passed ? "PASS" : "FAIL",
        stage = passed ? null : stage,
        sourceHwnd = $"0x{parsed.SourceHwnd.ToInt64():X}",
        ownerHwnd = $"0x{owner.Handle.ToInt64():X}",
        presentationHwnd = $"0x{presenter.PresentationWindowHandle.ToInt64():X}",
        minimumFrames = parsed.MinimumFrames,
        capture = captureSnapshot,
        presentation = presentationSnapshot
    };
}
catch (Exception error) when (error is not OutOfMemoryException)
{
    exitCode = 1;
    var setup = error as WindowsCaptureSetupException;
    report = new
    {
        schemaVersion = 1,
        probe = "CloudOS captured-surface presenter end-to-end",
        startedAt,
        completedAt = DateTimeOffset.UtcNow,
        verdict = "ERROR",
        stage = setup?.Stage ?? stage,
        sourceHwnd = $"0x{parsed.SourceHwnd.ToInt64():X}",
        ownerHwnd = owner.Handle == IntPtr.Zero ? null : $"0x{owner.Handle.ToInt64():X}",
        presentationHwnd = presenter?.PresentationWindowHandle is { } handle && handle != IntPtr.Zero ? $"0x{handle.ToInt64():X}" : null,
        error = new
        {
            type = error.GetType().Name,
            message = error.Message,
            hresult = $"0x{error.HResult:X8}",
            nativeHResult = setup is null ? null : $"0x{setup.NativeHResult:X8}"
        }
    };
    Console.Error.WriteLine($"PRESENTER_PROBE_ERROR={error.GetType().Name}: {error.Message}");
}
finally
{
    capture?.Dispose();
    coordinator?.Dispose();
    if (coordinator is null) presenter?.Dispose();
    owner.Close();
    Application.DoEvents();
}

var json = JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true });
Console.WriteLine(json);
if (!string.IsNullOrWhiteSpace(parsed.OutputPath))
{
    var fullPath = Path.GetFullPath(parsed.OutputPath);
    Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
    File.WriteAllText(fullPath, json);
}
return exitCode;

static ParsedArguments ParseArguments(string[] values)
{
    IntPtr hwnd = IntPtr.Zero;
    var seconds = 5;
    var minimumFrames = 10;
    string? output = null;

    for (var index = 0; index < values.Length; index++)
    {
        var key = values[index];
        if (index + 1 >= values.Length) return ParsedArguments.Fail($"Missing value for {key}.");
        var value = values[++index];
        switch (key)
        {
            case "--hwnd":
                if (!TryParseHandle(value, out hwnd) || hwnd == IntPtr.Zero) return ParsedArguments.Fail("Invalid --hwnd.");
                break;
            case "--seconds":
                if (!int.TryParse(value, out seconds) || seconds is < 1 or > 30) return ParsedArguments.Fail("Invalid --seconds.");
                break;
            case "--minimum-frames":
                if (!int.TryParse(value, out minimumFrames) || minimumFrames is < 1 or > 600) return ParsedArguments.Fail("Invalid --minimum-frames.");
                break;
            case "--output":
                output = value;
                break;
            default:
                return ParsedArguments.Fail($"Unknown argument: {key}");
        }
    }

    if (hwnd == IntPtr.Zero) return ParsedArguments.Fail("--hwnd is required.");
    return new ParsedArguments(true, null, hwnd, seconds, minimumFrames, output);
}

static bool TryParseHandle(string value, out IntPtr handle)
{
    handle = IntPtr.Zero;
    try
    {
        var parsed = value.StartsWith("0x", StringComparison.OrdinalIgnoreCase)
            ? Convert.ToInt64(value[2..], 16)
            : Convert.ToInt64(value, 10);
        if (parsed <= 0) return false;
        handle = new IntPtr(parsed);
        return true;
    }
    catch
    {
        return false;
    }
}

sealed record ParsedArguments(
    bool Success,
    string? Error,
    IntPtr SourceHwnd,
    int Seconds,
    int MinimumFrames,
    string? OutputPath)
{
    public static ParsedArguments Fail(string error) => new(false, error, IntPtr.Zero, 5, 10, null);
}
