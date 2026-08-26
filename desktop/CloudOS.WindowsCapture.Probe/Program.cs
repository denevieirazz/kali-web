using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using CloudOS.WindowsCapture;

if (args.Length == 0 || args.Contains("--help", StringComparer.OrdinalIgnoreCase))
{
    Console.WriteLine("CloudOS Windows capture probe");
    Console.WriteLine("  --pid <processId> | --hwnd <decimal|0xHEX>");
    Console.WriteLine("  [--seconds <1-30>] [--min-frames <1-1000>] [--output <path>]");
    return 64;
}

try
{
    var options = ProbeOptions.Parse(args);
    var hwnd = options.WindowHandle ?? WindowLocator.FindBestTopLevelWindow(options.ProcessId!.Value);
    if (hwnd == IntPtr.Zero) throw new InvalidOperationException("No visible top-level HWND was found for the requested process.");

    WindowLocator.GetWindowThreadProcessId(hwnd, out var ownerProcessId);
    using var ownerProcess = Process.GetProcessById(checked((int)ownerProcessId));
    var title = WindowLocator.GetTitle(hwnd);
    var rectangle = WindowLocator.GetRectangle(hwnd);

    using var capture = new WindowsCaptureSession(hwnd);
    var startedAt = DateTimeOffset.UtcNow;
    var snapshot = await capture.WaitForFramesAsync(
        options.MinimumFrames,
        TimeSpan.FromSeconds(options.Seconds));
    var completedAt = DateTimeOffset.UtcNow;

    var verdict = snapshot.Failure is null && snapshot.FrameCount >= options.MinimumFrames
        ? "PASS"
        : "FAIL";
    var report = new
    {
        schemaVersion = 2,
        probe = "CloudOS.WindowsCapture.Probe",
        startedAt,
        completedAt,
        verdict,
        requestedPid = options.ProcessId,
        process = new
        {
            processId = ownerProcess.Id,
            processName = ownerProcess.ProcessName,
            startTimeUtc = TryGetStartTime(ownerProcess),
            sessionId = ownerProcess.SessionId
        },
        window = new
        {
            handle = $"0x{hwnd.ToInt64():X}",
            title,
            left = rectangle.Left,
            top = rectangle.Top,
            width = rectangle.Right - rectangle.Left,
            height = rectangle.Bottom - rectangle.Top
        },
        capture = new
        {
            requiredFrames = options.MinimumFrames,
            observedSeconds = options.Seconds,
            snapshot.FrameCount,
            snapshot.Width,
            snapshot.Height,
            snapshot.ResizeCount,
            snapshot.EmptyFrameCount,
            initialItemSize = new
            {
                width = snapshot.InitialItemWidth,
                height = snapshot.InitialItemHeight
            },
            initialBufferSize = new
            {
                width = snapshot.InitialBufferWidth,
                height = snapshot.InitialBufferHeight,
                source = snapshot.InitialSizeSource
            },
            snapshot.FirstFrameAtUtc,
            snapshot.LastFrameAtUtc,
            snapshot.Failure
        }
    };

    var json = JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true });
    Console.WriteLine(json);
    if (options.OutputPath is not null)
    {
        var fullPath = Path.GetFullPath(options.OutputPath);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        await File.WriteAllTextAsync(fullPath, json + Environment.NewLine, new UTF8Encoding(false));
        Console.Error.WriteLine($"REPORT={fullPath}");
    }

    return verdict == "PASS" ? 0 : 2;
}
catch (Exception error) when (error is not OutOfMemoryException)
{
    Console.Error.WriteLine($"CAPTURE_PROBE_ERROR={error.GetType().Name}: {error.Message}");
    Console.Error.WriteLine(error);
    return 1;
}

static string? TryGetStartTime(Process process)
{
    try { return process.StartTime.ToUniversalTime().ToString("O"); }
    catch { return null; }
}

internal sealed record ProbeOptions(int? ProcessId, IntPtr? WindowHandle, int Seconds, int MinimumFrames, string? OutputPath)
{
    public static ProbeOptions Parse(string[] args)
    {
        int? processId = null;
        IntPtr? hwnd = null;
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

        return new ProbeOptions(processId, hwnd, seconds, minimumFrames, outputPath);
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
}
