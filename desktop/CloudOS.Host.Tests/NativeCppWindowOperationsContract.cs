using System.Runtime.CompilerServices;

internal static class NativeCppWindowOperationsContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        if (Environment.GetCommandLineArgs().Any(argument =>
            argument.StartsWith("--native-contained-fixture-", StringComparison.Ordinal)))
            return;

        var desktopRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));
        var nativeRoot = Path.Combine(desktopRoot, "CloudOS.NativeRuntime");
        var headerPath = Path.Combine(nativeRoot, "include", "cloudos_native_runtime.h");
        var sourcePath = Path.Combine(nativeRoot, "src", "cloudos_native_runtime.cpp");
        var bridgePath = Path.Combine(desktopRoot, "CloudOS.Host", "Native", "CloudOsNativeRuntime.cs");
        var managerPath = Path.Combine(desktopRoot, "CloudOS.Host", "Native", "NativeWindowManager.cs");

        foreach (var path in new[] { headerPath, sourcePath, bridgePath, managerPath })
            if (!File.Exists(path)) throw new InvalidOperationException($"Native HWND runtime source was not found at {path}.");

        var header = File.ReadAllText(headerPath);
        var source = File.ReadAllText(sourcePath);
        var bridge = File.ReadAllText(bridgePath);
        var manager = File.ReadAllText(managerPath);

        Assert(header.Contains("CLOUDOS_NATIVE_RUNTIME_ABI 5u", StringComparison.Ordinal),
            "The C++ ABI must expose the current HWND/runtime generation.");
        Assert(header.Contains("cloudos_native_window_attach", StringComparison.Ordinal)
            && header.Contains("cloudos_native_window_layout", StringComparison.Ordinal)
            && header.Contains("cloudos_native_window_focus", StringComparison.Ordinal),
            "The C++ ABI must own attach/layout/focus operations for real Windows surfaces.");
        Assert(source.Contains("SetWindowLongPtrW", StringComparison.Ordinal)
            && source.Contains("SetWindowPos", StringComparison.Ordinal)
            && source.Contains("SetForegroundWindow", StringComparison.Ordinal),
            "The native runtime must execute real Win32 window operations rather than proxy pixels through Web code.");
        Assert(bridge.Contains("ExpectedAbi = 5", StringComparison.Ordinal)
            && bridge.Contains("NativeWindowAttach(", StringComparison.Ordinal)
            && bridge.Contains("NativeWindowLayout(", StringComparison.Ordinal)
            && bridge.Contains("NativeWindowFocus(", StringComparison.Ordinal),
            "The Host C ABI bridge must bind the current C++ HWND operations generation.");
        Assert(manager.Contains("CloudOsNativeRuntime.TryAttachWindow(", StringComparison.Ordinal)
            && manager.Contains("CloudOsNativeRuntime.TryLayoutWindow(", StringComparison.Ordinal)
            && manager.Contains("CloudOsNativeRuntime.TryFocusWindow(", StringComparison.Ordinal),
            "NativeWindowManager must prefer the C++ window engine after capability validation.");

        Console.WriteLine("PASS C++ native HWND operations contract");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
