# interact_cloudos.ps1
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class WinInput {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;

    public static void ForceForeground(IntPtr hWnd) {
        uint pid;
        uint targetThread = GetWindowThreadProcessId(hWnd, out pid);
        uint currentThread = GetCurrentThreadId();
        AttachThreadInput(currentThread, targetThread, true);
        ShowWindow(hWnd, 9); // SW_RESTORE
        BringWindowToTop(hWnd);
        SetForegroundWindow(hWnd);
        ShowWindow(hWnd, 3); // SW_MAXIMIZE
        AttachThreadInput(currentThread, targetThread, false);
    }

    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(80);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
    }

    public static void DoubleClick(int x, int y) {
        Click(x, y);
        System.Threading.Thread.Sleep(100);
        Click(x, y);
    }
}
'@

$proc = Get-Process -Name 'cloudos_flutter_shell' | Select-Object -First 1
$hwnd = [IntPtr]2230758 # HWND of CloudOS Desktop

[WinInput]::ForceForeground($hwnd)
Start-Sleep -Milliseconds 500

# Double click desktop icon Arquivos (x=85, y=60)
[WinInput]::DoubleClick(85, 60)
Start-Sleep -Seconds 1
Write-Host "DOUBLE_CLICKED_ARQUIVOS"
