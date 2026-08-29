using System.Runtime.CompilerServices;

internal static class NativeSurfaceModeContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        var repoRoot = RepoRoot();
        var bridgePath = Path.Combine(repoRoot, "desktop", "CloudOS.Host", "Bridge", "WebMessageBridge.cs");
        var projectPath = Path.Combine(repoRoot, "desktop", "CloudOS.Host", "CloudOS.Host.csproj");
        var bridge = File.ReadAllText(bridgePath);
        var project = File.ReadAllText(projectPath);

        Assert(bridge.Contains("containmentMode = \"anchored-overlay\"", StringComparison.Ordinal),
            "Native HWND anchored-overlay must remain the Windows application renderer.");
        Assert(!bridge.Contains("captured-surface", StringComparison.OrdinalIgnoreCase)
            && !bridge.Contains("CapturedSurface", StringComparison.Ordinal),
            "The production bridge must not contain a captured-surface renderer.");
        Assert(!project.Contains("CloudOS.WindowsCapture", StringComparison.Ordinal),
            "The Host must not reference Windows capture projects.");
        Assert(!File.Exists(Path.Combine(repoRoot, "desktop", "CloudOS.Host", "Native", "NativeSurfaceMode.cs")),
            "The capture renderer selector must be removed.");

        Console.WriteLine("PASS native Windows surface-only contract");
    }

    private static string RepoRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            if (Directory.Exists(Path.Combine(current.FullName, ".git"))) return current.FullName;
            current = current.Parent;
        }
        throw new InvalidOperationException("Repository root not found.");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}