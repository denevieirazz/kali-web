[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$NativeRoot,
    [ValidateRange(5, 120)]
    [int]$StartupTimeoutSeconds = 30,
    [switch]$AllowDevelopmentLayout
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string className, string windowName);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
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
    & $Probe ping *> $null
    return $LASTEXITCODE -eq 0
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

$existingFlutter = @(Get-Process -Name 'cloudos_flutter_shell' -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and (Test-SamePath $_.Path $flutter)
})
if ($existingFlutter.Count -gt 0) {
    Write-Host "[CloudOS V21] Flutter presentation ja esta ativa (PID $($existingFlutter[0].Id))." -ForegroundColor Green
    exit 0
}

Write-Host '[CloudOS V21] Iniciando Flutter presentation...' -ForegroundColor Cyan
$flutterProc = Start-Process -FilePath $flutter -WorkingDirectory $presentationRoot -PassThru
Start-Sleep -Milliseconds 750
if ($flutterProc -and -not $flutterProc.HasExited) {
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        Start-Sleep -Milliseconds 200
        $flutterProc.Refresh()
        if ($flutterProc.MainWindowHandle -ne [IntPtr]::Zero) {
            [void][CloudOSV21NativeWindowProbe]::ShowWindow($flutterProc.MainWindowHandle, 3) # SW_MAXIMIZE
            [void][CloudOSV21NativeWindowProbe]::SetForegroundWindow($flutterProc.MainWindowHandle)
            break
        }
    } while ([DateTime]::UtcNow -lt $deadline)
}
Write-Host '[CloudOS V21] Runtime integrado iniciado.' -ForegroundColor Green
