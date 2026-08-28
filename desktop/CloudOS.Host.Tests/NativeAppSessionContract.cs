using System.Runtime.CompilerServices;

internal static class NativeAppSessionContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        if (Environment.GetCommandLineArgs().Any(argument =>
            argument.StartsWith("--native-contained-fixture-", StringComparison.Ordinal)))
            return;

        var desktopRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));
        var sessionPath = Path.Combine(desktopRoot, "CloudOS.Host", "Native", "NativeAppSession.cs");
        if (!File.Exists(sessionPath))
            throw new InvalidOperationException($"NativeAppSession source was not found at {sessionPath}.");

        var source = File.ReadAllText(sessionPath);
        Assert(source.Contains("internal int RootProcessId { get; }", StringComparison.Ordinal),
            "Native session identity must retain its immutable launch/Job root.");
        Assert(source.Contains("internal long CurrentWindowHandle { get; private set; }", StringComparison.Ordinal),
            "HWND must be mutable session state rather than session identity.");
        Assert(source.Contains("internal void BindWindow(int processId, long windowHandle)", StringComparison.Ordinal),
            "Native session must support rebinding to a replacement HWND.");
        Assert(source.Contains("WindowGeneration++", StringComparison.Ordinal),
            "Native session must expose HWND generation changes without changing session identity.");

        Console.WriteLine("PASS job-owned native app session contract");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
