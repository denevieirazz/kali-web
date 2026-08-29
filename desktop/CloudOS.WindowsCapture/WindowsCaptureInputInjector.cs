using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace CloudOS.WindowsCapture;

public enum WindowsCaptureInputInjectionStatus
{
    Delivered,
    Rejected,
    Unsupported,
    TargetLost,
    TimedOut,
    NativeFailure
}

public sealed record WindowsCaptureInputInjectionResult(
    WindowsCaptureInputInjectionStatus Status,
    WindowsCaptureInputRejection Rejection,
    long Sequence,
    int Generation,
    long DestinationWindowHandle,
    string? Failure)
{
    public bool Delivered => Status == WindowsCaptureInputInjectionStatus.Delivered;
}

/// <summary>
/// Targeted Win32 input candidate for a qualified captured HWND. It never uses global
/// SendInput and never guesses screen coordinates. Pointer events are routed only to a
/// child/control proven to belong to the source HWND client tree. Keyboard events are
/// delivered only to the focused HWND reported by the source GUI thread and proven to be
/// the source HWND or its child. Unsupported input models (Raw Input, brokered focus, etc.)
/// fail closed and must be classified instead of falling back to desktop-global injection.
/// </summary>
public sealed class WindowsCaptureTargetedInputInjector
{
    private const uint SmtoAbortIfHung = 0x0002;
    private const uint SmtoBlock = 0x0001;
    private const uint CwpSkipInvisible = 0x0001;
    private const uint CwpSkipDisabled = 0x0002;
    private const uint WmMouseMove = 0x0200;
    private const uint WmLButtonDown = 0x0201;
    private const uint WmLButtonUp = 0x0202;
    private const uint WmRButtonDown = 0x0204;
    private const uint WmRButtonUp = 0x0205;
    private const uint WmMButtonDown = 0x0207;
    private const uint WmMButtonUp = 0x0208;
    private const uint WmMouseWheel = 0x020A;
    private const uint WmKeyDown = 0x0100;
    private const uint WmKeyUp = 0x0101;
    private const uint BmSetState = 0x00F3;
    private const uint BmClick = 0x00F5;

    private readonly IntPtr _sourceWindow;
    private readonly WindowsCaptureInputGate _gate;
    private readonly uint _timeoutMilliseconds;
    private readonly object _pointerStateSync = new();
    private IntPtr _pressedStandardButton;

    public WindowsCaptureTargetedInputInjector(
        IntPtr sourceWindow,
        WindowsCaptureInputGate gate,
        uint timeoutMilliseconds = 250)
    {
        if (sourceWindow == IntPtr.Zero || !IsWindow(sourceWindow))
            throw new ArgumentException("Source HWND must be a live window.", nameof(sourceWindow));
        _gate = gate ?? throw new ArgumentNullException(nameof(gate));
        if (timeoutMilliseconds is < 25 or > 5000)
            throw new ArgumentOutOfRangeException(nameof(timeoutMilliseconds));
        _sourceWindow = sourceWindow;
        _timeoutMilliseconds = timeoutMilliseconds;
    }

    public WindowsCaptureInputInjectionResult InjectPointer(WindowsCapturePointerInput input)
    {
        ArgumentNullException.ThrowIfNull(input);
        input.Validate();
        var admission = _gate.Admit(input.Generation, input.Sequence);
        if (!admission.Allowed)
            return Rejected(input.Sequence, input.Generation, admission.Rejection);
        if (!IsWindow(_sourceWindow))
            return Failed(WindowsCaptureInputInjectionStatus.TargetLost, input.Sequence, input.Generation, IntPtr.Zero, "Source HWND is no longer valid.");

        if (!TryResolvePointerDestination(input.ClientPixelX, input.ClientPixelY, out var destination, out var destinationPoint))
            return Failed(WindowsCaptureInputInjectionStatus.Unsupported, input.Sequence, input.Generation, IntPtr.Zero, "Pointer destination could not be proven inside the source client tree.");

        var message = ResolvePointerMessage(input);
        if (message == 0)
            return Failed(WindowsCaptureInputInjectionStatus.Unsupported, input.Sequence, input.Generation, destination, "Pointer event kind/button is not supported by the targeted injector.");

        // Native Button and WinForms Button controls intentionally expose BM_CLICK as
        // their cross-thread activation contract. Raw WM_LBUTTONDOWN/UP requires real
        // foreground capture state and can be acknowledged without raising Click. Keep
        // this compatibility path restricted to an exact child already proven to belong
        // to the captured source tree; all other controls continue through pixel input.
        if (input.Button == WindowsCapturePointerButton.Left && IsStandardButton(destination))
        {
            if (input.Kind == WindowsCapturePointerEventKind.ButtonDown)
            {
                lock (_pointerStateSync) _pressedStandardButton = destination;
                return Send(
                    destination,
                    BmSetState,
                    new IntPtr(1),
                    IntPtr.Zero,
                    input.Sequence,
                    input.Generation);
            }

            if (input.Kind == WindowsCapturePointerEventKind.ButtonUp)
            {
                bool matchesPressedButton;
                lock (_pointerStateSync)
                {
                    matchesPressedButton = _pressedStandardButton == destination;
                    _pressedStandardButton = IntPtr.Zero;
                }
                if (!matchesPressedButton)
                    return Failed(WindowsCaptureInputInjectionStatus.Unsupported, input.Sequence, input.Generation, destination, "Button release does not match the targeted pressed control.");

                var released = Send(
                    destination,
                    BmSetState,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    input.Sequence,
                    input.Generation);
                if (!released.Delivered) return released;
                return Send(
                    destination,
                    BmClick,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    input.Sequence,
                    input.Generation);
            }
        }

        var wParam = BuildPointerWParam(input);
        IntPtr lParam;
        if (input.Kind == WindowsCapturePointerEventKind.Wheel)
        {
            var screenPoint = new NativePoint(input.ClientPixelX, input.ClientPixelY);
            if (!ClientToScreen(_sourceWindow, ref screenPoint))
                return NativeError(input.Sequence, input.Generation, destination, "ClientToScreen(mouse-wheel)");
            var keyState = unchecked((uint)(nuint)wParam) & 0xFFFFU;
            var wheel = (uint)(ushort)input.WheelDelta << 16;
            wParam = new IntPtr(unchecked((int)(keyState | wheel)));
            lParam = PackPoint(screenPoint.X, screenPoint.Y);
        }
        else
        {
            lParam = PackPoint(destinationPoint.X, destinationPoint.Y);
        }

        // Conventional Win32 controls establish hover/hit-test state from the move
        // immediately preceding a button press. A captured surface has no real cursor
        // over the source HWND, so synthesize that targeted move on the exact proven
        // child before the down message. This remains process-local message routing;
        // it never moves the desktop cursor or falls back to SendInput.
        if (input.Kind == WindowsCapturePointerEventKind.ButtonDown)
        {
            var moveResult = Send(
                destination,
                WmMouseMove,
                BuildPointerModifierWParam(input),
                lParam,
                input.Sequence,
                input.Generation);
            if (!moveResult.Delivered) return moveResult;
        }

        return Send(destination, message, wParam, lParam, input.Sequence, input.Generation);
    }

    public WindowsCaptureInputInjectionResult InjectKey(WindowsCaptureKeyInput input)
    {
        ArgumentNullException.ThrowIfNull(input);
        input.Validate();
        var admission = _gate.Admit(input.Generation, input.Sequence);
        if (!admission.Allowed)
            return Rejected(input.Sequence, input.Generation, admission.Rejection);
        if (!IsWindow(_sourceWindow))
            return Failed(WindowsCaptureInputInjectionStatus.TargetLost, input.Sequence, input.Generation, IntPtr.Zero, "Source HWND is no longer valid.");

        var sourceThread = GetWindowThreadProcessId(_sourceWindow, out _);
        if (sourceThread == 0)
            return NativeError(input.Sequence, input.Generation, IntPtr.Zero, "GetWindowThreadProcessId");

        var gui = new GuiThreadInfo { Size = (uint)Marshal.SizeOf<GuiThreadInfo>() };
        if (!GetGUIThreadInfo(sourceThread, ref gui))
            return NativeError(input.Sequence, input.Generation, IntPtr.Zero, "GetGUIThreadInfo");

        var destination = gui.Focus;
        if (destination == IntPtr.Zero || !IsWindow(destination) || !BelongsToSourceTree(destination))
            return Failed(WindowsCaptureInputInjectionStatus.Unsupported, input.Sequence, input.Generation, destination, "Focused HWND is not proven to belong to the captured source tree.");

        var message = input.Kind == WindowsCaptureKeyEventKind.KeyDown ? WmKeyDown : WmKeyUp;
        var lParam = BuildKeyLParam(input);
        return Send(destination, message, new IntPtr(input.VirtualKey), lParam, input.Sequence, input.Generation);
    }

    private bool TryResolvePointerDestination(int clientX, int clientY, out IntPtr destination, out NativePoint destinationPoint)
    {
        destination = _sourceWindow;
        destinationPoint = new NativePoint(clientX, clientY);
        if (!GetClientRect(_sourceWindow, out var sourceClient) || !sourceClient.Contains(destinationPoint))
            return false;

        // Walk down the child hierarchy using coordinates local to each proven parent.
        for (var depth = 0; depth < 32; depth++)
        {
            var child = ChildWindowFromPointEx(destination, destinationPoint, CwpSkipInvisible | CwpSkipDisabled);
            if (child == IntPtr.Zero || child == destination) break;
            if (!IsChild(_sourceWindow, child)) return false;

            var pointForChild = destinationPoint;
            if (MapWindowPoints(destination, child, ref pointForChild, 1) == 0)
            {
                var error = Marshal.GetLastWin32Error();
                if (error != 0) return false;
            }
            destination = child;
            destinationPoint = pointForChild;
        }

        return destination == _sourceWindow || IsChild(_sourceWindow, destination);
    }

    private bool BelongsToSourceTree(IntPtr candidate) =>
        candidate == _sourceWindow || IsChild(_sourceWindow, candidate);

    private static bool IsStandardButton(IntPtr candidate)
    {
        var className = new StringBuilder(256);
        if (GetClassNameW(candidate, className, className.Capacity) <= 0) return false;
        var value = className.ToString();
        return value.Equals("Button", StringComparison.OrdinalIgnoreCase)
            || value.StartsWith("WindowsForms10.BUTTON.", StringComparison.OrdinalIgnoreCase);
    }

    private WindowsCaptureInputInjectionResult Send(
        IntPtr destination,
        uint message,
        IntPtr wParam,
        IntPtr lParam,
        long sequence,
        int generation)
    {
        SetLastError(0);
        var delivered = SendMessageTimeout(
            destination,
            message,
            wParam,
            lParam,
            SmtoAbortIfHung | SmtoBlock,
            _timeoutMilliseconds,
            out _);
        if (delivered != IntPtr.Zero)
            return new WindowsCaptureInputInjectionResult(
                WindowsCaptureInputInjectionStatus.Delivered,
                WindowsCaptureInputRejection.None,
                sequence,
                generation,
                destination.ToInt64(),
                null);

        var error = Marshal.GetLastWin32Error();
        if (error == 1460)
            return Failed(WindowsCaptureInputInjectionStatus.TimedOut, sequence, generation, destination, "SendMessageTimeout timed out.");
        return Failed(
            WindowsCaptureInputInjectionStatus.NativeFailure,
            sequence,
            generation,
            destination,
            error == 0 ? "SendMessageTimeout failed without a Win32 error." : new Win32Exception(error).Message);
    }

    private static uint ResolvePointerMessage(WindowsCapturePointerInput input) => input.Kind switch
    {
        WindowsCapturePointerEventKind.Move => WmMouseMove,
        WindowsCapturePointerEventKind.Wheel => WmMouseWheel,
        WindowsCapturePointerEventKind.ButtonDown when input.Button == WindowsCapturePointerButton.Left => WmLButtonDown,
        WindowsCapturePointerEventKind.ButtonUp when input.Button == WindowsCapturePointerButton.Left => WmLButtonUp,
        WindowsCapturePointerEventKind.ButtonDown when input.Button == WindowsCapturePointerButton.Right => WmRButtonDown,
        WindowsCapturePointerEventKind.ButtonUp when input.Button == WindowsCapturePointerButton.Right => WmRButtonUp,
        WindowsCapturePointerEventKind.ButtonDown when input.Button == WindowsCapturePointerButton.Middle => WmMButtonDown,
        WindowsCapturePointerEventKind.ButtonUp when input.Button == WindowsCapturePointerButton.Middle => WmMButtonUp,
        _ => 0
    };

    private static IntPtr BuildPointerWParam(WindowsCapturePointerInput input)
    {
        var flags = unchecked((uint)(nuint)BuildPointerModifierWParam(input));
        if (input.Kind == WindowsCapturePointerEventKind.ButtonDown)
        {
            flags |= input.Button switch
            {
                WindowsCapturePointerButton.Left => 0x0001U,
                WindowsCapturePointerButton.Right => 0x0002U,
                WindowsCapturePointerButton.Middle => 0x0010U,
                _ => 0U
            };
        }
        return new IntPtr(unchecked((int)flags));
    }

    private static IntPtr BuildPointerModifierWParam(WindowsCapturePointerInput input)
    {
        uint flags = 0;
        if (input.Shift) flags |= 0x0004U;
        if (input.Control) flags |= 0x0008U;
        return new IntPtr(unchecked((int)flags));
    }

    private static IntPtr BuildKeyLParam(WindowsCaptureKeyInput input)
    {
        uint value = 1U;
        var scanCode = (uint)(ushort)input.ScanCode;
        value |= (scanCode & 0xFFU) << 16;
        if (input.Extended || scanCode > 0xFFU) value |= 1U << 24;
        if (input.Repeat || input.Kind == WindowsCaptureKeyEventKind.KeyUp) value |= 1U << 30;
        if (input.Kind == WindowsCaptureKeyEventKind.KeyUp) value |= 1U << 31;
        return new IntPtr(unchecked((int)value));
    }

    private static IntPtr PackPoint(int x, int y)
    {
        var low = (uint)(ushort)x;
        var high = (uint)(ushort)y << 16;
        return new IntPtr(unchecked((int)(low | high)));
    }

    private static WindowsCaptureInputInjectionResult Rejected(long sequence, int generation, WindowsCaptureInputRejection rejection) =>
        new(WindowsCaptureInputInjectionStatus.Rejected, rejection, sequence, generation, 0, null);

    private static WindowsCaptureInputInjectionResult Failed(
        WindowsCaptureInputInjectionStatus status,
        long sequence,
        int generation,
        IntPtr destination,
        string failure) =>
        new(status, WindowsCaptureInputRejection.InjectorFailed, sequence, generation, destination.ToInt64(), failure);

    private static WindowsCaptureInputInjectionResult NativeError(long sequence, int generation, IntPtr destination, string operation)
    {
        var error = Marshal.GetLastWin32Error();
        return Failed(
            WindowsCaptureInputInjectionStatus.NativeFailure,
            sequence,
            generation,
            destination,
            error == 0 ? $"{operation} failed without a Win32 error." : $"{operation}: {new Win32Exception(error).Message}");
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public NativePoint(int x, int y)
        {
            X = x;
            Y = y;
        }
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;

        public readonly bool Contains(NativePoint point) =>
            point.X >= Left && point.Y >= Top && point.X < Right && point.Y < Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct GuiThreadInfo
    {
        public uint Size;
        public uint Flags;
        public IntPtr Active;
        public IntPtr Focus;
        public IntPtr Capture;
        public IntPtr MenuOwner;
        public IntPtr MoveSize;
        public IntPtr Caret;
        public NativeRect CaretRect;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr windowHandle);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsChild(IntPtr parentWindow, IntPtr windowHandle);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetClientRect(IntPtr windowHandle, out NativeRect rectangle);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ClientToScreen(IntPtr windowHandle, ref NativePoint point);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int MapWindowPoints(IntPtr fromWindow, IntPtr toWindow, ref NativePoint point, uint pointCount);

    [DllImport("user32.dll")]
    private static extern IntPtr ChildWindowFromPointEx(IntPtr parentWindow, NativePoint point, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr windowHandle, out uint processId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetGUIThreadInfo(uint threadId, ref GuiThreadInfo info);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(
        IntPtr windowHandle,
        uint message,
        IntPtr wParam,
        IntPtr lParam,
        uint flags,
        uint timeout,
        out IntPtr result);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetClassNameW(IntPtr windowHandle, StringBuilder className, int maximumCount);

    [DllImport("kernel32.dll")]
    private static extern void SetLastError(uint errorCode);
}
