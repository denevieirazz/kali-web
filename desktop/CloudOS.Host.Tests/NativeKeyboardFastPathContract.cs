using System.Runtime.CompilerServices;
using CloudOS.Host.Native;

internal static class NativeKeyboardFastPathContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        if (Environment.GetCommandLineArgs().Any(argument =>
            argument.StartsWith("--native-contained-fixture-", StringComparison.Ordinal)))
            return;

        var router = new NativeKeyboardShortcutRouter();
        var ordinaryA = new NativeKeyboardInput(0x41, false, false, false);
        var ordinaryW = new NativeKeyboardInput(0x57, false, false, false);
        var injectedA = new NativeKeyboardInput(0x41, false, false, true);
        var leftWinDown = new NativeKeyboardInput(0x5B, false, false, false);
        var leftWinUp = new NativeKeyboardInput(0x5B, true, false, false);
        var altTab = new NativeKeyboardInput(0x09, false, true, false);
        var altF4 = new NativeKeyboardInput(0x73, false, true, false);

        Assert(!router.RequiresRouting(ordinaryA), "Ordinary A input must bypass foreground routing when no shortcut is captured.");
        Assert(!router.RequiresRouting(ordinaryW), "Ordinary W input must bypass foreground routing when no shortcut is captured.");
        Assert(!router.RequiresRouting(injectedA), "Unrelated injected input must bypass foreground routing.");
        Assert(router.RequiresRouting(leftWinDown), "Windows-key input must always enter the routing policy.");
        Assert(router.RequiresRouting(altTab), "Alt+Tab must always enter the routing policy.");
        Assert(router.RequiresRouting(altF4), "Alt+F4 must always enter the routing policy.");

        var winDecision = router.Route(leftWinDown, cloudOsForeground: true);
        Assert(winDecision.Suppress && router.HasCapture, "A captured Win sequence must remain active after Win-down.");
        Assert(router.RequiresRouting(ordinaryA), "All keys must route while a Win sequence is captured so chord state remains exact.");
        _ = router.Route(ordinaryA, cloudOsForeground: true);
        _ = router.Route(leftWinUp, cloudOsForeground: true);
        Assert(!router.HasCapture, "Win release must restore the ordinary-input fast path.");
        Assert(!router.RequiresRouting(ordinaryA), "Ordinary input must return to the fast path after captured release cleanup.");

        Console.WriteLine("PASS native keyboard ordinary-input fast path contract");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
