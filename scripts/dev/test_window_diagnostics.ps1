Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class WinDiag {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr hWnd, uint gaFlags);

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    public static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

    public struct RECT { public int Left, Top, Right, Bottom; }

    public static void Run() {
        EnumWindows((hWnd, lParam) => {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (!IsWindowVisible(hWnd)) return true;

            var title = new StringBuilder(512);
            GetWindowText(hWnd, title, 512);
            var cls = new StringBuilder(512);
            GetClassName(hWnd, cls, 512);

            IntPtr root = GetAncestor(hWnd, 2); // GA_ROOT
            bool isRoot = (root == hWnd);
            IntPtr owner = GetWindow(hWnd, 4); // GW_OWNER

            long style = GetWindowLongPtr(hWnd, -16).ToInt64(); // GWL_STYLE
            long exStyle = GetWindowLongPtr(hWnd, -20).ToInt64(); // GWL_EXSTYLE
            bool toolWindow = (exStyle & 0x00000080L) != 0; // WS_EX_TOOLWINDOW
            bool appWindow = (exStyle & 0x00040000L) != 0; // WS_EX_APPWINDOW

            int cloaked = 0;
            DwmGetWindowAttribute(hWnd, 14, out cloaked, 4); // DWMWA_CLOAKED

            RECT rc;
            GetWindowRect(hWnd, out rc);
            int w = rc.Right - rc.Left;
            int h = rc.Bottom - rc.Top;

            if (w > 100 && h > 100 && title.Length > 0) {
                Console.WriteLine($"HWND=0x{hWnd.ToInt64():X} PID={pid} isRoot={isRoot} owner=0x{owner.ToInt64():X} tool={toolWindow} appWin={appWindow} cloaked={cloaked} w={w} h={h} cls='{cls}' title='{title}'");
            }
            return true;
        }, IntPtr.Zero);
    }
}
"@

[WinDiag]::Run()
