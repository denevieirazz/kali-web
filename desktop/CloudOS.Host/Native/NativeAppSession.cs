namespace CloudOS.Host.Native;

internal enum NativeAppSessionState
{
    Launching,
    Ready,
    Attached,
    RecoveringWindow,
    Closing,
    Exited,
    Failed
}

/// <summary>
/// Stable identity for one Windows application launch inside CloudOS.
///
/// A session belongs to the launch/Job lifetime. HWND and even the process that owns the primary
/// HWND are mutable properties because Chromium, Electron, launchers and other desktop runtimes
/// routinely replace their top-level window during startup and during their normal lifecycle.
/// </summary>
internal sealed class NativeAppSession
{
    internal NativeAppSession(string sessionId, int rootProcessId, int processId, long windowHandle)
    {
        if (string.IsNullOrWhiteSpace(sessionId)) throw new ArgumentException("Session id is required.", nameof(sessionId));
        if (rootProcessId <= 0) throw new ArgumentOutOfRangeException(nameof(rootProcessId));
        if (processId <= 0) throw new ArgumentOutOfRangeException(nameof(processId));
        if (windowHandle == 0) throw new ArgumentOutOfRangeException(nameof(windowHandle));

        SessionId = sessionId;
        RootProcessId = rootProcessId;
        CurrentProcessId = processId;
        CurrentWindowHandle = windowHandle;
        State = NativeAppSessionState.Ready;
        CreatedAt = DateTimeOffset.UtcNow;
        UpdatedAt = CreatedAt;
    }

    internal string SessionId { get; }
    internal int RootProcessId { get; }
    internal int CurrentProcessId { get; private set; }
    internal long CurrentWindowHandle { get; private set; }
    internal NativeAppSessionState State { get; private set; }
    internal DateTimeOffset CreatedAt { get; }
    internal DateTimeOffset UpdatedAt { get; private set; }
    internal int WindowGeneration { get; private set; }

    internal void BindWindow(int processId, long windowHandle)
    {
        if (processId <= 0) throw new ArgumentOutOfRangeException(nameof(processId));
        if (windowHandle == 0) throw new ArgumentOutOfRangeException(nameof(windowHandle));

        if (CurrentProcessId != processId || CurrentWindowHandle != windowHandle)
            WindowGeneration++;
        CurrentProcessId = processId;
        CurrentWindowHandle = windowHandle;
        State = NativeAppSessionState.Ready;
        UpdatedAt = DateTimeOffset.UtcNow;
    }

    internal void MarkAttached()
    {
        State = NativeAppSessionState.Attached;
        UpdatedAt = DateTimeOffset.UtcNow;
    }

    internal void MarkWindowRecovery()
    {
        State = NativeAppSessionState.RecoveringWindow;
        UpdatedAt = DateTimeOffset.UtcNow;
    }

    internal void MarkClosing()
    {
        State = NativeAppSessionState.Closing;
        UpdatedAt = DateTimeOffset.UtcNow;
    }

    internal void MarkExited()
    {
        State = NativeAppSessionState.Exited;
        UpdatedAt = DateTimeOffset.UtcNow;
    }

    internal void MarkFailed()
    {
        State = NativeAppSessionState.Failed;
        UpdatedAt = DateTimeOffset.UtcNow;
    }
}
