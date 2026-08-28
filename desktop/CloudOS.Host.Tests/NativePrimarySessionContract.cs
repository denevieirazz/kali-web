using System.Runtime.CompilerServices;

internal static class NativePrimarySessionContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        if (Environment.GetCommandLineArgs().Any(argument =>
            argument.StartsWith("--native-contained-fixture-", StringComparison.Ordinal)))
            return;

        var desktopRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));
        var bridgePath = Path.Combine(desktopRoot, "CloudOS.Host", "Bridge", "WebMessageBridge.cs");
        if (!File.Exists(bridgePath))
            throw new InvalidOperationException($"WebMessageBridge source was not found at {bridgePath}.");

        var source = File.ReadAllText(bridgePath);
        Assert(source.Contains("else if (_sessionIdsByHandle.TryGetValue(handle, out var sessionId))", StringComparison.Ordinal),
            "Auxiliary Job HWNDs must not be promoted to CloudOS sessions by WinEvent callbacks.");
        Assert(!source.Contains("var sessionId = GetOrCreateSession(eventArgs.Window);", StringComparison.Ordinal),
            "WinEvent callbacks must not create sessions for helper or splash windows.");
        Assert(source.Contains("if (!_sessionIdsByHandle.TryGetValue(window.Handle, out var sessionId)) continue;", StringComparison.Ordinal),
            "Public session enumeration must expose only explicitly selected launch HWNDs.");
        Assert(source.Contains("WindowCandidateStabilityMilliseconds = 350", StringComparison.Ordinal),
            "Launch HWND selection must require a stable candidate before attachment.");
        Assert(source.Contains("PrimaryWindowReplacementGraceMilliseconds = 5_000", StringComparison.Ordinal),
            "A selected primary HWND must have a bounded replacement grace period.");
        Assert(source.Contains("_ = RecoverPrimaryWindowAsync(rootProcessId, removed, handle, removedProcessId);", StringComparison.Ordinal),
            "Destroying the selected HWND must begin same-Job recovery instead of immediately killing the launch.");
        Assert(source.Contains("_sessionIdsByHandle[candidate.Handle] = sessionId;", StringComparison.Ordinal)
            && source.Contains("_handlesBySessionId[sessionId] = candidate.Handle;", StringComparison.Ordinal),
            "A replacement HWND must inherit the same logical CloudOS session id.");
        Assert(source.Contains("await WaitForSessionRecoveryAsync(sessionId);", StringComparison.Ordinal),
            "Attach/layout requests must wait for an in-flight HWND replacement rather than terminating the Job.");
        Assert(source.Contains("native_primary_window_recovered", StringComparison.Ordinal)
            && source.Contains("native_primary_window_recovery_failed", StringComparison.Ordinal),
            "Primary HWND recovery must emit explicit success and bounded-failure diagnostics.");

        Console.WriteLine("PASS primary native session HWND handoff contract");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
