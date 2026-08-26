using System.Reflection;
using System.Runtime.CompilerServices;
using CloudOS.Host.Native;

internal static class NativeScriptLaunchContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        if (Environment.GetCommandLineArgs().Any(argument =>
            argument.StartsWith("--native-contained-fixture-", StringComparison.Ordinal)))
            return;

        var systemRoot = Environment.GetEnvironmentVariable("SystemRoot")
            ?? throw new InvalidOperationException("SystemRoot is unavailable for the Windows script containment test.");
        var commandProcessor = Path.Combine(systemRoot, "System32", "cmd.exe");
        if (!File.Exists(commandProcessor))
            throw new InvalidOperationException("System32 cmd.exe is unavailable for the Windows script containment test.");

        using var temp = new ScriptFixtureDirectory();
        var scriptPath = Path.Combine(temp.Path, "launch gui descendant.cmd");
        File.WriteAllText(scriptPath, BuildScriptCommand(), System.Text.Encoding.ASCII);

        var spec = NativeProcessLaunchSpec.Create(
            commandProcessor,
            ["/d", "/s", "/v:off", "/c", scriptPath],
            temp.Path);
        using var lease = NativeContainedProcessLauncher.StartSuspended(spec);
        using var windows = new NativeWindowManager();
        windows.TrackLaunchedProcess(lease.Process);
        lease.Resume();

        NativeWindowSnapshot? childWindow = null;
        IReadOnlyList<int> members = [];
        var deadline = DateTimeOffset.UtcNow.AddSeconds(8);
        while (DateTimeOffset.UtcNow < deadline && childWindow is null)
        {
            members = NativeContainedJobTracker.Synchronize(lease, windows);
            windows.Refresh();
            childWindow = windows.GetWindows()
                .FirstOrDefault(window => window.ProcessId != lease.ProcessId
                    && window.Title == "CloudOS Native Containment Fixture");
            if (childWindow is null) Thread.Sleep(25);
        }

        Assert(childWindow is not null,
            "A GUI descendant launched through cmd.exe /c must be correlated through Job membership.");
        var quarantined = childWindow
            ?? throw new InvalidOperationException("The script GUI descendant was not observed.");
        Assert(members.Contains(quarantined.ProcessId),
            "The script GUI descendant PID must remain inside the same containment Job.");
        Assert(windows.IsTrackedProcess(quarantined.ProcessId),
            "The script GUI descendant must receive a native window capability before exposure.");
        Assert(!quarantined.IsVisible,
            "The script GUI descendant must remain hidden until CloudOS explicitly attaches it.");
        Assert(lease.TryTerminate(3_000, out var terminationError),
            terminationError ?? "The script containment Job did not terminate.");

        Console.WriteLine("PASS cmd script GUI descendant containment contract");
    }

    private static string BuildScriptCommand()
    {
        var executable = Environment.ProcessPath
            ?? throw new InvalidOperationException("The Host test process path is unavailable.");
        var pieces = new List<string> { QuoteCmdPath(executable) };
        if (string.Equals(Path.GetFileNameWithoutExtension(executable), "dotnet", StringComparison.OrdinalIgnoreCase))
            pieces.Add(QuoteCmdPath(Assembly.GetExecutingAssembly().Location));
        pieces.Add("--native-contained-fixture-window");
        return "@echo off\r\n" + string.Join(" ", pieces) + "\r\nexit /b %ERRORLEVEL%\r\n";
    }

    private static string QuoteCmdPath(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.IndexOfAny(['\0', '\r', '\n', '"']) >= 0)
            throw new InvalidOperationException("The script fixture contains an invalid executable path.");
        return $"\"{value}\"";
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private sealed class ScriptFixtureDirectory : IDisposable
    {
        internal string Path { get; } = System.IO.Path.Combine(
            System.IO.Path.GetTempPath(),
            "cloudos host script fixture",
            Guid.NewGuid().ToString("N"));

        internal ScriptFixtureDirectory() => Directory.CreateDirectory(Path);

        public void Dispose()
        {
            try { Directory.Delete(Path, recursive: true); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                Console.Error.WriteLine($"WARN script fixture cleanup failed: {error.GetType().Name}");
            }
        }
    }
}
