using System.Runtime.CompilerServices;

internal static class NativeSurfaceModeContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        if (Environment.GetCommandLineArgs().Any(argument =>
            argument.StartsWith("--native-contained-fixture-", StringComparison.Ordinal)))
            return;

        var desktopRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));
        var modePath = Path.Combine(desktopRoot, "CloudOS.Host", "Native", "NativeSurfaceMode.cs");
        var bridgePath = Path.Combine(desktopRoot, "CloudOS.Host", "Bridge", "WebMessageBridge.cs");
        if (!File.Exists(modePath) || !File.Exists(bridgePath))
            throw new InvalidOperationException("Native surface source files were not found.");

        var mode = File.ReadAllText(modePath);
        var bridge = File.ReadAllText(bridgePath);

        Assert(mode.Contains("return NativeSurfaceRenderMode.NativeOverlay;", StringComparison.Ordinal),
            "Native overlay must be the fail-safe/default Windows app renderer.");
        Assert(mode.Contains("CLOUDOS_NATIVE_SURFACE_MODE", StringComparison.Ordinal),
            "The capture fallback must be controlled by an explicit environment switch.");
        Assert(bridge.Contains(
                "NativeSurfaceMode.Current == NativeSurfaceRenderMode.CapturedSurface",
                StringComparison.Ordinal),
            "The bridge must not initialize captured-surface unless capture was explicitly requested.");
        Assert(bridge.Contains("containmentMode = \"anchored-overlay\"", StringComparison.Ordinal),
            "The real native HWND overlay path must remain a first-class containment mode.");

        Console.WriteLine("PASS native Windows surface default contract");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
