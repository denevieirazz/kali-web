using System.Runtime.CompilerServices;
using CloudOS.Host.Native;

internal static class NativeKeyboardShortcutContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        NormalApplicationInputPassesThrough();
        BareWindowsKeyRoutesToCloudOsStart();
        WindowsShellEscapeChordsAreConsumed();
        AltTabRoutesOncePerPress();
        AltF4RoutesOncePerPress();
        InjectedReservedInputCannotInvokeCloudOsActions();
        UnrelatedForegroundWindowsRemainUntouched();
        FocusLossCannotTriggerDeferredCloudOsActions();
        Console.WriteLine("PASS native keyboard shortcuts are scoped and fail closed");
    }

    private static void NormalApplicationInputPassesThrough()
    {
        var router = new NativeKeyboardShortcutRouter();
        AssertPass(router.Route(new NativeKeyboardInput(0x57, false, false, false), true), "W must reach the focused application.");
        AssertPass(router.Route(new NativeKeyboardInput(0x41, false, false, false), true), "Letters must reach the focused application.");
        AssertPass(router.Route(new NativeKeyboardInput(0x31, false, false, false), true), "Numbers must reach the focused application.");
    }

    private static void BareWindowsKeyRoutesToCloudOsStart()
    {
        var router = new NativeKeyboardShortcutRouter();
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyLeftWin, false, false, false), true), null, "Win down must be captured without toggling early.");
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyLeftWin, true, false, false), true), NativeHostShortcut.ToggleStartMenu, "Bare Win release must toggle CloudOS Start.");
    }

    private static void WindowsShellEscapeChordsAreConsumed()
    {
        foreach (var key in new[] { NativeKeyboardShortcutRouter.VirtualKeyR, NativeKeyboardShortcutRouter.VirtualKeyD })
        {
            var router = new NativeKeyboardShortcutRouter();
            AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyLeftWin, false, false, false), true), null, "Win chord must start captured.");
            AssertConsumed(router.Route(new NativeKeyboardInput(key, false, false, false), true), null, "Win+R/Win+D keydown must not escape to Windows.");
            AssertConsumed(router.Route(new NativeKeyboardInput(key, true, false, false), true), null, "Win+R/Win+D keyup must remain captured.");
            AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyLeftWin, true, false, false), true), null, "A Win chord must not toggle Start after completion.");
        }
    }

    private static void AltTabRoutesOncePerPress()
    {
        var router = new NativeKeyboardShortcutRouter();
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyTab, false, true, false), true), NativeHostShortcut.CycleWindows, "Alt+Tab must route to the CloudOS switcher.");
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyTab, false, true, false), true), null, "Alt+Tab repeat must not cycle more than once per press.");
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyTab, true, true, false), true), null, "Alt+Tab keyup must remain captured.");
    }

    private static void AltF4RoutesOncePerPress()
    {
        var router = new NativeKeyboardShortcutRouter();
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyF4, false, true, false), true), NativeHostShortcut.CloseActiveWindow, "Alt+F4 must close the active CloudOS window.");
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyF4, false, true, false), true), null, "Alt+F4 repeat must not close multiple windows.");
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyF4, true, true, false), true), null, "Alt+F4 keyup must remain captured.");
    }

    private static void InjectedReservedInputCannotInvokeCloudOsActions()
    {
        var router = new NativeKeyboardShortcutRouter();
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyLeftWin, false, false, true), true), null, "Injected Win must be swallowed without a privileged action.");
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyLeftWin, true, false, true), true), null, "Injected Win release must not toggle Start.");
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyTab, false, true, true), true), null, "Injected Alt+Tab must not invoke the CloudOS switcher.");
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyF4, false, true, true), true), null, "Injected Alt+F4 must not close a CloudOS window.");
    }

    private static void UnrelatedForegroundWindowsRemainUntouched()
    {
        var router = new NativeKeyboardShortcutRouter();
        AssertPass(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyLeftWin, false, false, false), false), "Win outside CloudOS must remain a Windows shortcut.");
        AssertPass(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyTab, false, true, false), false), "Alt+Tab outside CloudOS must remain a Windows shortcut.");
        AssertPass(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyF4, false, true, false), false), "Alt+F4 outside CloudOS must remain a Windows shortcut.");
    }

    private static void FocusLossCannotTriggerDeferredCloudOsActions()
    {
        var router = new NativeKeyboardShortcutRouter();
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyLeftWin, false, false, false), true), null, "Win down must start captured in CloudOS.");
        AssertConsumed(router.Route(new NativeKeyboardInput(NativeKeyboardShortcutRouter.VirtualKeyLeftWin, true, false, false), false), null, "Focus loss before Win release must consume cleanup without toggling CloudOS Start.");
    }

    private static void AssertPass(NativeKeyboardDecision decision, string message)
    {
        if (decision.Suppress || decision.Shortcut is not null) throw new InvalidOperationException(message);
    }

    private static void AssertConsumed(NativeKeyboardDecision decision, NativeHostShortcut? shortcut, string message)
    {
        if (!decision.Suppress || decision.Shortcut != shortcut) throw new InvalidOperationException(message);
    }
}
