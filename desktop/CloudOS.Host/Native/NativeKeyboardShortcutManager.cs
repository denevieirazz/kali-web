using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;

namespace CloudOS.Host.Native;

/// <summary>
/// Owns one WH_KEYBOARD_LL hook on a dedicated message-pump thread. The hook is
/// active only while the foreground HWND is the Host or belongs to an owner chain
/// rooted at the Host. Keeping the low-level callback off the WPF dispatcher avoids
/// UI/WebView work delaying the hook past Windows' low-level-hook deadline.
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
    private const int StartupTimeoutMilliseconds = 5_000;
    private const int ShutdownTimeoutMilliseconds = 5_000;
    private const int ErrorTimeout = 1460;
    private const int ErrorGeneralFailure = 31;

    private readonly IntPtr _hostWindow;
    private readonly Action<NativeHostShortcut> _onShortcut;
    private readonly NativeKeyboardShortcutRouter _router = new();
    private readonly LowLevelKeyboardProc _callback;
    private readonly ManualResetEvent _hookReady = new(false);
    private readonly Thread _hookThread;

    private Exception? _hookStartException;
    private uint _hookThreadId;
    private IntPtr _hook;
    private volatile bool _disposed;

    public NativeKeyboardShortcutManager(IntPtr hostWindow, Action<NativeHostShortcut> onShortcut)
    {
        if (hostWindow == IntPtr.Zero) throw new ArgumentException("The CloudOS Host HWND is required.", nameof(hostWindow));
        _onShortcut = onShortcut ?? throw new ArgumentNullException(nameof(onShortcut));
        _hostWindow = hostWindow;
        _callback = HookCallback;
        _hookThread = new Thread(HookThreadMain)
        {
            IsBackground = true,
            Name = "CloudOS.NativeKeyboardShortcutManager"
        };
        _hookThread.Start();

        if (!_hookReady.WaitOne(StartupTimeoutMilliseconds))
        {
            Dispose();
            throw new Win32Exception(ErrorTimeout, "Timed out while starting the CloudOS low-level keyboard hook thread.");
        }

        if (_hookStartException is not null)
        {
            var startupError = _hookStartException;
            Dispose();
            if (startupError is Win32Exception nativeError) throw nativeError;
            throw new Win32Exception(ErrorGeneralFailure, $"The CloudOS low-level keyboard hook could not start: {startupError.Message}");
        }
    }

    private void HookThreadMain()
    {
        try
        {
            _hookThreadId = NativeMethods.GetCurrentThreadId();

            // SetWindowsHookEx(WH_KEYBOARD_LL) dispatches callbacks through the
            // installer's message queue. Create it before exposing readiness so
            // Dispose can always stop this thread with WM_QUIT.
            NativeMethods.MSG message;
            NativeMethods.PeekMessage(out message, IntPtr.Zero, 0, 0, NativeMethods.PM_NOREMOVE);
            if (_disposed)
            {
                _hookReady.Set();
                return;
            }

            var module = GetModuleHandle(null);
            if (module == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetModuleHandleW failed for the CloudOS keyboard hook.");

            _hook = SetWindowsHookEx(WhKeyboardLl, _callback, module, 0);
            if (_hook == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "The CloudOS low-level keyboard hook could not be installed.");

            _hookReady.Set();
            while (!_disposed && NativeMethods.GetMessage(out message, IntPtr.Zero, 0, 0) > 0)
            {
                NativeMethods.TranslateMessage(ref message);
                NativeMethods.DispatchMessage(ref message);
            }
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            _hookStartException = error;
            try { _hookReady.Set(); } catch (ObjectDisposedException) { }
        }
        finally
        {
            var hook = Interlocked.Exchange(ref _hook, IntPtr.Zero);
            if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
            _hookThreadId = 0;
            GC.KeepAlive(_callback);
        }
    }

    private IntPtr HookCallback(int code, IntPtr messagePointer, IntPtr dataPointer)
    {
        var hook = _hook;
        if (code < 0 || _disposed)
            return CallNextHookEx(hook, code, messagePointer, dataPointer);

        var message = unchecked((int)messagePointer.ToInt64());
        if (message is not (WmKeyDown or WmKeyUp or WmSysKeyDown or WmSysKeyUp))
            return CallNextHookEx(hook, code, messagePointer, dataPointer);

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
                // The action only queues work onto WPF. A shutdown race must never
                // unwind through the unmanaged low-level-hook callback.
            }
        }

        return decision.Suppress
            ? new IntPtr(1)
            : CallNextHookEx(hook, code, messagePointer, dataPointer);
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

        var threadId = _hookThreadId;
        if (threadId != 0)
            NativeMethods.PostThreadMessage(threadId, NativeMethods.WM_QUIT, UIntPtr.Zero, IntPtr.Zero);

        if (_hookThread.IsAlive && Thread.CurrentThread != _hookThread)
        {
            if (!_hookThread.Join(ShutdownTimeoutMilliseconds))
            {
                // Fail closed if the message pump is unexpectedly stuck. Removing
                // the hook is preferable to leaving a process-global callback alive.
                var hook = Interlocked.Exchange(ref _hook, IntPtr.Zero);
                if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
            }
        }

        _hookReady.Close();
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
