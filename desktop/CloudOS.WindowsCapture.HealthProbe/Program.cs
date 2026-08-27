using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using CloudOS.WindowsCapture;

var helpRequested = args.Contains("--help", StringComparer.OrdinalIgnoreCase);
if (args.Length == 0 || helpRequested)
{
    Console.WriteLine("CloudOS Windows frame health probe");
    Console.WriteLine("  --hwnd <decimal|0xHEX>");
    Console.WriteLine("  [--seconds <1-30>] [--min-frames <1-1000>]");
    Console.WriteLine("  [--sample-every <1-120>] [--samples <1-64>]");
    Console.WriteLine("  [--region <32-1024>] [--grid <8-128>] [--output <path>]");
    return helpRequested ? 0 : 64;
}

var options = HealthProbeOptions.Parse(args);
using var apartment = WinRtApartment.Enter();
var startedAt = DateTimeOffset.UtcNow;

try
{
    using var capture = new WindowsCaptureSession(
        options.WindowHandle,
        WindowsCaptureTargetKind.Window,
        WindowsCaptureItemFactoryKind.RawActivationFactory,
        WindowsCaptureItemProjectionKind.MarshalInterfaceFromAbi,
        WindowsCaptureAbiLifetimeKind.HoldUntilSessionDispose,
        new WindowsFrameHealthOptions(
            options.SampleEveryNFrames,
            options.MaximumSamples,
            options.MaximumRegionSize,
            options.GridSize));

    var snapshot = await capture.WaitForFramesAsync(
        options.MinimumFrames,
        TimeSpan.FromSeconds(options.Seconds));
    var health = snapshot.FrameHealth;

    var capturePass = snapshot.Failure is null && snapshot.FrameCount >= options.MinimumFrames;
    var healthAvailable = health is { SuccessfulSamples: > 0 };
    var healthPass = healthAvailable && health!.FailedSamples == 0;
    var verdict = capturePass && healthPass ? "PASS" : "FAIL";

    var report = new HealthProbeReport(
        1,
        "CloudOS.WindowsCapture.HealthProbe",
        startedAt,
        DateTimeOffset.UtcNow,
        verdict,
        apartment.State,
        $"0x{options.WindowHandle.ToInt64():X}",
        new CaptureSummary(
            options.MinimumFrames,
            options.Seconds,
            snapshot.FrameCount,
            snapshot.Width,
            snapshot.Height,
            snapshot.EmptyFrameCount,
            snapshot.ResizeCount,
            snapshot.Failure),
        health,
        new Interpretation(
            capturePass,
            healthAvailable,
            health?.StaticSequenceSuspect ?? false,
            health?.FlatNeutralSequenceSuspect ?? false,
            health is { DistinctFrameHashes: > 1 },
            health is { ChangedSamples: > 0 }),
        null);

    await EmitAsync(report, options.OutputPath);
    return verdict == "PASS" ? 0 : 2;
}
catch (WindowsCaptureSetupException error)
{
    var report = new HealthProbeReport(
        1,
        "CloudOS.WindowsCapture.HealthProbe",
        startedAt,
        DateTimeOffset.UtcNow,
        "ERROR",
        apartment.State,
        $"0x{options.WindowHandle.ToInt64():X}",
        null,
        null,
        null,
        new HealthProbeError(
            error.Stage,
            error.GetType().Name,
            error.Message,
            $"0x{error.NativeHResult:X8}",
            error.ItemWidth,
            error.ItemHeight,
            error.BufferWidth,
            error.BufferHeight));
    await EmitAsync(report, options.OutputPath);
    Console.Error.WriteLine($"FRAME_HEALTH_ERROR={error.GetType().Name}: {error.Message}");
    return 1;
}
catch (Exception error) when (error is not OutOfMemoryException)
{
    var report = new HealthProbeReport(
        1,
        "CloudOS.WindowsCapture.HealthProbe",
        startedAt,
        DateTimeOffset.UtcNow,
        "ERROR",
        apartment.State,
        $"0x{options.WindowHandle.ToInt64():X}",
        null,
        null,
        null,
        new HealthProbeError(
            "probe-runtime",
            error.GetType().Name,
            error.Message,
            $"0x{error.HResult:X8}",
            0,
            0,
            0,
            0));
    await EmitAsync(report, options.OutputPath);
    Console.Error.WriteLine($"FRAME_HEALTH_ERROR={error.GetType().Name}: {error.Message}");
    return 1;
}

static async Task EmitAsync(HealthProbeReport report, string? outputPath)
{
    var json = JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true });
    Console.WriteLine(json);
    if (outputPath is null) return;

    var fullPath = Path.GetFullPath(outputPath);
    Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
    await File.WriteAllTextAsync(fullPath, json + Environment.NewLine, new UTF8Encoding(false));
    Console.Error.WriteLine($"REPORT={fullPath}");
}

internal sealed record HealthProbeOptions(
    IntPtr WindowHandle,
    int Seconds,
    int MinimumFrames,
    int SampleEveryNFrames,
    int MaximumSamples,
    int MaximumRegionSize,
    int GridSize,
    string? OutputPath)
{
    public static HealthProbeOptions Parse(string[] args)
    {
        IntPtr hwnd = IntPtr.Zero;
        var seconds = 5;
        var minimumFrames = 20;
        var sampleEvery = 3;
        var maximumSamples = 8;
        var maximumRegion = 256;
        var gridSize = 32;
        string? output = null;

        for (var index = 0; index < args.Length; index++)
        {
            string Next(string option)
            {
                if (++index >= args.Length) throw new ArgumentException($"Missing value for {option}.");
                return args[index];
            }

            switch (args[index])
            {
                case "--hwnd":
                    hwnd = ParseHandle(Next("--hwnd"));
                    break;
                case "--seconds":
                    seconds = int.Parse(Next("--seconds"));
                    if (seconds is < 1 or > 30) throw new ArgumentOutOfRangeException("--seconds");
                    break;
                case "--min-frames":
                    minimumFrames = int.Parse(Next("--min-frames"));
                    if (minimumFrames is < 1 or > 1000) throw new ArgumentOutOfRangeException("--min-frames");
                    break;
                case "--sample-every":
                    sampleEvery = int.Parse(Next("--sample-every"));
                    break;
                case "--samples":
                    maximumSamples = int.Parse(Next("--samples"));
                    break;
                case "--region":
                    maximumRegion = int.Parse(Next("--region"));
                    break;
                case "--grid":
                    gridSize = int.Parse(Next("--grid"));
                    break;
                case "--output":
                    output = Next("--output");
                    break;
                default:
                    throw new ArgumentException($"Unknown option: {args[index]}");
            }
        }

        if (hwnd == IntPtr.Zero) throw new ArgumentException("--hwnd is required and must be non-zero.");
        _ = new WindowsFrameHealthOptions(sampleEvery, maximumSamples, maximumRegion, gridSize).Validate();
        return new HealthProbeOptions(hwnd, seconds, minimumFrames, sampleEvery, maximumSamples, maximumRegion, gridSize, output);
    }

    private static IntPtr ParseHandle(string text)
    {
        var value = text.StartsWith("0x", StringComparison.OrdinalIgnoreCase)
            ? Convert.ToInt64(text[2..], 16)
            : long.Parse(text);
        return new IntPtr(value);
    }
}

internal sealed record HealthProbeReport(
    int SchemaVersion,
    string Probe,
    DateTimeOffset StartedAt,
    DateTimeOffset CompletedAt,
    string Verdict,
    string Apartment,
    string Hwnd,
    CaptureSummary? Capture,
    WindowsFrameHealthSnapshot? FrameHealth,
    Interpretation? Interpretation,
    HealthProbeError? Error);

internal sealed record CaptureSummary(
    int RequiredFrames,
    int ObservedSeconds,
    long FrameCount,
    int Width,
    int Height,
    int EmptyFrameCount,
    int ResizeCount,
    string? Failure);

internal sealed record Interpretation(
    bool CapturePass,
    bool HealthAvailable,
    bool StaticSequenceSuspect,
    bool FlatNeutralSequenceSuspect,
    bool MultipleDistinctHashes,
    bool ObservedFrameChanges);

internal sealed record HealthProbeError(
    string Stage,
    string Type,
    string Message,
    string HResult,
    int ItemWidth,
    int ItemHeight,
    int BufferWidth,
    int BufferHeight);

internal sealed class WinRtApartment : IDisposable
{
    private const uint RoInitMultithreaded = 1;
    private const int SFalse = 1;
    private const int RpcEChangedMode = unchecked((int)0x80010106);
    private readonly bool _mustUninitialize;

    private WinRtApartment(bool mustUninitialize, string state)
    {
        _mustUninitialize = mustUninitialize;
        State = state;
    }

    public string State { get; }

    public static WinRtApartment Enter()
    {
        var result = RoInitialize(RoInitMultithreaded);
        if (result == 0) return new WinRtApartment(true, "mta-initialized-by-health-probe");
        if (result == SFalse) return new WinRtApartment(true, "mta-already-initialized");
        if (result == RpcEChangedMode) return new WinRtApartment(false, "existing-non-mta-apartment");
        Marshal.ThrowExceptionForHR(result);
        throw new InvalidOperationException("RoInitialize failed without an HRESULT exception.");
    }

    public void Dispose()
    {
        if (_mustUninitialize) RoUninitialize();
    }

    [DllImport("combase.dll")]
    private static extern int RoInitialize(uint initType);

    [DllImport("combase.dll")]
    private static extern void RoUninitialize();
}
