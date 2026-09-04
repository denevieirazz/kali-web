[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$BuildDirectory,
    [string]$Distribution = 'kali-linux',
    [switch]$RequireKali,
    [switch]$AllowTerminateDistribution,
    [int]$TimeoutSeconds = 12,
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($TimeoutSeconds -lt 3 -or $TimeoutSeconds -gt 60) {
    throw 'TimeoutSeconds must be between 3 and 60.'
}

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$build = if ($BuildDirectory) {
    (Resolve-Path -LiteralPath $BuildDirectory).Path
} else {
    Join-Path $rootPath 'desktop\CloudOS.NativeShell\bin\Release'
}
$runtime = Join-Path $build 'CloudOS.NativeRuntime.dll'
if (-not (Test-Path -LiteralPath $runtime -PathType Leaf)) {
    throw "CloudOS.NativeRuntime.dll missing: $runtime"
}

$wsl = (Get-Command wsl.exe -ErrorAction SilentlyContinue).Source
if (-not $wsl) {
    throw 'wsl.exe is not available on this Windows installation.'
}

$registered = @(
    & $wsl --list --quiet 2>$null |
        ForEach-Object { ([string]$_).Trim([char]0).Trim() } |
        Where-Object { $_ }
)
if ($LASTEXITCODE -ne 0) {
    throw "wsl.exe --list --quiet failed with exit code $LASTEXITCODE."
}

$requested = $Distribution.Trim()
if (-not $requested) {
    throw 'Distribution must be a registered distro name.'
}
$selected = $registered | Where-Object { $_ -ieq $requested } | Select-Object -First 1
if (-not $selected) {
    throw "Requested distro '$requested' is not registered. Registered: $($registered -join ', ')"
}
if ($RequireKali -and $selected -notmatch '(?i)kali') {
    throw "Release security qualification requires a real Kali distro; selected '$selected'."
}

if (-not $OutputPath) {
    $artifactDir = Join-Path $rootPath 'desktop\CloudOS.NativeShell\artifacts'
    New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
    $OutputPath = Join-Path $artifactDir 'terminal-wsl-physical-v22.json'
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

# Fixed native ABI harness. There is intentionally no user-supplied command
# parameter: the only launched program is wsl.exe for the selected registered
# distro and the only input sent is the deterministic qualification sequence.
$source = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public sealed class CloudOSTerminalNativeHarness : IDisposable
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryW(string path);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr module, string name);
    [DllImport("kernel32.dll")]
    private static extern bool FreeLibrary(IntPtr module);

    [UnmanagedFunctionPointer(CallingConvention.StdCall, CharSet = CharSet.Unicode)]
    private delegate bool CreateDelegate(
        string commandLine, string workingDirectory, short columns, short rows,
        out IntPtr terminal, out uint processId);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate bool WriteDelegate(
        IntPtr terminal, byte[] data, uint size, out uint written);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate bool ReadDelegate(
        IntPtr terminal, byte[] buffer, uint capacity, out uint read);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate bool ResizeDelegate(IntPtr terminal, short columns, short rows);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate bool GetExitDelegate(IntPtr terminal, out uint exitCode, out int exited);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate bool TerminateDelegate(IntPtr terminal, uint exitCode);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate void ReleaseDelegate(IntPtr terminal);

    private readonly IntPtr module;
    private readonly CreateDelegate create;
    private readonly WriteDelegate write;
    private readonly ReadDelegate read;
    private readonly ResizeDelegate resize;
    private readonly GetExitDelegate getExit;
    private readonly TerminateDelegate terminate;
    private readonly ReleaseDelegate release;
    private readonly object textLock = new object();
    private readonly StringBuilder text = new StringBuilder();
    private Thread reader;
    private volatile bool closing;
    private IntPtr terminal;

    public uint ProcessId { get; private set; }

    public CloudOSTerminalNativeHarness(string runtimePath)
    {
        module = LoadLibraryW(runtimePath);
        if (module == IntPtr.Zero) throw new InvalidOperationException("LoadLibraryW failed: " + Marshal.GetLastWin32Error());
        create = Resolve<CreateDelegate>("cloudos_native_terminal_create");
        write = Resolve<WriteDelegate>("cloudos_native_terminal_write");
        read = Resolve<ReadDelegate>("cloudos_native_terminal_read");
        resize = Resolve<ResizeDelegate>("cloudos_native_terminal_resize");
        getExit = Resolve<GetExitDelegate>("cloudos_native_terminal_get_exit_code");
        terminate = Resolve<TerminateDelegate>("cloudos_native_terminal_terminate");
        release = Resolve<ReleaseDelegate>("cloudos_native_terminal_release");
    }

    private T Resolve<T>(string name) where T : class
    {
        IntPtr address = GetProcAddress(module, name);
        if (address == IntPtr.Zero) throw new MissingMethodException(name);
        return Marshal.GetDelegateForFunctionPointer(address, typeof(T)) as T;
    }

    public void Start(string commandLine, short columns, short rows)
    {
        if (!create(commandLine, null, columns, rows, out terminal, out uint pid) || terminal == IntPtr.Zero)
            throw new InvalidOperationException("cloudos_native_terminal_create failed: " + Marshal.GetLastWin32Error());
        ProcessId = pid;
        reader = new Thread(ReadLoop) { IsBackground = true, Name = "CloudOS V22 terminal qualification reader" };
        reader.Start();
    }

    private void ReadLoop()
    {
        byte[] buffer = new byte[8192];
        while (!closing && terminal != IntPtr.Zero)
        {
            if (!read(terminal, buffer, (uint)buffer.Length, out uint count) || count == 0) break;
            string chunk = Encoding.UTF8.GetString(buffer, 0, checked((int)count));
            lock (textLock) text.Append(chunk);
        }
    }

    public bool Write(string value)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(value);
        return write(terminal, bytes, (uint)bytes.Length, out uint written) && written == bytes.Length;
    }

    public bool WriteControlC()
    {
        byte[] bytes = new byte[] { 0x03 };
        return write(terminal, bytes, 1, out uint written) && written == 1;
    }

    public bool Resize(short columns, short rows) => resize(terminal, columns, rows);

    public bool WaitContains(string marker, int timeoutMs)
    {
        DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        do
        {
            lock (textLock)
            {
                if (text.ToString().Contains(marker)) return true;
            }
            Thread.Sleep(40);
        } while (DateTime.UtcNow < deadline);
        return false;
    }

    public string Snapshot()
    {
        lock (textLock) return text.ToString();
    }

    public bool WaitExit(int timeoutMs, out uint exitCode)
    {
        DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        do
        {
            if (getExit(terminal, out exitCode, out int exited) && exited != 0) return true;
            Thread.Sleep(50);
        } while (DateTime.UtcNow < deadline);
        exitCode = 259;
        return false;
    }

    public void ForceTerminate(uint code)
    {
        if (terminal != IntPtr.Zero) terminate(terminal, code);
    }

    public void Dispose()
    {
        closing = true;
        if (terminal != IntPtr.Zero)
        {
            if (getExit(terminal, out uint ignored, out int exited) && exited == 0)
                terminate(terminal, 0xC1050022);
            release(terminal);
            terminal = IntPtr.Zero;
        }
        if (reader != null && reader.IsAlive) reader.Join(2000);
        if (module != IntPtr.Zero) FreeLibrary(module);
    }
}
'@

if (-not ('CloudOSTerminalNativeHarness' -as [type])) {
    Add-Type -TypeDefinition $source -Language CSharp
}

function Quote-WindowsArgument([string]$Value) {
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

$failures = [Collections.Generic.List[string]]::new()
$evidence = [ordered]@{
    distribution = $selected
    runtime_dll = $runtime
    ctrl_c = $false
    resize = $false
    stdout_streaming = $false
    graceful_exit = $false
    wsl_terminate_observed = $false
    terminal_process_cleanup = $false
}

$command = 'wsl.exe -d ' + (Quote-WindowsArgument $selected) + ' -- sh'
$terminal = [CloudOSTerminalNativeHarness]::new($runtime)
try {
    $terminal.Start($command, 80, 24)
    $evidence.process_id = [int64]$terminal.ProcessId

    if (-not $terminal.Write("printf '__CLOUDOS_TERM_READY__\\n'`n") -or
        -not $terminal.WaitContains('__CLOUDOS_TERM_READY__', $TimeoutSeconds * 1000)) {
        $failures.Add('stdout_stream_not_observed')
    } else {
        $evidence.stdout_streaming = $true
    }

    if (-not $terminal.Write("printf '__SIZE_A__:'; stty size`n") -or
        -not $terminal.WaitContains('__SIZE_A__:', $TimeoutSeconds * 1000)) {
        $failures.Add('initial_tty_size_not_observed')
    }

    if (-not $terminal.Resize(100, 40)) {
        $failures.Add('resize_api_failed')
    } else {
        Start-Sleep -Milliseconds 150
        if (-not $terminal.Write("printf '__SIZE_B__:'; stty size`n") -or
            -not $terminal.WaitContains('__SIZE_B__:', $TimeoutSeconds * 1000)) {
            $failures.Add('resized_tty_size_not_observed')
        } else {
            $snapshot = $terminal.Snapshot()
            if ($snapshot -match '__SIZE_B__:[^\r\n]*40\s+100') {
                $evidence.resize = $true
            } else {
                $failures.Add('resized_tty_dimensions_mismatch')
            }
        }
    }

    if (-not $terminal.Write("sleep 30`n")) {
        $failures.Add('ctrl_c_sleep_write_failed')
    } else {
        Start-Sleep -Milliseconds 300
        if (-not $terminal.WriteControlC()) {
            $failures.Add('ctrl_c_write_failed')
        } else {
            Start-Sleep -Milliseconds 150
            $ctrlCProbe = 'printf ''__CTRL_C__:%s\n'' "$?"' + "`n"
            [void]$terminal.Write($ctrlCProbe)
            if ($terminal.WaitContains('__CTRL_C__:130', $TimeoutSeconds * 1000)) {
                $evidence.ctrl_c = $true
            } else {
                $failures.Add('ctrl_c_exit_130_not_observed')
            }
        }
    }

    if (-not $terminal.Write("exit`n")) {
        $failures.Add('exit_write_failed')
    } else {
        [uint32]$exitCode = 259
        if ($terminal.WaitExit($TimeoutSeconds * 1000, [ref]$exitCode)) {
            $evidence.graceful_exit = $true
            $evidence.graceful_exit_code = [int64]$exitCode
        } else {
            $failures.Add('terminal_exit_timeout')
        }
    }
}
finally {
    $pid = [int]$terminal.ProcessId
    $terminal.Dispose()
    Start-Sleep -Milliseconds 300
    $evidence.terminal_process_cleanup = -not [bool](Get-Process -Id $pid -ErrorAction SilentlyContinue)
    if (-not $evidence.terminal_process_cleanup) {
        $failures.Add('terminal_windows_process_orphaned')
    }
}

if ($AllowTerminateDistribution) {
    $second = [CloudOSTerminalNativeHarness]::new($runtime)
    try {
        $second.Start($command, 80, 24)
        [void]$second.Write("printf '__TERMINATE_READY__\\n'; sleep 300`n")
        if (-not $second.WaitContains('__TERMINATE_READY__', $TimeoutSeconds * 1000)) {
            $failures.Add('terminate_scenario_not_ready')
        } else {
            & $wsl --terminate $selected 2>$null | Out-Null
            $terminateExit = $LASTEXITCODE
            $evidence.wsl_terminate_exit_code = $terminateExit
            [uint32]$secondExit = 259
            if ($terminateExit -eq 0 -and $second.WaitExit($TimeoutSeconds * 1000, [ref]$secondExit)) {
                $evidence.wsl_terminate_observed = $true
                $evidence.wsl_terminate_terminal_exit_code = [int64]$secondExit
            } else {
                $failures.Add('wsl_terminate_did_not_close_terminal')
            }
        }
    }
    finally {
        $second.Dispose()
    }
} else {
    $evidence.wsl_terminate_status = 'not_run_requires_AllowTerminateDistribution'
}

$report = [ordered]@{
    schema = 22
    test = 'CloudOS physical ConPTY/WSL terminal qualification'
    collected_utc = [DateTime]::UtcNow.ToString('o')
    verdict = if ($failures.Count -eq 0 -and ($evidence.wsl_terminate_observed -or -not $AllowTerminateDistribution)) { 'pass' } else { 'fail' }
    release_complete = ($failures.Count -eq 0 -and $AllowTerminateDistribution -and $evidence.wsl_terminate_observed)
    evidence = $evidence
    failures = $failures.ToArray()
    boundary = 'Physical Windows + registered distro required. Release-complete additionally requires -AllowTerminateDistribution; hosted CI must not claim this gate.'
}

$parent = [IO.Path]::GetDirectoryName($OutputPath)
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8

if ($failures.Count -gt 0) {
    Write-Error "FAIL: physical Terminal/WSL V22 qualification failed: $($failures -join ', '). Report: $OutputPath"
    exit 1
}

if (-not $AllowTerminateDistribution) {
    Write-Warning "PASS (partial): streaming/resize/Ctrl+C/exit passed, but release-complete WSL termination was not exercised. Report: $OutputPath"
    exit 0
}

Write-Host "PASS: physical Terminal/WSL V22 qualification passed, including distro termination. Report: $OutputPath"
