Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class WinEnumNotepad {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    public static void Run(uint targetPid) {
        EnumWindows((hWnd, lParam) => {
            uint procId;
            GetWindowThreadProcessId(hWnd, out procId);
            if (procId == targetPid) {
                var title = new System.Text.StringBuilder(256);
                GetWindowText(hWnd, title, 256);
                var cls = new System.Text.StringBuilder(256);
                GetClassName(hWnd, cls, 256);
                Console.WriteLine("HWND=" + hWnd + " Class=" + cls + " Vis=" + IsWindowVisible(hWnd) + " Title=" + title);
            }
            return true;
        }, IntPtr.Zero);
    }
}
"@

$p = Get-Process notepad -ErrorAction SilentlyContinue
if ($p) {
    [WinEnumNotepad]::Run($p[0].Id)
} else {
    Write-Host "No notepad process"
}
