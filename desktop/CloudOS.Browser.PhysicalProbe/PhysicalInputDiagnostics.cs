using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;

namespace CloudOS.Browser.PhysicalProbe;

internal static class PhysicalInputDiagnostics
{
    private const uint TOKEN_QUERY = 0x0008;
    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private const int TokenElevation = 20;
    private const int TokenIntegrityLevel = 25;
    private const int TokenUIAccess = 26;
    private const int UOI_FLAGS = 1;
    private const int UOI_NAME = 2;
    private const int UOI_IO = 6;
    private const uint WSF_VISIBLE = 0x0001;
    private const uint DESKTOP_READOBJECTS = 0x0001;
    private const int VK_SHIFT = 0x10;
    private const int VK_CONTROL = 0x11;
    private const int VK_MENU = 0x12;
    private const int VK_LWIN = 0x5B;
    private const int VK_RWIN = 0x5C;

    internal static FocusRequestResult RequestFocus(Window window, FrameworkElement element)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        var windowActivated = window.Activate();
        var setForegroundSucceeded = hwnd != IntPtr.Zero && SetForegroundWindow(hwnd);
        var elementFocusRequested = element.Focus();
        var keyboardFocusRequested = Keyboard.Focus(element) is not null;
        return new FocusRequestResult(windowActivated, setForegroundSucceeded, elementFocusRequested, keyboardFocusRequested);
    }

    internal static PhysicalInputSnapshot Capture(Window window, FrameworkElement focusedElement, int nativeInputSize)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        var currentThreadId = GetCurrentThreadId();
        var currentProcessId = (uint)Environment.ProcessId;

        uint windowProcessId = 0;
        var windowThreadId = hwnd == IntPtr.Zero ? 0 : GetWindowThreadProcessId(hwnd, out windowProcessId);

        var foregroundHwnd = GetForegroundWindow();
        uint foregroundProcessId = 0;
        var foregroundThreadId = foregroundHwnd == IntPtr.Zero
            ? 0
            : GetWindowThreadProcessId(foregroundHwnd, out foregroundProcessId);

        var processToken = ReadProcessToken(currentProcessId);
        var foregroundToken = foregroundProcessId == currentProcessId
            ? processToken
            : ReadProcessToken(foregroundProcessId);
        var desktop = ReadDesktopContext(currentThreadId);
        var gui = ReadGuiThreadInfo(currentThreadId);
        var nativeFocus = GetFocus();

        var foregroundIntegrityHigher = processToken.IntegrityRid.HasValue
            && foregroundToken.IntegrityRid.HasValue
            && foregroundToken.IntegrityRid.Value > processToken.IntegrityRid.Value;

        return new PhysicalInputSnapshot(
            OperatingSystem.IsWindows(),
            Environment.UserInteractive,
            Process.GetCurrentProcess().SessionId,
            currentProcessId,
            currentThreadId,
            hwnd != IntPtr.Zero,
            windowProcessId,
            windowThreadId,
            windowProcessId == currentProcessId,
            windowThreadId == currentThreadId,
            foregroundProcessId,
            foregroundThreadId,
            foregroundHwnd != IntPtr.Zero && foregroundHwnd == hwnd,
            foregroundThreadId == currentThreadId,
            foregroundIntegrityHigher,
            window.IsActive,
            focusedElement.IsKeyboardFocusWithin,
            ReferenceEquals(Keyboard.FocusedElement, focusedElement),
            nativeFocus != IntPtr.Zero && nativeFocus == hwnd,
            gui.Available,
            gui.Error,
            gui.ActiveMatches(hwnd),
            gui.FocusMatches(hwnd),
            desktop,
            processToken,
            foregroundToken,
            IsKeyDown(VK_SHIFT),
            IsKeyDown(VK_CONTROL),
            IsKeyDown(VK_MENU),
            IsKeyDown(VK_LWIN) || IsKeyDown(VK_RWIN),
            nativeInputSize);
    }

    internal static IReadOnlyList<string> Evaluate(PhysicalInputSnapshot snapshot)
    {
        var blockers = new List<string>();
        if (!snapshot.IsWindows) blockers.Add("not-windows");
        if (!snapshot.UserInteractive) blockers.Add("non-interactive-process");
        if (snapshot.SessionId == 0) blockers.Add("session-zero");
        if (snapshot.Desktop.WindowStationVisible != true) blockers.Add("window-station-not-visible");
        if (snapshot.Desktop.ThreadDesktopReceivesInput != true) blockers.Add("thread-desktop-not-input");
        if (!snapshot.Desktop.InputDesktopOpen) blockers.Add("input-desktop-unavailable");
        if (snapshot.Desktop.ThreadDesktopName is not null && snapshot.Desktop.InputDesktopName is not null
            && !string.Equals(snapshot.Desktop.ThreadDesktopName, snapshot.Desktop.InputDesktopName, StringComparison.OrdinalIgnoreCase))
            blockers.Add("thread-desktop-differs-from-input-desktop");
        if (!snapshot.ProcessToken.Available || !snapshot.ProcessToken.IntegrityRid.HasValue)
            blockers.Add("process-integrity-unavailable");
        if (!snapshot.WindowHandleValid) blockers.Add("window-handle-missing");
        if (!snapshot.WindowOwnedByCurrentProcess) blockers.Add("window-process-mismatch");
        if (!snapshot.WindowOwnedByCurrentThread) blockers.Add("window-thread-mismatch");
        if (snapshot.ForegroundIntegrityHigher) blockers.Add("foreground-higher-integrity");
        if (!snapshot.ForegroundMatchesWindow) blockers.Add("foreground-not-probe-window");
        if (!snapshot.ForegroundThreadMatchesCurrent) blockers.Add("foreground-input-queue-differs");
        if (!snapshot.WindowIsActive) blockers.Add("wpf-window-not-active");
        if (!snapshot.WpfKeyboardFocusWithin || !snapshot.WpfFocusedElementMatches)
            blockers.Add("wpf-focus-mismatch");
        if (!snapshot.GuiThreadInfoAvailable) blockers.Add("gui-thread-info-unavailable");
        if (!snapshot.GuiThreadActiveMatchesWindow) blockers.Add("native-active-window-mismatch");
        if (!snapshot.GuiThreadFocusMatchesWindow && !snapshot.GetFocusMatchesWindow)
            blockers.Add("native-keyboard-focus-mismatch");
        if (snapshot.ShiftDown || snapshot.ControlDown || snapshot.AltDown || snapshot.WindowsKeyDown)
            blockers.Add("modifier-key-already-down");
        return blockers;
    }

    private static DesktopContext ReadDesktopContext(uint currentThreadId)
    {
        var windowStation = GetProcessWindowStation();
        var windowStationName = TryGetUserObjectName(windowStation);
        bool? windowStationVisible = null;
        int? windowStationFlagsError = null;
        if (windowStation != IntPtr.Zero)
        {
            if (GetUserObjectInformationFlags(windowStation, UOI_FLAGS, out var flags, (uint)Marshal.SizeOf<UserObjectFlags>(), out _))
                windowStationVisible = (flags.dwFlags & WSF_VISIBLE) != 0;
            else
                windowStationFlagsError = Marshal.GetLastPInvokeError();
        }

        var threadDesktop = GetThreadDesktop(currentThreadId);
        var threadDesktopName = TryGetUserObjectName(threadDesktop);
        var (threadDesktopReceivesInput, threadDesktopIoError) = TryGetUserObjectBool(threadDesktop, UOI_IO);

        var inputDesktop = OpenInputDesktop(0, false, DESKTOP_READOBJECTS);
        if (inputDesktop == IntPtr.Zero)
        {
            return new DesktopContext(
                windowStationName,
                windowStationVisible,
                windowStationFlagsError,
                threadDesktopName,
                threadDesktopReceivesInput,
                threadDesktopIoError,
                false,
                null,
                null,
                Marshal.GetLastPInvokeError());
        }

        try
        {
            var inputDesktopName = TryGetUserObjectName(inputDesktop);
            var (inputDesktopReceivesInput, inputDesktopIoError) = TryGetUserObjectBool(inputDesktop, UOI_IO);
            return new DesktopContext(
                windowStationName,
                windowStationVisible,
                windowStationFlagsError,
                threadDesktopName,
                threadDesktopReceivesInput,
                threadDesktopIoError,
                true,
                inputDesktopName,
                inputDesktopReceivesInput,
                inputDesktopIoError);
        }
        finally
        {
            CloseDesktop(inputDesktop);
        }
    }

    private static GuiThreadSnapshot ReadGuiThreadInfo(uint threadId)
    {
        var info = new GuiThreadInfo { cbSize = (uint)Marshal.SizeOf<GuiThreadInfo>() };
        if (!GetGUIThreadInfo(threadId, ref info))
            return new GuiThreadSnapshot(false, Marshal.GetLastPInvokeError(), false, false);

        return new GuiThreadSnapshot(true, null, info.hwndActive != IntPtr.Zero, info.hwndFocus != IntPtr.Zero)
        {
            ActiveWindow = info.hwndActive,
            FocusWindow = info.hwndFocus
        };
    }

    private static TokenSecurityContext ReadProcessToken(uint processId)
    {
        if (processId == 0)
            return TokenSecurityContext.Unavailable(null);

        var processHandle = processId == (uint)Environment.ProcessId
            ? GetCurrentProcess()
            : OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, processId);

        if (processHandle == IntPtr.Zero)
            return TokenSecurityContext.Unavailable(Marshal.GetLastPInvokeError());

        var closeProcess = processId != (uint)Environment.ProcessId;
        try
        {
            if (!OpenProcessToken(processHandle, TOKEN_QUERY, out var tokenHandle))
                return TokenSecurityContext.Unavailable(Marshal.GetLastPInvokeError());

            try
            {
                var integrityRid = TryReadIntegrityRid(tokenHandle, out var integrityError);
                var elevated = TryReadTokenInt(tokenHandle, TokenElevation, out var elevationError);
                var uiAccess = TryReadTokenInt(tokenHandle, TokenUIAccess, out var uiAccessError);
                var error = integrityError ?? elevationError ?? uiAccessError;
                return new TokenSecurityContext(
                    integrityRid.HasValue,
                    integrityRid,
                    integrityRid.HasValue ? IntegrityName(integrityRid.Value) : null,
                    elevated.HasValue ? elevated.Value != 0 : null,
                    uiAccess.HasValue ? uiAccess.Value != 0 : null,
                    error);
            }
            finally
            {
                CloseHandle(tokenHandle);
            }
        }
        finally
        {
            if (closeProcess) CloseHandle(processHandle);
        }
    }

    private static int? TryReadIntegrityRid(IntPtr tokenHandle, out int? error)
    {
        error = null;
        GetTokenInformation(tokenHandle, TokenIntegrityLevel, IntPtr.Zero, 0, out var length);
        if (length <= 0)
        {
            error = Marshal.GetLastPInvokeError();
            return null;
        }

        var buffer = Marshal.AllocHGlobal(length);
        try
        {
            if (!GetTokenInformation(tokenHandle, TokenIntegrityLevel, buffer, length, out _))
            {
                error = Marshal.GetLastPInvokeError();
                return null;
            }

            var sid = Marshal.ReadIntPtr(buffer);
            if (sid == IntPtr.Zero)
            {
                error = 0;
                return null;
            }

            var countPtr = GetSidSubAuthorityCount(sid);
            if (countPtr == IntPtr.Zero)
            {
                error = 0;
                return null;
            }

            var count = Marshal.ReadByte(countPtr);
            if (count == 0)
            {
                error = 0;
                return null;
            }

            var ridPtr = GetSidSubAuthority(sid, (uint)(count - 1));
            if (ridPtr == IntPtr.Zero)
            {
                error = 0;
                return null;
            }

            return Marshal.ReadInt32(ridPtr);
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static int? TryReadTokenInt(IntPtr tokenHandle, int informationClass, out int? error)
    {
        error = null;
        var buffer = Marshal.AllocHGlobal(sizeof(int));
        try
        {
            if (!GetTokenInformation(tokenHandle, informationClass, buffer, sizeof(int), out _))
            {
                error = Marshal.GetLastPInvokeError();
                return null;
            }
            return Marshal.ReadInt32(buffer);
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static string IntegrityName(int rid) => rid switch
    {
        < 0x1000 => "untrusted",
        < 0x2000 => "low",
        0x2000 => "medium",
        < 0x3000 => "medium-plus",
        < 0x4000 => "high",
        0x4000 => "system",
        _ => "protected-or-custom"
    };

    private static string? TryGetUserObjectName(IntPtr handle)
    {
        if (handle == IntPtr.Zero) return null;
        var buffer = new StringBuilder(256);
        return GetUserObjectInformationName(handle, UOI_NAME, buffer, (uint)(buffer.Capacity * sizeof(char)), out _)
            ? buffer.ToString()
            : null;
    }

    private static (bool? Value, int? Error) TryGetUserObjectBool(IntPtr handle, int index)
    {
        if (handle == IntPtr.Zero) return (null, null);
        if (GetUserObjectInformationBool(handle, index, out var value, sizeof(int), out _))
            return (value != 0, null);
        return (null, Marshal.GetLastPInvokeError());
    }

    private static bool IsKeyDown(int virtualKey) => (GetAsyncKeyState(virtualKey) & 0x8000) != 0;

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern IntPtr GetFocus();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetGUIThreadInfo(uint threadId, ref GuiThreadInfo info);

    [DllImport("user32.dll")]
    private static extern IntPtr GetProcessWindowStation();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetThreadDesktop(uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr OpenInputDesktop(uint flags, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint desiredAccess);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseDesktop(IntPtr desktop);

    [DllImport("user32.dll", EntryPoint = "GetUserObjectInformationW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetUserObjectInformationName(IntPtr handle, int index, StringBuilder buffer, uint length, out uint needed);

    [DllImport("user32.dll", EntryPoint = "GetUserObjectInformationW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetUserObjectInformationBool(IntPtr handle, int index, out int value, int length, out uint needed);

    [DllImport("user32.dll", EntryPoint = "GetUserObjectInformationW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetUserObjectInformationFlags(IntPtr handle, int index, out UserObjectFlags flags, uint length, out uint needed);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int virtualKey);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint desiredAccess, [MarshalAs(UnmanagedType.Bool)] bool inheritHandle, uint processId);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenProcessToken(IntPtr processHandle, uint desiredAccess, out IntPtr tokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformation(IntPtr tokenHandle, int informationClass, IntPtr tokenInformation, int tokenInformationLength, out int returnLength);

    [DllImport("advapi32.dll")]
    private static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);

    [DllImport("advapi32.dll")]
    private static extern IntPtr GetSidSubAuthority(IntPtr sid, uint subAuthority);

    [StructLayout(LayoutKind.Sequential)]
    private struct UserObjectFlags
    {
        public int fInherit;
        public int fReserved;
        public uint dwFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct GuiThreadInfo
    {
        public uint cbSize;
        public uint flags;
        public IntPtr hwndActive;
        public IntPtr hwndFocus;
        public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner;
        public IntPtr hwndMoveSize;
        public IntPtr hwndCaret;
        public NativeRect rcCaret;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    private sealed record GuiThreadSnapshot(bool Available, int? Error, bool HasActiveWindow, bool HasFocusWindow)
    {
        internal IntPtr ActiveWindow { get; init; }
        internal IntPtr FocusWindow { get; init; }
        internal bool ActiveMatches(IntPtr hwnd) => Available && HasActiveWindow && ActiveWindow == hwnd;
        internal bool FocusMatches(IntPtr hwnd) => Available && HasFocusWindow && FocusWindow == hwnd;
    }
}

internal sealed record FocusRequestResult(
    bool WindowActivateSucceeded,
    bool SetForegroundWindowSucceeded,
    bool ElementFocusRequested,
    bool KeyboardFocusRequested);

internal sealed record TokenSecurityContext(
    bool Available,
    int? IntegrityRid,
    string? IntegrityLevel,
    bool? Elevated,
    bool? UiAccess,
    int? Error)
{
    internal static TokenSecurityContext Unavailable(int? error) => new(false, null, null, null, null, error);
}

internal sealed record DesktopContext(
    string? WindowStationName,
    bool? WindowStationVisible,
    int? WindowStationFlagsError,
    string? ThreadDesktopName,
    bool? ThreadDesktopReceivesInput,
    int? ThreadDesktopIoError,
    bool InputDesktopOpen,
    string? InputDesktopName,
    bool? InputDesktopReceivesInput,
    int? InputDesktopError);

internal sealed record PhysicalInputSnapshot(
    bool IsWindows,
    bool UserInteractive,
    int SessionId,
    uint CurrentProcessId,
    uint CurrentThreadId,
    bool WindowHandleValid,
    uint WindowProcessId,
    uint WindowThreadId,
    bool WindowOwnedByCurrentProcess,
    bool WindowOwnedByCurrentThread,
    uint ForegroundProcessId,
    uint ForegroundThreadId,
    bool ForegroundMatchesWindow,
    bool ForegroundThreadMatchesCurrent,
    bool ForegroundIntegrityHigher,
    bool WindowIsActive,
    bool WpfKeyboardFocusWithin,
    bool WpfFocusedElementMatches,
    bool GetFocusMatchesWindow,
    bool GuiThreadInfoAvailable,
    int? GuiThreadInfoError,
    bool GuiThreadActiveMatchesWindow,
    bool GuiThreadFocusMatchesWindow,
    DesktopContext Desktop,
    TokenSecurityContext ProcessToken,
    TokenSecurityContext ForegroundToken,
    bool ShiftDown,
    bool ControlDown,
    bool AltDown,
    bool WindowsKeyDown,
    int NativeInputSize);

internal sealed record PhysicalInputContext(
    PhysicalInputSnapshot BeforeFocus,
    FocusRequestResult FocusRequest,
    PhysicalInputSnapshot AfterFocus,
    IReadOnlyList<string> Blockers);
