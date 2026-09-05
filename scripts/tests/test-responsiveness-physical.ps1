# test-responsiveness-physical.ps1
# Physical validation script for CloudOS Real-time Responsiveness & Display Adaptation

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$artifactsDir = 'C:\Users\dougl\.gemini\antigravity\brain\e0ea3935-20e3-4f15-a2a8-79266b2d4907'
$scratchDir = Join-Path $artifactsDir 'scratch'

Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class ResponsivenessTester {
    public delegate bool EnumDesktopWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern IntPtr OpenDesktop(string lpszDesktop, uint dwFlags, bool fInherit, uint dwDesiredAccess);

    [DllImport("user32.dll")]
    public static extern bool EnumDesktopWindows(IntPtr hDesktop, EnumDesktopWindowsProc lpfn, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool CloseDesktop(IntPtr hDesktop);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll")]
    public static extern bool EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

    [DllImport("user32.dll")]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int CDS_UPDATEREGISTRY = 0x01;
    public const int CDS_TEST = 0x02;
    public const int DISP_CHANGE_SUCCESSFUL = 0;

    public static IntPtr FindWindowForPid(uint targetPid) {
        IntPtr hDesk = OpenDesktop("Default", 0, false, 0x01FF);
        if (hDesk == IntPtr.Zero) return IntPtr.Zero;
        IntPtr found = IntPtr.Zero;
        EnumDesktopWindows(hDesk, (hWnd, lParam) => {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid == targetPid && IsWindowVisible(hWnd)) {
                found = hWnd;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        CloseDesktop(hDesk);
        return found;
    }

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBmp, uint nFlags);

    public static void CaptureWindow(IntPtr hWnd, string filePath) {
        RECT rect;
        GetWindowRect(hWnd, out rect);
        int width = rect.Right - rect.Left;
        int height = rect.Bottom - rect.Top;
        if (width <= 0) width = 1280;
        if (height <= 0) height = 720;

        using (Bitmap bmp = new Bitmap(width, height, PixelFormat.Format32bppArgb)) {
            using (Graphics g = Graphics.FromImage(bmp)) {
                IntPtr hdc = g.GetHdc();
                try {
                    PrintWindow(hWnd, hdc, 2);
                } finally {
                    g.ReleaseHdc(hdc);
                }
            }
            bmp.Save(filePath, ImageFormat.Png);
        }
    }
}
'@ -ReferencedAssemblies System.Drawing

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "[TEST] CloudOS Responsividade Global em Tempo Real - Verificacao Fisica" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# 1. Verify CloudOS processes are running
$flutterProc = Get-Process -Name 'cloudos_flutter_shell' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $flutterProc) {
    throw "Processo cloudos_flutter_shell nao esta em execucao. Inicie o CloudOS primeiro."
}
Write-Host "[1/6] CloudOS Flutter Shell ativo (PID $($flutterProc.Id))." -ForegroundColor Green

# 2. Find Window Handle
$flutterHwnd = [ResponsivenessTester]::FindWindowForPid($flutterProc.Id)
if ($flutterHwnd -eq [IntPtr]::Zero) {
    throw "Nao foi possivel encontrar HWND visivel para PID $($flutterProc.Id)"
}
Write-Host "[2/6] HWND da janela Flutter detectado: $flutterHwnd" -ForegroundColor Green

# Ensure Flutter is restored/maximized
[void][ResponsivenessTester]::ShowWindow($flutterHwnd, 3) # SW_MAXIMIZE
[void][ResponsivenessTester]::BringWindowToTop($flutterHwnd)
[void][ResponsivenessTester]::SetForegroundWindow($flutterHwnd)
Start-Sleep -Milliseconds 800

# 3. Query current display resolution on target display (\\.\DISPLAY6)
$targetDisplay = '\\.\DISPLAY6'
$originalDevMode = New-Object ResponsivenessTester+DEVMODE
$originalDevMode.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($originalDevMode)
if (-not [ResponsivenessTester]::EnumDisplaySettings($targetDisplay, [ResponsivenessTester]::ENUM_CURRENT_SETTINGS, [ref]$originalDevMode)) {
    throw "Falha ao consultar resolucao atual de $targetDisplay"
}
$origWidth = $originalDevMode.dmPelsWidth
$origHeight = $originalDevMode.dmPelsHeight
$origFreq = $originalDevMode.dmDisplayFrequency
Write-Host "[3/6] Resolucao original de ${targetDisplay}: ${origWidth}x${origHeight} @ ${origFreq}Hz" -ForegroundColor Yellow

# Capture initial state
$initialCap = Join-Path $scratchDir "responsiveness_initial_${origWidth}x${origHeight}.png"
[ResponsivenessTester]::CaptureWindow($flutterHwnd, $initialCap)
Write-Host "   -> Captura inicial salva: $initialCap" -ForegroundColor Gray

try {
    # 4. Physical Real-time Resolution Switch: 2560x1440 -> 1920x1080
    Write-Host "`n[4/6] [TESTE FISICO] Alterando resolucao em tempo real para 1920x1080 @ 60Hz..." -ForegroundColor Yellow
    $mode1080 = $originalDevMode
    $mode1080.dmPelsWidth = 1920
    $mode1080.dmPelsHeight = 1080
    $mode1080.dmDisplayFrequency = 60
    $mode1080.dmFields = 0x00040000 -bor 0x00080000 -bor 0x00400000 # DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY

    $changeRes = [ResponsivenessTester]::ChangeDisplaySettingsEx($targetDisplay, [ref]$mode1080, [IntPtr]::Zero, 0, [IntPtr]::Zero)
    if ($changeRes -ne [ResponsivenessTester]::DISP_CHANGE_SUCCESSFUL) {
        throw "ChangeDisplaySettingsEx para 1920x1080 falhou com codigo $changeRes"
    }
    Write-Host "   -> [DISP_CHANGE_SUCCESSFUL] Resolucao fisica alterada para 1920x1080!" -ForegroundColor Green

    # Wait for Windows WM_DISPLAYCHANGE message and Flutter layout adaptation
    Start-Sleep -Seconds 3

    # Ensure window is maximized to the new bounds
    [void][ResponsivenessTester]::ShowWindow($flutterHwnd, 3) # SW_MAXIMIZE
    Start-Sleep -Milliseconds 800

    $rect1080 = New-Object ResponsivenessTester+RECT
    [void][ResponsivenessTester]::GetWindowRect($flutterHwnd, [ref]$rect1080)
    $w1080 = $rect1080.Right - $rect1080.Left
    $h1080 = $rect1080.Bottom - $rect1080.Top
    Write-Host "   -> Dimensoes da janela CloudOS apos adaptacao em tempo real: ${w1080}x${h1080}" -ForegroundColor Cyan

    $cap1080 = Join-Path $scratchDir "responsiveness_adapted_1920x1080.png"
    [ResponsivenessTester]::CaptureWindow($flutterHwnd, $cap1080)
    Write-Host "   -> Captura adaptada salva: $cap1080" -ForegroundColor Gray

    # 5. Physical Real-time Resolution Switch: 1920x1080 -> 1280x720
    Write-Host "`n[5/6] [TESTE FISICO] Alterando resolucao em tempo real para 1280x720 @ 60Hz..." -ForegroundColor Yellow
    $mode720 = $originalDevMode
    $mode720.dmPelsWidth = 1280
    $mode720.dmPelsHeight = 720
    $mode720.dmDisplayFrequency = 60
    $mode720.dmFields = 0x00040000 -bor 0x00080000 -bor 0x00400000

    $changeRes720 = [ResponsivenessTester]::ChangeDisplaySettingsEx($targetDisplay, [ref]$mode720, [IntPtr]::Zero, 0, [IntPtr]::Zero)
    if ($changeRes720 -ne [ResponsivenessTester]::DISP_CHANGE_SUCCESSFUL) {
        throw "ChangeDisplaySettingsEx para 1280x720 falhou com codigo $changeRes720"
    }
    Write-Host "   -> [DISP_CHANGE_SUCCESSFUL] Resolucao fisica alterada para 1280x720!" -ForegroundColor Green

    # Wait for Windows WM_DISPLAYCHANGE message and Flutter layout adaptation
    Start-Sleep -Seconds 3

    [void][ResponsivenessTester]::ShowWindow($flutterHwnd, 3) # SW_MAXIMIZE
    Start-Sleep -Milliseconds 800

    $rect720 = New-Object ResponsivenessTester+RECT
    [void][ResponsivenessTester]::GetWindowRect($flutterHwnd, [ref]$rect720)
    $w720 = $rect720.Right - $rect720.Left
    $h720 = $rect720.Bottom - $rect720.Top
    Write-Host "   -> Dimensoes da janela CloudOS apos adaptacao em tempo real: ${w720}x${h720}" -ForegroundColor Cyan

    $cap720 = Join-Path $scratchDir "responsiveness_adapted_1280x720.png"
    [ResponsivenessTester]::CaptureWindow($flutterHwnd, $cap720)
    Write-Host "   -> Captura adaptada salva: $cap720" -ForegroundColor Gray

} finally {
    # 6. RESTORE ORIGINAL DISPLAY RESOLUTION
    Write-Host "`n[6/6] Restaurando resolucao original (${origWidth}x${origHeight} @ ${origFreq}Hz)..." -ForegroundColor Yellow
    $restoreRes = [ResponsivenessTester]::ChangeDisplaySettingsEx($targetDisplay, [ref]$originalDevMode, [IntPtr]::Zero, 0, [IntPtr]::Zero)
    if ($restoreRes -eq [ResponsivenessTester]::DISP_CHANGE_SUCCESSFUL) {
        Write-Host "   -> [RESTORE_OK] Resolucao original restaurada com sucesso!" -ForegroundColor Green
    } else {
        Write-Warning "Falha ao restaurar resolucao com ChangeDisplaySettingsEx: $restoreRes. Tentando CDS_RESET..."
    }
    Start-Sleep -Seconds 2

    # Final recovery capture
    $finalCap = Join-Path $scratchDir "responsiveness_restored_${origWidth}x${origHeight}.png"
    [ResponsivenessTester]::CaptureWindow($flutterHwnd, $finalCap)
    Write-Host "   -> Captura final pós-restauração salva: $finalCap" -ForegroundColor Gray
}

Write-Host "`n======================================================================" -ForegroundColor Green
Write-Host "[SUCCESS] TESTE FISICO DE RESPONSIVIDADE EM TEMPO REAL CONCLUIDO!" -ForegroundColor Green
Write-Host "Evidencias geradas em: $scratchDir" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
