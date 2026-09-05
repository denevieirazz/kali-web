Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class WindowCapture {
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBmp, uint nFlags);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public static void Capture(IntPtr hWnd, string filePath) {
        RECT rect;
        GetWindowRect(hWnd, out rect);
        int width = rect.Right - rect.Left;
        int height = rect.Bottom - rect.Top;
        if (width <= 0) width = 800;
        if (height <= 0) height = 600;

        using (Bitmap bmp = new Bitmap(width, height, PixelFormat.Format32bppArgb)) {
            using (Graphics g = Graphics.FromImage(bmp)) {
                IntPtr hdc = g.GetHdc();
                try {
                    PrintWindow(hWnd, hdc, 2); // PW_RENDERFULLCONTENT = 2
                } finally {
                    g.ReleaseHdc(hdc);
                }
            }
            bmp.Save(filePath, ImageFormat.Png);
        }
    }
}
'@ -ReferencedAssemblies System.Drawing

$proc = Get-Process -Name 'cloudos_flutter_shell' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
    $artifactDir = 'C:\Users\dougl\.gemini\antigravity\brain\e0ea3935-20e3-4f15-a2a8-79266b2d4907'
    $outPath = Join-Path $artifactDir 'cloudos_v21_etapa2_screenshot.png'
    [WindowCapture]::Capture($proc.MainWindowHandle, $outPath)
    Write-Host "CAPTURED: $outPath ($(Get-Item $outPath | Select-Object -ExpandProperty Length) bytes)"
} else {
    Write-Host "NO_WINDOW_HANDLE_FOUND"
}
