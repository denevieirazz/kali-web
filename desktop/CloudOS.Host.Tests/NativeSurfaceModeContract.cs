using System.Runtime.CompilerServices;

internal static class NativeSurfaceModeContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        var repoRoot = RepoRoot();
        var bridgePath = Path.Combine(repoRoot, "desktop", "CloudOS.Host", "Bridge", "WebMessageBridge.cs");
        var projectPath = Path.Combine(repoRoot, "desktop", "CloudOS.Host", "CloudOS.Host.csproj");
        var captureProject = Path.Combine(repoRoot, "desktop", "CloudOS.WindowsCapture", "CloudOS.WindowsCapture.csproj");
        var presenterProject = Path.Combine(repoRoot, "desktop", "CloudOS.WindowsCapture.Presenter", "CloudOS.WindowsCapture.Presenter.csproj");
        var bridge = File.ReadAllText(bridgePath);
        var project = File.ReadAllText(projectPath);

        Assert(bridge.Contains("containmentMode = \"captured-surface\"", StringComparison.Ordinal),
            "Production Host must expose the WGC/D3D captured-surface compatibility renderer.");
        Assert(bridge.Contains("containmentMode = \"anchored-overlay\"", StringComparison.Ordinal),
            "Native HWND anchored-overlay must remain available as a fallback renderer.");
        Assert(project.Contains("CloudOS.WindowsCapture\\CloudOS.WindowsCapture.csproj", StringComparison.Ordinal)
            && project.Contains("CloudOS.WindowsCapture.Presenter\\CloudOS.WindowsCapture.Presenter.csproj", StringComparison.Ordinal),
            "The Host must reference both production capture projects.");
        Assert(File.Exists(captureProject) && File.Exists(presenterProject),
            "Production WGC/D3D capture and presenter projects must exist.");
        Assert(!File.Exists(Path.Combine(repoRoot, "desktop", "CloudOS.Host", "Native", "NativeSurfaceMode.cs")),
            "Renderer selection must remain Host-owned instead of trusting web-provided native mode state.");

        Console.WriteLine("PASS native Windows hybrid surface contract");
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
