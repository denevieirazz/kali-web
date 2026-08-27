using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using CloudOS.WindowsCapture;

if (args.Length == 0 || args.Contains("--help", StringComparer.OrdinalIgnoreCase))
{
    Console.WriteLine("CloudOS Windows captured-surface input probe");
    Console.WriteLine("  --pid <processId> [--output <path>]");
    return args.Contains("--help", StringComparer.OrdinalIgnoreCase) ? 0 : 64;
}

try
{
    var options = InputProbeOptions.Parse(args);
    return await RunAsync(options);
}
catch (Exception error) when (error is not OutOfMemoryException)
{
    Console.Error.WriteLine($"INPUT_PROBE_FATAL={error.GetType().Name}: {error.Message}");
    Console.Error.WriteLine(error);
    return 1;
}

static async Task<int> RunAsync(InputProbeOptions options)
{
    using var process = Process.GetProcessById(options.ProcessId);
    var hwnd = await WaitForMainWindowAsync(process, TimeSpan.FromSeconds(10));
    var beforeTitle = ReadWindowText(hwnd);

    const int generation = 1;
    var gate = new WindowsCaptureInputGate(generation);
    gate.SetActive(true);
    var injector = new WindowsCaptureTargetedInputInjector(hwnd, gate);

    // The deterministic WinForms fixture owns this button rectangle in parent-client pixels.
    const int buttonX = 80;
    const int buttonY = 270;

    var pointerDown = injector.InjectPointer(new WindowsCapturePointerInput(
        Sequence: 1,
        Generation: generation,
        Kind: WindowsCapturePointerEventKind.ButtonDown,
        Button: WindowsCapturePointerButton.Left,
        ClientPixelX: buttonX,
        ClientPixelY: buttonY,
        WheelDelta: 0,
        Shift: false,
        Control: false,
        Alt: false));

    var pointerUp = injector.InjectPointer(new WindowsCapturePointerInput(
        Sequence: 2,
        Generation: generation,
        Kind: WindowsCapturePointerEventKind.ButtonUp,
        Button: WindowsCapturePointerButton.Left,
        ClientPixelX: buttonX,
        ClientPixelY: buttonY,
        WheelDelta: 0,
        Shift: false,
        Control: false,
        Alt: false));

    var keyDown = injector.InjectKey(new WindowsCaptureKeyInput(
        Sequence: 3,
        Generation: generation,
        Kind: WindowsCaptureKeyEventKind.KeyDown,
        VirtualKey: 0x41,
        ScanCode: 0x1E,
        Extended: false,
        Repeat: false));

    var keyUp = injector.InjectKey(new WindowsCaptureKeyInput(
        Sequence: 4,
        Generation: generation,
        Kind: WindowsCaptureKeyEventKind.KeyUp,
        VirtualKey: 0x41,
        ScanCode: 0x1E,
        Extended: false,
        Repeat: false));

    var replay = injector.InjectKey(new WindowsCaptureKeyInput(
        Sequence: 4,
        Generation: generation,
        Kind: WindowsCaptureKeyEventKind.KeyDown,
        VirtualKey: 0x42,
        ScanCode: 0x30,
        Extended: false,
        Repeat: false));

    var staleGeneration = injector.InjectKey(new WindowsCaptureKeyInput(
        Sequence: 5,
        Generation: generation + 1,
        Kind: WindowsCaptureKeyEventKind.KeyDown,
        VirtualKey: 0x43,
        ScanCode: 0x2E,
        Extended: false,
        Repeat: false));

    var deadline = DateTimeOffset.UtcNow.AddSeconds(2);
    string afterTitle;
    do
    {
        await Task.Delay(50);
        afterTitle = ReadWindowText(hwnd);
        if (afterTitle.Contains("clicks=1", StringComparison.Ordinal) &&
            afterTitle.Contains("keys=1", StringComparison.Ordinal) &&
            afterTitle.Contains("last=A", StringComparison.Ordinal))
            break;
    }
    while (DateTimeOffset.UtcNow < deadline);

    var observedClick = afterTitle.Contains("clicks=1", StringComparison.Ordinal);
    var observedKey = afterTitle.Contains("keys=1", StringComparison.Ordinal) &&
                      afterTitle.Contains("last=A", StringComparison.Ordinal);
    var replayRejected = replay.Status == WindowsCaptureInputInjectionStatus.Rejected &&
                         replay.Rejection == WindowsCaptureInputRejection.ReplayedSequence;
    var staleRejected = staleGeneration.Status == WindowsCaptureInputInjectionStatus.Rejected &&
                        staleGeneration.Rejection == WindowsCaptureInputRejection.StaleGeneration;

    var pass = pointerDown.Delivered &&
               pointerUp.Delivered &&
               keyDown.Delivered &&
               keyUp.Delivered &&
               replayRejected &&
               staleRejected &&
               observedClick &&
               observedKey;

    var report = new
    {
        schemaVersion = 1,
        probe = "CloudOS.WindowsCapture.InputProbe",
        verdict = pass ? "PASS" : "FAIL",
        processId = options.ProcessId,
        hwnd = $"0x{hwnd.ToInt64():X}",
        beforeTitle,
        afterTitle,
        observed = new
        {
            click = observedClick,
            key = observedKey,
            replayRejected,
            staleGenerationRejected = staleRejected
        },
        injections = new
        {
            pointerDown,
            pointerUp,
            keyDown,
            keyUp,
            replay,
            staleGeneration
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

    return pass ? 0 : 2;
}

static async Task<IntPtr> WaitForMainWindowAsync(Process process, TimeSpan timeout)
{
    var deadline = DateTimeOffset.UtcNow + timeout;
    while (DateTimeOffset.UtcNow < deadline)
    {
        if (process.HasExited)
            throw new InvalidOperationException($"Target process exited before input test. exit={process.ExitCode}");
        process.Refresh();
        if (process.MainWindowHandle != IntPtr.Zero) return process.MainWindowHandle;
        await Task.Delay(50);
    }
    throw new TimeoutException("Target process did not expose a MainWindowHandle within the timeout.");
}

static string ReadWindowText(IntPtr hwnd)
{
    var length = GetWindowTextLength(hwnd);
    var builder = new StringBuilder(Math.Max(256, length + 1));
    if (GetWindowText(hwnd, builder, builder.Capacity) == 0 && length > 0)
        throw new InvalidOperationException($"GetWindowText failed: {Marshal.GetLastWin32Error()}");
    return builder.ToString();
}

[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
static extern int GetWindowTextLength(IntPtr hWnd);

internal sealed record InputProbeOptions(int ProcessId, string? OutputPath)
{
    public static InputProbeOptions Parse(string[] args)
    {
        int? pid = null;
        string? output = null;
        for (var index = 0; index < args.Length; index++)
        {
            switch (args[index])
            {
                case "--pid":
                    pid = ParsePositiveInt(ReadValue(args, ref index, "--pid"), "--pid");
                    break;
                case "--output":
                    output = ReadValue(args, ref index, "--output");
                    break;
                default:
                    throw new ArgumentException($"Unknown argument: {args[index]}");
            }
        }

        if (pid is null) throw new ArgumentException("--pid is required.");
        return new InputProbeOptions(pid.Value, output);
    }

    private static string ReadValue(string[] args, ref int index, string name)
    {
        if (++index >= args.Length) throw new ArgumentException($"{name} requires a value.");
        return args[index];
    }

    private static int ParsePositiveInt(string value, string name)
    {
        if (!int.TryParse(value, out var parsed) || parsed <= 0)
            throw new ArgumentOutOfRangeException(name, $"{name} must be a positive integer.");
        return parsed;
    }
}
