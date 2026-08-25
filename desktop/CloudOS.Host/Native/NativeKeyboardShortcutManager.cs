using System.ComponentModel;
using System.Runtime.InteropServices;

namespace CloudOS.Host.Native;

/// <summary>
/// Installs one WH_KEYBOARD_LL hook for the CloudOS Host process. The hook is
/// active only while the foreground HWND is the Host or belongs to an owner chain
/// rooted at the Host. This keeps ordinary Windows applications completely outside
/// the shortcut policy while allowing a focused contained HWND to behave like a
/// CloudOS surface.
/// </summary>
public sealed class NativeKeyboardShortcutManager : IDisposable
{
    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104;
    private const int WmSysKeyUp = 0x0105;
    private const uint LlkhfLowerIlInjected = 0x00000002;
    private const uint LlkhfInjected = 0x00000010;
    private const uint LlkhfAltDown = 0x00000020;
    private const int GwOwner = 4;

    private readonly IntPtr _hostWindow;
    private readonly Action<NativeHostShortcut> _onShortcut;
    private readonly NativeKeyboardShortcutRouter _router = new();
    private readonly LowLevelKeyboardProc _callback;
    private IntPtr _hook;
    private bool _disposed;

    public NativeKeyboardShortcutManager(IntPtr hostWindow, Action<NativeHostShortcut> onShortcut)
    {
        if (hostWindow == IntPtr.Zero) throw new ArgumentException("The CloudOS Host HWND is required.", nameof(hostWindow));
        _onShortcut = onShortcut ?? throw new ArgumentNullException(nameof(onShortcut));
        _hostWindow = hostWindow;
        _callback = HookCallback;

        var module = GetModuleHandle(null);
        if (module == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "GetModuleHandleW failed for the CloudOS keyboard hook.");

        _hook = SetWindowsHookEx(WhKeyboardLl, _callback, module, 0);
        if (_hook == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "The CloudOS low-level keyboard hook could not be installed.");
    }

    private IntPtr HookCallback(int code, IntPtr messagePointer, IntPtr dataPointer)
    {
        if (code < 0 || _disposed)
            return CallNextHookEx(_hook, code, messagePointer, dataPointer);

        var message = unchecked((int)messagePointer.ToInt64());
        if (message is not (WmKeyDown or WmKeyUp or WmSysKeyDown or WmSysKeyUp))
            return CallNextHookEx(_hook, code, messagePointer, dataPointer);

        var data = Marshal.PtrToStructure<KbdLlHookStruct>(dataPointer);
        var input = new NativeKeyboardInput(
            data.VirtualKey,
            message is WmKeyUp or WmSysKeyUp,
            (data.Flags & LlkhfAltDown) != 0,
            (data.Flags & (LlkhfInjected | LlkhfLowerIlInjected)) != 0);
        var decision = _router.Route(input, IsCloudOsForeground());

        if (decision.Shortcut is { } shortcut)
        {
            try { _onShortcut(shortcut); }
            catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException)
            {
                // A shutdown race must not unwind across the unmanaged hook boundary.
            }
        }

        return decision.Suppress
            ? new IntPtr(1)
            : CallNextHookEx(_hook, code, messagePointer, dataPointer);
    }

    private bool IsCloudOsForeground()
    {
        var current = GetForegroundWindow();
        for (var depth = 0; current != IntPtr.Zero && depth < 8; depth++)
        {
            if (current == _hostWindow) return true;
            var owner = GetWindow(current, GwOwner);
            if (owner == current) break;
            current = owner;
        }
        return false;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        var hook = Interlocked.Exchange(ref _hook, IntPtr.Zero);
        if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
        GC.KeepAlive(_callback);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KbdLlHookStruct
    {
        internal uint VirtualKey;
        internal uint ScanCode;
        internal uint Flags;
        internal uint Time;
        internal UIntPtr ExtraInfo;
    }

    private delegate IntPtr LowLevelKeyboardProc(int code, IntPtr messagePointer, IntPtr dataPointer);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(
        int hookId,
        LowLevelKeyboardProc callback,
        IntPtr module,
        uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(
        IntPtr hook,
        int code,
        IntPtr messagePointer,
        IntPtr dataPointer);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr window, int command);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string? moduleName);
}
