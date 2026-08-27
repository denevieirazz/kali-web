using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using CloudOS.WindowsCapture;

if (args.Length == 0 || args.Contains("--help", StringComparer.OrdinalIgnoreCase))
{
    Console.WriteLine("CloudOS Windows capture probe");
    Console.WriteLine("  --pid <processId> | --hwnd <decimal|0xHEX>");
    Console.WriteLine("  [--capture-kind window|monitor]");
    Console.WriteLine("  [--item-factory raw|projected]");
    Console.WriteLine("  [--seconds <1-30>] [--min-frames <1-1000>] [--output <path>]");
    return 64;
}

try
{
    using var apartment = WinRtApartment.EnterForProbe();
    var options = ProbeOptions.Parse(args);
    return await RunProbeAsync(options, apartment.State);
}
catch (Exception error) when (error is not OutOfMemoryException)
{
    Console.Error.WriteLine($"CAPTURE_PROBE_FATAL={error.GetType().Name}: {error.Message}");
    Console.Error.WriteLine(error);
    return 1;
}

static async Task<int> RunProbeAsync(ProbeOptions options, string apartmentState)
{
    var hwnd = options.WindowHandle ?? WindowLocator.FindBestTopLevelWindow(options.ProcessId!.Value);
    if (hwnd == IntPtr.Zero) throw new InvalidOperationException("No visible top-level HWND was found for the requested process.");

    WindowLocator.GetWindowThreadProcessId(hwnd, out var ownerProcessId);
    using var ownerProcess = Process.GetProcessById(checked((int)ownerProcessId));
    var title = WindowLocator.GetTitle(hwnd);
    var rectangle = WindowLocator.GetRectangle(hwnd);

    var targetKind = options.CaptureKind;
    var targetHandle = targetKind == WindowsCaptureTargetKind.Window
        ? hwnd
        : WindowLocator.GetNearestMonitor(hwnd);
    if (targetHandle == IntPtr.Zero)
        throw new InvalidOperationException($"Could not resolve a {targetKind} capture handle.");

    var startedAt = DateTimeOffset.UtcNow;
    try
    {
        using var capture = new WindowsCaptureSession(targetHandle, targetKind, options.ItemFactoryKind);
        var snapshot = await capture.WaitForFramesAsync(
            options.MinimumFrames,
            TimeSpan.FromSeconds(options.Seconds));
        var completedAt = DateTimeOffset.UtcNow;

        var verdict = snapshot.Failure is null && snapshot.FrameCount >= options.MinimumFrames
            ? "PASS"
            : "FAIL";

        var report = BuildReport(
            options,
            apartmentState,
            ownerProcess,
            hwnd,
            title,
            rectangle,
            targetHandle,
            startedAt,
            completedAt,
            verdict,
            snapshot,
            error: null);

        await EmitReportAsync(report, options.OutputPath);
        return verdict == "PASS" ? 0 : 2;
    }
    catch (WindowsCaptureSetupException error)
    {
        var completedAt = DateTimeOffset.UtcNow;
        var report = BuildReport(
            options,
            apartmentState,
            ownerProcess,
            hwnd,
            title,
            rectangle,
            targetHandle,
            startedAt,
            completedAt,
            "ERROR",
            snapshot: null,
            error: new ProbeError(
                error.Stage,
                error.GetType().Name,
                error.Message,
                $"0x{error.HResult:X8}",
                $"0x{error.NativeHResult:X8}",
                error.InnerException?.GetType().Name,
                error.InnerException?.Message,
                error.ItemWidth,
                error.ItemHeight,
                error.BufferWidth,
                error.BufferHeight,
                error.InitialSizeSource,
                error.DisplayName,
                error.StackTrace));

        await EmitReportAsync(report, options.OutputPath);
        Console.Error.WriteLine($"CAPTURE_PROBE_ERROR={error.GetType().Name}: {error.Message}");
        Console.Error.WriteLine(error);
        return 1;
    }
    catch (Exception error) when (error is not OutOfMemoryException)
    {
        var completedAt = DateTimeOffset.UtcNow;
        var report = BuildReport(
            options,
            apartmentState,
            ownerProcess,
            hwnd,
            title,
            rectangle,
            targetHandle,
            startedAt,
            completedAt,
            "ERROR",
            snapshot: null,
            error: new ProbeError(
                "probe-runtime",
                error.GetType().Name,
                error.Message,
                $"0x{error.HResult:X8}",
                error.InnerException is null ? null : $"0x{error.InnerException.HResult:X8}",
                error.InnerException?.GetType().Name,
                error.InnerException?.Message,
                0,
                0,
                0,
                0,
                null,
                null,
                error.StackTrace));

        await EmitReportAsync(report, options.OutputPath);
        Console.Error.WriteLine($"CAPTURE_PROBE_ERROR={error.GetType().Name}: {error.Message}");
        Console.Error.WriteLine(error);
        return 1;
    }
}

static ProbeReport BuildReport(
    ProbeOptions options,
    string apartmentState,
    Process ownerProcess,
    IntPtr hwnd,
    string title,
    WindowLocator.NativeRect rectangle,
    IntPtr targetHandle,
    DateTimeOffset startedAt,
    DateTimeOffset completedAt,
    string verdict,
    WindowsCaptureSnapshot? snapshot,
    ProbeError? error)
{
    return new ProbeReport(
        4,
        "CloudOS.WindowsCapture.Probe",
        startedAt,
        completedAt,
        verdict,
        apartmentState,
        options.ProcessId,
        new ProcessReport(
            ownerProcess.Id,
            ownerProcess.ProcessName,
            TryGetStartTime(ownerProcess),
            ownerProcess.SessionId),
        new WindowReport(
            $"0x{hwnd.ToInt64():X}",
            title,
            rectangle.Left,
            rectangle.Top,
            rectangle.Right - rectangle.Left,
            rectangle.Bottom - rectangle.Top),
        new TargetReport(
            options.CaptureKind.ToString().ToLowerInvariant(),
            $"0x{targetHandle.ToInt64():X}",
            FormatFactory(options.ItemFactoryKind)),
        snapshot is null
            ? null
            : new CaptureReport(
                options.MinimumFrames,
                options.Seconds,
                snapshot.FrameCount,
                snapshot.Width,
                snapshot.Height,
                snapshot.ResizeCount,
                snapshot.EmptyFrameCount,
                snapshot.InitialItemWidth,
                snapshot.InitialItemHeight,
                snapshot.InitialBufferWidth,
                snapshot.InitialBufferHeight,
                snapshot.InitialSizeSource,
                snapshot.ItemFactory,
                snapshot.FirstFrameAtUtc,
                snapshot.LastFrameAtUtc,
                snapshot.Failure),
        error);
}

static async Task EmitReportAsync(ProbeReport report, string? outputPath)
{
    var json = JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true });
    Console.WriteLine(json);

    if (outputPath is null) return;
    var fullPath = Path.GetFullPath(outputPath);
    Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
    await File.WriteAllTextAsync(fullPath, json + Environment.NewLine, new UTF8Encoding(false));
    Console.Error.WriteLine($"REPORT={fullPath}");
}

static string FormatFactory(WindowsCaptureItemFactoryKind factoryKind) => factoryKind switch
{
    WindowsCaptureItemFactoryKind.RawActivationFactory => "raw-activation-factory",
    WindowsCaptureItemFactoryKind.ProjectedFactory => "projected-factory",
    _ => factoryKind.ToString()
};

static string? TryGetStartTime(Process process)
{
    try { return process.StartTime.ToUniversalTime().ToString("O"); }
    catch { return null; }
}

internal sealed record ProbeReport(
    int SchemaVersion,
    string Probe,
    DateTimeOffset StartedAt,
    DateTimeOffset CompletedAt,
    string Verdict,
    string Apartment,
    int? RequestedPid,
    ProcessReport Process,
    WindowReport Window,
    TargetReport Target,
    CaptureReport? Capture,
    ProbeError? Error);

internal sealed record ProcessReport(int ProcessId, string ProcessName, string? StartTimeUtc, int SessionId);
internal sealed record WindowReport(string Handle, string Title, int Left, int Top, int Width, int Height);
internal sealed record TargetReport(string Kind, string Handle, string ItemFactory);
internal sealed record CaptureReport(
    int RequiredFrames,
    int ObservedSeconds,
    long FrameCount,
    int Width,
    int Height,
    int ResizeCount,
    int EmptyFrameCount,
    int InitialItemWidth,
    int InitialItemHeight,
    int InitialBufferWidth,
    int InitialBufferHeight,
    string InitialSizeSource,
    string ItemFactory,
    DateTimeOffset? FirstFrameAtUtc,
    DateTimeOffset? LastFrameAtUtc,
    string? Failure);
internal sealed record ProbeError(
    string Stage,
    string Type,
    string Message,
    string HResult,
    string? NativeHResult,
    string? InnerType,
    string? InnerMessage,
    int ItemWidth,
    int ItemHeight,
    int BufferWidth,
    int BufferHeight,
    string? InitialSizeSource,
    string? DisplayName,
    string? StackTrace);

internal sealed record ProbeOptions(
    int? ProcessId,
    IntPtr? WindowHandle,
    WindowsCaptureTargetKind CaptureKind,
    WindowsCaptureItemFactoryKind ItemFactoryKind,
    int Seconds,
    int MinimumFrames,
    string? OutputPath)
{
    public static ProbeOptions Parse(string[] args)
    {
        int? processId = null;
        IntPtr? hwnd = null;
        var captureKind = WindowsCaptureTargetKind.Window;
        var itemFactoryKind = WindowsCaptureItemFactoryKind.RawActivationFactory;
        var seconds = 3;
        var minimumFrames = 10;
        string? outputPath = null;

        for (var index = 0; index < args.Length; index++)
        {
            string NextValue(string option)
            {
                if (++index >= args.Length) throw new ArgumentException($"Missing value for {option}.");
                return args[index];
            }

            switch (args[index])
            {
                case "--pid":
                    processId = int.Parse(NextValue("--pid"));
                    if (processId <= 0) throw new ArgumentOutOfRangeException("--pid");
                    break;
                case "--hwnd":
                    hwnd = ParseHandle(NextValue("--hwnd"));
                    if (hwnd == IntPtr.Zero) throw new ArgumentOutOfRangeException("--hwnd");
                    break;
                case "--capture-kind":
                    captureKind = NextValue("--capture-kind").ToLowerInvariant() switch
                    {
                        "window" => WindowsCaptureTargetKind.Window,
                        "monitor" => WindowsCaptureTargetKind.Monitor,
                        var value => throw new ArgumentException($"Unknown capture kind: {value}")
                    };
                    break;
                case "--item-factory":
                    itemFactoryKind = NextValue("--item-factory").ToLowerInvariant() switch
                    {
                        "raw" => WindowsCaptureItemFactoryKind.RawActivationFactory,
                        "raw-activation-factory" => WindowsCaptureItemFactoryKind.RawActivationFactory,
                        "projected" => WindowsCaptureItemFactoryKind.ProjectedFactory,
                        "projected-factory" => WindowsCaptureItemFactoryKind.ProjectedFactory,
                        var value => throw new ArgumentException($"Unknown item factory: {value}")
                    };
                    break;
                case "--seconds":
                    seconds = int.Parse(NextValue("--seconds"));
                    if (seconds is < 1 or > 30) throw new ArgumentOutOfRangeException("--seconds");
                    break;
                case "--min-frames":
                    minimumFrames = int.Parse(NextValue("--min-frames"));
                    if (minimumFrames is < 1 or > 1000) throw new ArgumentOutOfRangeException("--min-frames");
                    break;
                case "--output":
                    outputPath = NextValue("--output");
                    break;
                default:
                    throw new ArgumentException($"Unknown option: {args[index]}");
            }
        }

        if ((processId.HasValue ? 1 : 0) + (hwnd.HasValue ? 1 : 0) != 1)
            throw new ArgumentException("Specify exactly one of --pid or --hwnd.");

        return new ProbeOptions(processId, hwnd, captureKind, itemFactoryKind, seconds, minimumFrames, outputPath);
    }

    private static IntPtr ParseHandle(string text)
    {
        var value = text.StartsWith("0x", StringComparison.OrdinalIgnoreCase)
            ? Convert.ToInt64(text[2..], 16)
            : long.Parse(text);
        return new IntPtr(value);
    }
}

internal static class WindowLocator
{
    private const uint MonitorDefaultToNearest = 2;

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    private delegate bool EnumWindowsCallback(IntPtr hwnd, IntPtr state);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr state);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    internal static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowRect(IntPtr hwnd, out NativeRect rectangle);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextW(IntPtr hwnd, StringBuilder text, int capacity);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);

    public static IntPtr FindBestTopLevelWindow(int processId)
    {
        var bestHandle = IntPtr.Zero;
        long bestArea = -1;
        var completed = EnumWindows((hwnd, _) =>
        {
            GetWindowThreadProcessId(hwnd, out var candidatePid);
            if (candidatePid != processId || !IsWindowVisible(hwnd)) return true;
            if (!GetWindowRect(hwnd, out var rectangle)) return true;
            var width = Math.Max(0, rectangle.Right - rectangle.Left);
            var height = Math.Max(0, rectangle.Bottom - rectangle.Top);
            var area = (long)width * height;
            if (area <= bestArea) return true;
            bestArea = area;
            bestHandle = hwnd;
            return true;
        }, IntPtr.Zero);
        if (!completed) throw new InvalidOperationException($"EnumWindows failed with Win32 error {Marshal.GetLastWin32Error()}.");
        return bestHandle;
    }

    public static string GetTitle(IntPtr hwnd)
    {
        var title = new StringBuilder(2048);
        GetWindowTextW(hwnd, title, title.Capacity);
        return title.ToString();
    }

    public static NativeRect GetRectangle(IntPtr hwnd)
    {
        if (!GetWindowRect(hwnd, out var rectangle))
            throw new InvalidOperationException($"GetWindowRect failed with Win32 error {Marshal.GetLastWin32Error()}.");
        return rectangle;
    }

    public static IntPtr GetNearestMonitor(IntPtr hwnd) => MonitorFromWindow(hwnd, MonitorDefaultToNearest);
}

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

    public static WinRtApartment EnterForProbe()
    {
        var result = RoInitialize(RoInitMultithreaded);
        if (result == 0)
            return new WinRtApartment(true, "mta-initialized-by-probe");
        if (result == SFalse)
            return new WinRtApartment(true, "mta-already-initialized");
        if (result == RpcEChangedMode)
            return new WinRtApartment(false, "existing-non-mta-apartment");

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
