namespace CloudOS.Host.Native;

public enum NativeHostShortcut
{
    ToggleStartMenu,
    CycleWindows,
    CloseActiveWindow
}

public readonly record struct NativeKeyboardInput(
    uint VirtualKey,
    bool IsKeyUp,
    bool AltDown,
    bool IsInjected);

public readonly record struct NativeKeyboardDecision(bool Suppress, NativeHostShortcut? Shortcut)
{
    internal static NativeKeyboardDecision Pass => new(false, null);
    internal static NativeKeyboardDecision Consume(NativeHostShortcut? shortcut = null) => new(true, shortcut);
}

/// <summary>
/// Stateful, side-effect-free routing policy for CloudOS-owned system shortcuts.
/// Normal application input is never consumed. The Windows key is captured as a
/// sequence so Win+R/Win+D cannot escape and a bare Win toggles the CloudOS Start
/// menu only after the key is released without a chord.
/// </summary>
public sealed class NativeKeyboardShortcutRouter
{
    internal const uint VirtualKeyTab = 0x09;
    internal const uint VirtualKeyR = 0x52;
    internal const uint VirtualKeyD = 0x44;
    internal const uint VirtualKeyF4 = 0x73;
    internal const uint VirtualKeyLeftWin = 0x5B;
    internal const uint VirtualKeyRightWin = 0x5C;

    private readonly HashSet<uint> _suppressedWinChordKeys = [];
    private bool _leftWinDown;
    private bool _rightWinDown;
    private bool _winChordUsed;
    private bool _altTabHeld;
    private bool _altF4Held;

    public bool HasCapture =>
        _leftWinDown ||
        _rightWinDown ||
        _altTabHeld ||
        _altF4Held ||
        _suppressedWinChordKeys.Count > 0;

    public NativeKeyboardDecision Route(NativeKeyboardInput input, bool cloudOsForeground)
    {
        var virtualKey = input.VirtualKey;
        var isWinKey = virtualKey is VirtualKeyLeftWin or VirtualKeyRightWin;
        var suppressedWinChordKey = _suppressedWinChordKeys.Contains(virtualKey);
        var capturedRelease =
            (isWinKey && (_leftWinDown || _rightWinDown)) ||
            suppressedWinChordKey ||
            (virtualKey == VirtualKeyTab && _altTabHeld) ||
            (virtualKey == VirtualKeyF4 && _altF4Held);

        if (!cloudOsForeground)
        {
            // If focus leaves CloudOS while a reserved sequence is already captured,
            // consume only the release needed to restore router state. Never execute
            // a CloudOS action after focus has moved to an unrelated application.
            if (_leftWinDown || _rightWinDown) _winChordUsed = true;
            if (!capturedRelease) return NativeKeyboardDecision.Pass;
        }

        var winDown = _leftWinDown || _rightWinDown;
        if (input.IsInjected)
        {
            // Synthetic low-level keyboard input may not invoke privileged shell
            // actions. Reserved injected sequences are swallowed while CloudOS owns
            // focus so they also cannot fall through to the Windows shell.
            if (isWinKey ||
                (virtualKey == VirtualKeyTab && (input.AltDown || _altTabHeld)) ||
                (virtualKey == VirtualKeyF4 && (input.AltDown || _altF4Held)) ||
                (winDown && (virtualKey is VirtualKeyR or VirtualKeyD)))
            {
                return NativeKeyboardDecision.Consume();
            }
            return NativeKeyboardDecision.Pass;
        }

        if (isWinKey)
        {
            if (!input.IsKeyUp)
            {
                if (virtualKey == VirtualKeyLeftWin) _leftWinDown = true;
                else _rightWinDown = true;
                return NativeKeyboardDecision.Consume();
            }

            if (virtualKey == VirtualKeyLeftWin) _leftWinDown = false;
            else _rightWinDown = false;

            var noWinKeyRemains = !_leftWinDown && !_rightWinDown;
            var shouldToggleStart = cloudOsForeground && noWinKeyRemains && !_winChordUsed;
            if (noWinKeyRemains) _winChordUsed = false;
            return NativeKeyboardDecision.Consume(
                shouldToggleStart ? NativeHostShortcut.ToggleStartMenu : null);
        }

        winDown = _leftWinDown || _rightWinDown;
        if (winDown && !input.IsKeyUp) _winChordUsed = true;

        if ((virtualKey is VirtualKeyR or VirtualKeyD) && (winDown || suppressedWinChordKey))
        {
            if (input.IsKeyUp) _suppressedWinChordKeys.Remove(virtualKey);
            else _suppressedWinChordKeys.Add(virtualKey);
            return NativeKeyboardDecision.Consume();
        }

        if (virtualKey == VirtualKeyTab && (input.AltDown || _altTabHeld))
        {
            if (input.IsKeyUp)
            {
                _altTabHeld = false;
                return NativeKeyboardDecision.Consume();
            }
            if (_altTabHeld) return NativeKeyboardDecision.Consume();
            _altTabHeld = true;
            return NativeKeyboardDecision.Consume(NativeHostShortcut.CycleWindows);
        }

        if (virtualKey == VirtualKeyF4 && (input.AltDown || _altF4Held))
        {
            if (input.IsKeyUp)
            {
                _altF4Held = false;
                return NativeKeyboardDecision.Consume();
            }
            if (_altF4Held) return NativeKeyboardDecision.Consume();
            _altF4Held = true;
            return NativeKeyboardDecision.Consume(NativeHostShortcut.CloseActiveWindow);
        }

        return NativeKeyboardDecision.Pass;
    }
}
