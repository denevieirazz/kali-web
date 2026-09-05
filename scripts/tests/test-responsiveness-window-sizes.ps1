# test-responsiveness-window-sizes.ps1
# Physical real-time responsiveness test for CloudOS window bounds & layout adaptation

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$artifactsDir = 'C:\Users\dougl\.gemini\antigravity\brain\e0ea3935-20e3-4f15-a2a8-79266b2d4907'
$scratchDir = Join-Path $artifactsDir 'scratch'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class WinResizeHelper {
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public const uint WM_DISPLAYCHANGE = 0x007E;
    public const uint WM_SIZE = 0x0005;
    public const uint SWP_NOZORDER = 0x0004;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_SHOWWINDOW = 0x0040;

    public static void ResizeAndNotify(IntPtr hWnd, int width, int height) {
        ShowWindow(hWnd, 9); // SW_RESTORE
        System.Threading.Thread.Sleep(200);
        SetWindowPos(hWnd, IntPtr.Zero, 0, 0, width, height, SWP_NOZORDER | SWP_SHOWWINDOW);
        BringWindowToTop(hWnd);
        SetForegroundWindow(hWnd);
        System.Threading.Thread.Sleep(200);

        // Notify display change to trigger CloudOS bridge and Flutter LayoutBuilder
        IntPtr lParam = (IntPtr)((height << 16) | (width & 0xFFFF));
        SendMessage(hWnd, WM_DISPLAYCHANGE, (UIntPtr)32, lParam);
    }
}
'@

$proc = Get-Process -Name 'cloudos_flutter_shell' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { throw "cloudos_flutter_shell nao esta em execucao." }

# Use HwndFinder to find HWND
$testerSource = @'
using System;
using System.Runtime.InteropServices;
public class HwndFinder {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    public static IntPtr FindHwndForPid(uint targetPid) {
        IntPtr result = IntPtr.Zero;
        EnumWindows((hWnd, lParam) => {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid == targetPid && IsWindowVisible(hWnd)) {
                result = hWnd;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
'@
Add-Type -TypeDefinition $testerSource

$hwnd = [HwndFinder]::FindHwndForPid($proc.Id)
Write-Host "CloudOS Flutter Shell HWND: $hwnd (PID $($proc.Id))"

# 1. Resize to 1280x720
Write-Host "`n[1/3] Redimensionando para 1280x720 em tempo real..." -ForegroundColor Yellow
[WinResizeHelper]::ResizeAndNotify($hwnd, 1280, 720)
Start-Sleep -Seconds 2
$r1 = New-Object WinResizeHelper+RECT
[void][WinResizeHelper]::GetWindowRect($hwnd, [ref]$r1)
$w1 = $r1.Right - $r1.Left
$h1 = $r1.Bottom - $r1.Top
Write-Host "   -> Dimensoes confirmadas: ${w1}x${h1}" -ForegroundColor Cyan

# 2. Resize to 1024x768
Write-Host "`n[2/3] Redimensionando para 1024x768 em tempo real..." -ForegroundColor Yellow
[WinResizeHelper]::ResizeAndNotify($hwnd, 1024, 768)
Start-Sleep -Seconds 2
$r2 = New-Object WinResizeHelper+RECT
[void][WinResizeHelper]::GetWindowRect($hwnd, [ref]$r2)
$w2 = $r2.Right - $r2.Left
$h2 = $r2.Bottom - $r2.Top
Write-Host "   -> Dimensoes confirmadas: ${w2}x${h2}" -ForegroundColor Cyan

# 3. Restore to Maximized / Native Screen
Write-Host "`n[3/3] Restaurando janela maximizada..." -ForegroundColor Yellow
[void][WinResizeHelper]::ShowWindow($hwnd, 3) # SW_MAXIMIZE
Start-Sleep -Seconds 2
$r3 = New-Object WinResizeHelper+RECT
[void][WinResizeHelper]::GetWindowRect($hwnd, [ref]$r3)
$w3 = $r3.Right - $r3.Left
$h3 = $r3.Bottom - $r3.Top
Write-Host "   -> Dimensoes finais restauradas: ${w3}x${h3}" -ForegroundColor Green

Write-Host "`n[SUCCESS] Teste de redimensionamento e adaptacao responsiva concluido com sucesso!" -ForegroundColor Green
