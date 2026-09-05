Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class WinFindDirect {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    public static void Check() {
        IntPtr hwnd = FindWindow("FLUTTER_RUNNER_WIN32_WINDOW", null);
        if (hwnd != IntPtr.Zero) {
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            bool vis = IsWindowVisible(hwnd);
            Console.WriteLine("FOUND_FLUTTER_HWND: 0x" + hwnd.ToString("X") + " PID: " + pid + " Visible: " + vis);
        } else {
            Console.WriteLine("FLUTTER_WINDOW_NOT_FOUND");
        }
    }
}
'@

[WinFindDirect]::Check()
