[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root,
    [string]$NativeRoot,
    [ValidateRange(5, 120)]
    [int]$StartupTimeoutSeconds = 30,
    [switch]$AllowDevelopmentLayout,
    [switch]$Startup
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$t0 = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

$currentSession = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
$startupMutexName = "Local\CloudOS_Startup_Session_$currentSession"
$createdNew = $false
$startupMutex = New-Object System.Threading.Mutex($true, $startupMutexName, [ref]$createdNew)
if (-not $createdNew) {
    Write-Host "[CloudOS] Outra inicializacao ja esta em andamento nesta sessao. Encerrando duplicata." -ForegroundColor Yellow
    exit 0
}

if (-not $Root) {
    $Root = $PSScriptRoot
}

$presentationRoot = (Resolve-Path -LiteralPath $Root).Path
$nativeRootPath = if ($NativeRoot) {
    (Resolve-Path -LiteralPath $NativeRoot).Path
}
else {
    $presentationRoot
}

$verifyScript = Join-Path $presentationRoot 'verify-cloudos-v21-runtime.ps1'
if (-not (Test-Path -LiteralPath $verifyScript -PathType Leaf)) {
    $repoVerifier = Join-Path $PSScriptRoot 'verify-cloudos-v21-runtime.ps1'
    if (-not (Test-Path -LiteralPath $repoVerifier -PathType Leaf)) {
        throw 'Verificador do runtime integrado V21 nao foi encontrado.'
    }
    $verifyScript = $repoVerifier
}

$verifyArgs = @{
    Root = $presentationRoot
    NativeRoot = $nativeRootPath
}
if ($AllowDevelopmentLayout) { $verifyArgs.AllowDevelopmentLayout = $true }
& $verifyScript @verifyArgs

if (-not ('CloudOSV21NativeWindowProbe' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CloudOSV21NativeWindowProbe {
    public delegate bool EnumDesktopWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string className, string windowName);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr OpenDesktop(string lpszDesktop, uint dwFlags, bool fInherit, uint dwDesiredAccess);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool EnumDesktopWindows(IntPtr hDesktop, EnumDesktopWindowsProc lpfn, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool CloseDesktop(IntPtr hDesktop);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcess(
        string lpApplicationName, string lpCommandLine,
        IntPtr lpProcessAttributes, IntPtr lpThreadAttributes,
        bool bInheritHandles, uint dwCreationFlags,
        IntPtr lpEnvironment, string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    public static IntPtr FindWindowForPidOnDefault(uint targetPid) {
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

    public static int LaunchProcess(string exePath, string workingDir, string desktop = @"winsta0\default") {
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(si);
        si.lpDesktop = desktop;
        si.dwFlags = 1; // STARTF_USESHOWWINDOW
        si.wShowWindow = 1; // SW_SHOWNORMAL
        PROCESS_INFORMATION pi;
        if (!CreateProcess(exePath, null, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, workingDir, ref si, out pi)) {
            return 0;
        }
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        return pi.dwProcessId;
    }
}
'@
}

function Test-SamePath([string]$Left, [string]$Right) {
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    try {
        $a = [IO.Path]::GetFullPath($Left).TrimEnd('\')
        $b = [IO.Path]::GetFullPath($Right).TrimEnd('\')
        return [string]::Equals($a, $b, [StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}

function Get-NativeAuthorityEndpoint {
    $hwndMessage = [IntPtr]::new(-3)
    $window = [CloudOSV21NativeWindowProbe]::FindWindowEx(
        $hwndMessage,
        [IntPtr]::Zero,
        'CloudOS.NativeShell.Activation.v21',
        $null)
    if ($window -eq [IntPtr]::Zero) { return $null }

    [uint32]$processId = 0
    [void][CloudOSV21NativeWindowProbe]::GetWindowThreadProcessId($window, [ref]$processId)
    if ($processId -eq 0) { return $null }
    try {
        $process = Get-Process -Id $processId -ErrorAction Stop
        return [pscustomobject]@{
            Window = $window
            ProcessId = [int]$processId
            Path = $process.Path
        }
    }
    catch { return $null }
}

function Assert-AuthorityPath($Endpoint, [string]$ExpectedPath) {
    if ($null -eq $Endpoint) { return }
    if (-not (Test-SamePath $Endpoint.Path $ExpectedPath)) {
        throw "Outra autoridade NativeShell V21 ja esta ativa: $($Endpoint.Path). Feche-a antes de iniciar este bundle: $ExpectedPath"
    }
}

function Test-Broker {
    param([string]$Probe)
    try {
        $p = Start-Process -FilePath $Probe -ArgumentList 'ping' -NoNewWindow -Wait -PassThru
        return $p.ExitCode -eq 0
    }
    catch {
        return $false
    }
}

$nativeShell = Join-Path $nativeRootPath 'CloudOS.exe'
$supervisor = Join-Path $nativeRootPath 'CloudOS.Supervisor.exe'
$broker = Join-Path $nativeRootPath 'CloudOS.SystemBroker.exe'
$probe = Join-Path $nativeRootPath 'CloudOS.BrokerProbe.exe'
$flutter = Join-Path $presentationRoot 'cloudos_flutter_shell.exe'

Write-Host '[CloudOS V21] Modo integrado: NativeShell C++/Win32 = autoridade; Flutter = apresentacao companion.' -ForegroundColor Cyan

$endpoint = Get-NativeAuthorityEndpoint
Assert-AuthorityPath $endpoint $nativeShell
if ($null -eq $endpoint) {
    Write-Host '[CloudOS V21] Iniciando Shell Supervisor V11...' -ForegroundColor Cyan
    Start-Process -FilePath $supervisor -WorkingDirectory $nativeRootPath | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 250
        $endpoint = Get-NativeAuthorityEndpoint
        if ($null -ne $endpoint) {
            Assert-AuthorityPath $endpoint $nativeShell
            break
        }
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($null -eq $endpoint) {
        throw "NativeShell V21 nao publicou o endpoint de ativacao em $StartupTimeoutSeconds segundos."
    }
}
Write-Host "[CloudOS V21] NativeShell authority pronta (PID $($endpoint.ProcessId))." -ForegroundColor Green
$t1 = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

# Preserva NativeShell C++ como autoridade headless ocultando suas superficies visuais legadas
# para que a apresentacao Flutter V21 seja a única casca visual no desktop.
$nativeTaskbar = [CloudOSV21NativeWindowProbe]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, 'CloudOS.NativeShell.Taskbar.v3', $null)
if ($nativeTaskbar -ne [IntPtr]::Zero) {
    [void][CloudOSV21NativeWindowProbe]::ShowWindow($nativeTaskbar, 0)
}
$nativeDesktop = [CloudOSV21NativeWindowProbe]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, 'CloudOS.NativeShell.Desktop', $null)
if ($nativeDesktop -ne [IntPtr]::Zero) {
    [void][CloudOSV21NativeWindowProbe]::ShowWindow($nativeDesktop, 0)
}

$brokerProcesses = @(Get-Process -Name 'CloudOS.SystemBroker' -ErrorAction SilentlyContinue)
foreach ($process in $brokerProcesses) {
    if ($process.Path -and -not (Test-SamePath $process.Path $broker)) {
        throw "Outro System Broker V21 ja esta ativo: $($process.Path). Feche-o antes de iniciar este bundle."
    }
}

if (-not (Test-Broker -Probe $probe)) {
    Write-Host '[CloudOS V21] Iniciando System Broker V21...' -ForegroundColor Cyan
    Start-Process -FilePath $broker -WorkingDirectory $nativeRootPath | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Min($StartupTimeoutSeconds, 20))
    $brokerReady = $false
    do {
        Start-Sleep -Milliseconds 250
        if (Test-Broker -Probe $probe) {
            $brokerReady = $true
            break
        }
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $brokerReady) {
        throw 'System Broker V21 nao respondeu ao health.ping dentro do timeout.'
    }
}
Write-Host '[CloudOS V21] System Broker V21 pronto.' -ForegroundColor Green
$t2 = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

$existingFlutter = @(Get-Process -Name 'cloudos_flutter_shell' -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and (Test-SamePath $_.Path $flutter)
})

$flutterHwnd = [IntPtr]::Zero
if ($existingFlutter.Count -gt 0) {
    foreach ($proc in $existingFlutter) {
        $hwnd = [CloudOSV21NativeWindowProbe]::FindWindowForPidOnDefault($proc.Id)
        if ($hwnd -ne [IntPtr]::Zero) {
            $flutterHwnd = $hwnd
            break
        }
    }
    if ($flutterHwnd -ne [IntPtr]::Zero) {
        Write-Host "[CloudOS V21] Flutter presentation ativa (PID $($existingFlutter[0].Id)). Focando janela..." -ForegroundColor Green
        [void][CloudOSV21NativeWindowProbe]::ShowWindow($flutterHwnd, 3) # SW_MAXIMIZE
        [void][CloudOSV21NativeWindowProbe]::BringWindowToTop($flutterHwnd)
        [void][CloudOSV21NativeWindowProbe]::SetForegroundWindow($flutterHwnd)
        if ($startupMutex) {
            $startupMutex.ReleaseMutex()
            $startupMutex.Dispose()
            $startupMutex = $null
        }
        exit 0
    }
    else {
        Write-Host "[CloudOS V21] Instancia Flutter sem janela interativa detectada. Reiniciando..." -ForegroundColor Yellow
        $existingFlutter | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '[CloudOS V21] Iniciando Flutter presentation...' -ForegroundColor Cyan
$flutterPid = [CloudOSV21NativeWindowProbe]::LaunchProcess($flutter, $presentationRoot)
if ($flutterPid -eq 0) {
    $flutterProc = Start-Process -FilePath $flutter -WorkingDirectory $presentationRoot -PassThru
    $flutterPid = $flutterProc.Id
}

$deadline = [DateTime]::UtcNow.AddSeconds(10)
do {
    Start-Sleep -Milliseconds 250
    $flutterHwnd = [CloudOSV21NativeWindowProbe]::FindWindowForPidOnDefault($flutterPid)
    if ($flutterHwnd -ne [IntPtr]::Zero) {
        [void][CloudOSV21NativeWindowProbe]::ShowWindow($flutterHwnd, 3) # SW_MAXIMIZE
        [void][CloudOSV21NativeWindowProbe]::BringWindowToTop($flutterHwnd)
        [void][CloudOSV21NativeWindowProbe]::SetForegroundWindow($flutterHwnd)
        break
    }
} while ([DateTime]::UtcNow -lt $deadline)

$t3 = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$t4 = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

$cloudosDataDir = Join-Path $env:LOCALAPPDATA 'CloudOS'
if (-not (Test-Path -LiteralPath $cloudosDataDir)) {
    New-Item -ItemType Directory -Path $cloudosDataDir -Force | Out-Null
}

$metrics = [ordered]@{
    timestamp           = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    is_startup          = [bool]$Startup
    session_id          = $currentSession
    supervisor_ready_ms = [int]($t1 - $t0)
    broker_ready_ms     = [int]($t2 - $t1)
    flutter_window_ms   = [int]($t3 - $t2)
    total_startup_ms    = [int]($t4 - $t0)
    explorer_running    = ((Get-Process -Name 'explorer' -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
}
$metrics | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $cloudosDataDir 'startup-metrics.json') -Encoding UTF8

if ($Startup) {
    $status = [ordered]@{
        last_startup = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        last_result  = 'SUCCESS'
        mechanism    = 'HKCU Run Key (CloudOS)'
        total_ms     = [int]($t4 - $t0)
    }
    $status | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $cloudosDataDir 'startup-status.json') -Encoding UTF8
}

if ($startupMutex) {
    $startupMutex.ReleaseMutex()
    $startupMutex.Dispose()
    $startupMutex = $null
}

Write-Host '[CloudOS V21] Runtime integrado iniciado.' -ForegroundColor Green
