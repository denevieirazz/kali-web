using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using CloudOS.WindowsCapture;

var helpRequested = args.Contains("--help", StringComparer.OrdinalIgnoreCase);
if (args.Length == 0 || helpRequested)
{
    Console.WriteLine("CloudOS Windows capture probe");
    Console.WriteLine("  --pid <processId> | --hwnd <decimal|0xHEX>");
    Console.WriteLine("  [--capture-kind window|monitor]");
    Console.WriteLine("  [--item-factory raw|projected]");
    Console.WriteLine("  [--item-projection projected|marshal-interface]");
    Console.WriteLine("  [--abi-lifetime release|hold]");
    Console.WriteLine("  [--seconds <1-30>] [--min-frames <1-1000>] [--output <path>]");
    return helpRequested ? 0 : 64;
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
    var windowDiagnostics = WindowLocator.GetDiagnostics(hwnd);

    var targetKind = options.CaptureKind;
    var targetHandle = targetKind == WindowsCaptureTargetKind.Window
        ? hwnd
        : WindowLocator.GetNearestMonitor(hwnd);
    if (targetHandle == IntPtr.Zero)
        throw new InvalidOperationException($"Could not resolve a {targetKind} capture handle.");

    var startedAt = DateTimeOffset.UtcNow;
    try
    {
        using var capture = new WindowsCaptureSession(
            targetHandle,
            targetKind,
            options.ItemFactoryKind,
            options.ItemProjectionKind,
            options.AbiLifetimeKind);

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
            windowDiagnostics,
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
            windowDiagnostics,
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
            windowDiagnostics,
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
    WindowDiagnostics windowDiagnostics,
    IntPtr targetHandle,
    DateTimeOffset startedAt,
    DateTimeOffset completedAt,
    string verdict,
    WindowsCaptureSnapshot? snapshot,
    ProbeError? error)
{
    return new ProbeReport(
        5,
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
        windowDiagnostics,
        new TargetReport(
            options.CaptureKind.ToString().ToLowerInvariant(),
            $"0x{targetHandle.ToInt64():X}",
            FormatFactory(options.ItemFactoryKind),
            FormatProjection(options.ItemProjectionKind),
            FormatLifetime(options.AbiLifetimeKind)),
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
                snapshot.ItemProjection,
                snapshot.AbiLifetime,
                snapshot.HoldsAbiReference,
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

static string FormatProjection(WindowsCaptureItemProjectionKind projectionKind) => projectionKind switch
{
    WindowsCaptureItemProjectionKind.ProjectedTypeFromAbi => "projected-type-from-abi",
    WindowsCaptureItemProjectionKind.MarshalInterfaceFromAbi => "marshal-interface-from-abi",
    _ => projectionKind.ToString()
};

static string FormatLifetime(WindowsCaptureAbiLifetimeKind lifetimeKind) => lifetimeKind switch
{
    WindowsCaptureAbiLifetimeKind.ReleaseAfterProjection => "release-after-projection",
    WindowsCaptureAbiLifetimeKind.HoldUntilSessionDispose => "hold-until-session-dispose",
    _ => lifetimeKind.ToString()
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
    WindowDiagnostics Window,
    TargetReport Target,
    CaptureReport? Capture,
    ProbeError? Error);

internal sealed record ProcessReport(int ProcessId, string ProcessName, string? StartTimeUtc, int SessionId);

internal sealed record WindowDiagnostics(
    string Handle,
    string Title,
    string ClassName,
    int Left,
    int Top,
    int Width,
    int Height,
    bool Visible,
    bool Iconic,
    bool Hung,
    bool Cloaked,
    bool CloakKnown,
    string Style,
    string ExtendedStyle,
    string OwnerHandle,
    string RootOwnerHandle,
    string MonitorHandle,
    uint ThreadId,
    uint ProcessId,
    uint Dpi,
    bool DisplayAffinityKnown,
    string? DisplayAffinity);

internal sealed record TargetReport(
    string Kind,
    string Handle,
    string ItemFactory,
    string ItemProjection,
    string AbiLifetime);

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
    string ItemProjection,
    string AbiLifetime,
    bool HoldsAbiReference,
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
    WindowsCaptureItemProjectionKind ItemProjectionKind,
    WindowsCaptureAbiLifetimeKind AbiLifetimeKind,
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
        var itemProjectionKind = WindowsCaptureItemProjectionKind.MarshalInterfaceFromAbi;
        var abiLifetimeKind = WindowsCaptureAbiLifetimeKind.HoldUntilSessionDispose;
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
                case "--item-projection":
                    itemProjectionKind = NextValue("--item-projection").ToLowerInvariant() switch
                    {
                        "projected" => WindowsCaptureItemProjectionKind.ProjectedTypeFromAbi,
                        "projected-type-from-abi" => WindowsCaptureItemProjectionKind.ProjectedTypeFromAbi,
                        "marshal-interface" => WindowsCaptureItemProjectionKind.MarshalInterfaceFromAbi,
                        "marshal-interface-from-abi" => WindowsCaptureItemProjectionKind.MarshalInterfaceFromAbi,
                        var value => throw new ArgumentException($"Unknown item projection: {value}")
                    };
                    break;
                case "--abi-lifetime":
                    abiLifetimeKind = NextValue("--abi-lifetime").ToLowerInvariant() switch
                    {
                        "release" => WindowsCaptureAbiLifetimeKind.ReleaseAfterProjection,
                        "release-after-projection" => WindowsCaptureAbiLifetimeKind.ReleaseAfterProjection,
                        "hold" => WindowsCaptureAbiLifetimeKind.HoldUntilSessionDispose,
                        "hold-until-session-dispose" => WindowsCaptureAbiLifetimeKind.HoldUntilSessionDispose,
                        var value => throw new ArgumentException($"Unknown ABI lifetime: {value}")
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

        return new ProbeOptions(
            processId,
            hwnd,
            captureKind,
            itemFactoryKind,
            itemProjectionKind,
            abiLifetimeKind,
            seconds,
            minimumFrames,
            outputPath);
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
    private const uint GaRootOwner = 3;
    private const uint GwOwner = 4;
    private const int GwlStyle = -16;
    private const int GwlExStyle = -20;
    private const uint DwmwaCloaked = 14;

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    private delegate bool EnumWindowsCallback(IntPtr hwnd, IntPtr state);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr state);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern bool IsHungAppWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    internal static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowRect(IntPtr hwnd, out NativeRect rectangle);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextW(IntPtr hwnd, StringBuilder text, int capacity);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassNameW(IntPtr hwnd, StringBuilder className, int capacity);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hwnd, uint command);

    [DllImport("user32.dll")]
    private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hwnd, int index);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)]
    private static extern int GetWindowLong32(IntPtr hwnd, int index);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowDisplayAffinity(IntPtr hwnd, out uint affinity);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, uint attribute, out uint value, uint valueSize);

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

    public static WindowDiagnostics GetDiagnostics(IntPtr hwnd)
    {
        var rectangle = GetRectangle(hwnd);
        var title = GetTitle(hwnd);
        var className = GetClassName(hwnd);
        var threadId = GetWindowThreadProcessId(hwnd, out var processId);
        var monitor = GetNearestMonitor(hwnd);
        var owner = GetWindow(hwnd, GwOwner);
        var rootOwner = GetAncestor(hwnd, GaRootOwner);
        var style = GetWindowLongPtr(hwnd, GwlStyle).ToInt64();
        var extendedStyle = GetWindowLongPtr(hwnd, GwlExStyle).ToInt64();

        var cloakedValue = 0u;
        var cloakKnown = DwmGetWindowAttribute(hwnd, DwmwaCloaked, out cloakedValue, sizeof(uint)) == 0;

        var affinityKnown = GetWindowDisplayAffinity(hwnd, out var affinity);
        return new WindowDiagnostics(
            $"0x{hwnd.ToInt64():X}",
            title,
            className,
            rectangle.Left,
            rectangle.Top,
            rectangle.Right - rectangle.Left,
            rectangle.Bottom - rectangle.Top,
            IsWindowVisible(hwnd),
            IsIconic(hwnd),
            IsHungAppWindow(hwnd),
            cloakKnown && cloakedValue != 0,
            cloakKnown,
            $"0x{unchecked((ulong)style):X}",
            $"0x{unchecked((ulong)extendedStyle):X}",
            $"0x{owner.ToInt64():X}",
            $"0x{rootOwner.ToInt64():X}",
            $"0x{monitor.ToInt64():X}",
            threadId,
            processId,
            GetDpiForWindow(hwnd),
            affinityKnown,
            affinityKnown ? $"0x{affinity:X8}" : null);
    }

    public static string GetTitle(IntPtr hwnd)
    {
        var title = new StringBuilder(2048);
        _ = GetWindowTextW(hwnd, title, title.Capacity);
        return title.ToString();
    }

    private static string GetClassName(IntPtr hwnd)
    {
        var className = new StringBuilder(512);
        _ = GetClassNameW(hwnd, className, className.Capacity);
        return className.ToString();
    }

    public static NativeRect GetRectangle(IntPtr hwnd)
    {
        if (!GetWindowRect(hwnd, out var rectangle))
            throw new InvalidOperationException($"GetWindowRect failed with Win32 error {Marshal.GetLastWin32Error()}.");
        return rectangle;
    }

    public static IntPtr GetNearestMonitor(IntPtr hwnd) => MonitorFromWindow(hwnd, MonitorDefaultToNearest);

    private static IntPtr GetWindowLongPtr(IntPtr hwnd, int index) =>
        IntPtr.Size == 8 ? GetWindowLongPtr64(hwnd, index) : new IntPtr(GetWindowLong32(hwnd, index));
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
