using System.Runtime.CompilerServices;
using CloudOS.Host.Native;

internal static class NativeWindowSnapshotContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        if (Environment.GetCommandLineArgs().Any(argument =>
            argument.StartsWith("--native-contained-fixture-", StringComparison.Ordinal)))
            return;

        var observedAt = DateTimeOffset.UtcNow;
        var baseline = Snapshot(observedAt: observedAt);
        var refreshed = Snapshot(observedAt: observedAt.AddSeconds(1));

        Assert(
            NativeWindowManager.HasSameObservableState(baseline, refreshed),
            "Refresh timestamps and fresh snapshot object identities must not emit native Updated events.");

        AssertChanged(Snapshot(handle: 1002), "HWND changes must remain observable.");
        AssertChanged(Snapshot(processId: 43), "Process changes must remain observable.");
        AssertChanged(Snapshot(title: "Editor 2"), "Title changes must remain observable.");
        AssertChanged(Snapshot(isVisible: false), "Visibility changes must remain observable.");
        AssertChanged(Snapshot(isMinimized: true), "Minimize changes must remain observable.");
        AssertChanged(Snapshot(isMaximized: true), "Maximize changes must remain observable.");
        AssertChanged(Snapshot(isAttached: false), "Attachment changes must remain observable.");
        AssertChanged(Snapshot(bounds: new NativeWindowBounds(11, 20, 640, 480)), "X changes must remain observable.");
        AssertChanged(Snapshot(bounds: new NativeWindowBounds(10, 21, 640, 480)), "Y changes must remain observable.");
        AssertChanged(Snapshot(bounds: new NativeWindowBounds(10, 20, 641, 480)), "Width changes must remain observable.");
        AssertChanged(Snapshot(bounds: new NativeWindowBounds(10, 20, 640, 481)), "Height changes must remain observable.");

        Console.WriteLine("PASS native window observable snapshot contract");

        void AssertChanged(NativeWindowSnapshot changed, string message)
        {
            Assert(!NativeWindowManager.HasSameObservableState(baseline, changed), message);
        }
    }

    private static NativeWindowSnapshot Snapshot(
        long handle = 1001,
        int processId = 42,
        string title = "Editor",
        bool isVisible = true,
        bool isMinimized = false,
        bool isMaximized = false,
        bool isAttached = true,
        NativeWindowBounds? bounds = null,
        DateTimeOffset? observedAt = null)
    {
        return new NativeWindowSnapshot(
            handle,
            processId,
            title,
            isVisible,
            isMinimized,
            isMaximized,
            isAttached,
            bounds ?? new NativeWindowBounds(10, 20, 640, 480),
            observedAt ?? DateTimeOffset.UtcNow);
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
