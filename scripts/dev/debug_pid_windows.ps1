Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public class ThreadWinDebug {
    public delegate bool EnumThreadDelegate(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumThreadWindows(int dwThreadId, EnumThreadDelegate lpfn, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    public static void InspectProcess(int pid) {
        System.Diagnostics.Process proc = System.Diagnostics.Process.GetProcessById(pid);
        Console.WriteLine("Process PID: " + pid + " Threads: " + proc.Threads.Count);
        foreach (System.Diagnostics.ProcessThread thread in proc.Threads) {
            EnumThreadWindows(thread.Id, (hWnd, lParam) => {
                StringBuilder title = new StringBuilder(256);
                GetWindowText(hWnd, title, 256);
                StringBuilder cls = new StringBuilder(256);
                GetClassName(hWnd, cls, 256);
                bool visible = IsWindowVisible(hWnd);
                Console.WriteLine("  Thread: " + thread.Id + " HWND: 0x" + hWnd.ToString("X") + " (" + hWnd + ") Class: " + cls + " Title: '" + title + "' Visible: " + visible);
                
                // Force show and foreground
                ShowWindow(hWnd, 3); // SW_MAXIMIZE
                SetForegroundWindow(hWnd);
                return true;
            }, IntPtr.Zero);
        }
    }
}
'@

$proc = Get-Process -Name 'cloudos_flutter_shell' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc) {
    [ThreadWinDebug]::InspectProcess($proc.Id)
} else {
    Write-Host "No process found"
}
