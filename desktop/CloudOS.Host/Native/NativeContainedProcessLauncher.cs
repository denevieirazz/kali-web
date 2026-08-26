using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Serialization;
using Microsoft.Win32.SafeHandles;

namespace CloudOS.Host.Native;

/// <summary>
/// Creates a direct Windows process suspended and hidden, assigns it to a
/// kill-on-close Job, and exposes Resume only after NativeWindowManager has
/// installed the process capability. Shell, protocol and UWP activation never
/// enter this boundary.
/// </summary>
public static class NativeContainedProcessLauncher
{
    private const uint CreateSuspended = 0x00000004;
    private const uint CreateUnicodeEnvironment = 0x00000400;
    private const uint StartfUseShowWindow = 0x00000001;
    private const short SwHide = 0;
    private const uint JobObjectLimitKillOnJobClose = 0x00002000;
    private const int JobObjectExtendedLimitInformationClass = 9;

    public static NativeContainedProcessLease StartSuspended(NativeProcessLaunchSpec spec)
    {
        ArgumentNullException.ThrowIfNull(spec);

        using var environment = NativeEnvironmentBlock.Create();
        var startup = new StartupInfo
        {
            Size = Marshal.SizeOf<StartupInfo>(),
            Flags = StartfUseShowWindow,
            ShowWindow = SwHide
        };
        var commandLine = new StringBuilder(BuildCommandLine(spec.Executable, spec.Arguments));
        var processInfo = default(ProcessInformation);
        SafeJobHandle? job = null;
        SafeKernelHandle? processHandle = null;
        SafeKernelHandle? threadHandle = null;

        try
        {
            job = CreateKillOnCloseJob();
            if (!CreateProcess(
                spec.Executable,
                commandLine,
                IntPtr.Zero,
                IntPtr.Zero,
                false,
                CreateSuspended | CreateUnicodeEnvironment,
                environment.Pointer,
                spec.WorkingDirectory,
                ref startup,
                out processInfo))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateProcessW failed for the contained application.");
            }

            processHandle = new SafeKernelHandle(processInfo.Process, true);
            threadHandle = new SafeKernelHandle(processInfo.Thread, true);
            if (!AssignProcessToJobObject(job, processHandle))
            {
                var nativeError = Marshal.GetLastWin32Error();
                TerminateProcess(processHandle, 1);
                throw new Win32Exception(nativeError, "The process could not be assigned to the CloudOS containment Job.");
            }

            var process = Process.GetProcessById(checked((int)processInfo.ProcessId));
            var lease = new NativeContainedProcessLease(process, processHandle, threadHandle, job);
            processHandle = null;
            threadHandle = null;
            job = null;
            return lease;
        }
        catch
        {
            if (processHandle is not null && !processHandle.IsInvalid)
                TerminateProcess(processHandle, 1);
            threadHandle?.Dispose();
            processHandle?.Dispose();
            job?.Dispose();
            throw;
        }
    }

    internal static string BuildCommandLine(string executable, IReadOnlyList<string> arguments)
    {
        var command = new StringBuilder(QuoteArgument(executable));
        foreach (var argument in arguments)
        {
            command.Append(' ');
            command.Append(QuoteArgument(argument));
        }
        // CreateProcessW's 32,767-character limit includes the terminating NUL.
        if (command.Length > 32_766)
            throw new ArgumentException("The Windows command line exceeds the CreateProcessW limit.", nameof(arguments));
        return command.ToString();
    }

    internal static string QuoteArgument(string argument)
    {
        if (argument.IndexOf('\0') >= 0)
            throw new ArgumentException("A Windows process argument cannot contain NUL.", nameof(argument));
        if (argument.Length > 0 && argument.IndexOfAny([' ', '\t', '\r', '\n', '\v', '\f', '"']) < 0)
            return argument;

        var result = new StringBuilder(argument.Length + 2).Append('"');
        var backslashes = 0;
        foreach (var character in argument)
        {
            if (character == '\\')
            {
                backslashes++;
                continue;
            }
            if (character == '"')
            {
                result.Append('\\', backslashes * 2 + 1);
                result.Append('"');
                backslashes = 0;
                continue;
            }
            result.Append('\\', backslashes);
            backslashes = 0;
            result.Append(character);
        }
        result.Append('\\', backslashes * 2);
        return result.Append('"').ToString();
    }

    private static SafeJobHandle CreateKillOnCloseJob()
    {
        var job = CreateJobObject(IntPtr.Zero, null);
        if (job.IsInvalid)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateJobObjectW failed.");

        var information = new JobObjectExtendedLimitInformation
        {
            BasicLimitInformation = new JobObjectBasicLimitInformation
            {
                LimitFlags = JobObjectLimitKillOnJobClose
            }
        };
        var size = Marshal.SizeOf<JobObjectExtendedLimitInformation>();
        var pointer = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(information, pointer, false);
            if (!SetInformationJobObject(job, JobObjectExtendedLimitInformationClass, pointer, (uint)size))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "The Job kill-on-close policy could not be installed.");
        }
        catch
        {
            job.Dispose();
            throw;
        }
        finally
        {
            Marshal.FreeHGlobal(pointer);
        }
        return job;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo
    {
        internal int Size;
        internal string? Reserved;
        internal string? Desktop;
        internal string? Title;
        internal int X;
        internal int Y;
        internal int XSize;
        internal int YSize;
        internal int XCountChars;
        internal int YCountChars;
        internal int FillAttribute;
        internal uint Flags;
        internal short ShowWindow;
        internal short Reserved2;
        internal IntPtr ReservedPointer;
        internal IntPtr StandardInput;
        internal IntPtr StandardOutput;
        internal IntPtr StandardError;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInformation
    {
        internal IntPtr Process;
        internal IntPtr Thread;
        internal uint ProcessId;
        internal uint ThreadId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        internal ulong ReadOperationCount;
        internal ulong WriteOperationCount;
        internal ulong OtherOperationCount;
        internal ulong ReadTransferCount;
        internal ulong WriteTransferCount;
        internal ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectBasicLimitInformation
    {
        internal long PerProcessUserTimeLimit;
        internal long PerJobUserTimeLimit;
        internal uint LimitFlags;
        internal UIntPtr MinimumWorkingSetSize;
        internal UIntPtr MaximumWorkingSetSize;
        internal uint ActiveProcessLimit;
        internal UIntPtr Affinity;
        internal uint PriorityClass;
        internal uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectExtendedLimitInformation
    {
        internal JobObjectBasicLimitInformation BasicLimitInformation;
        internal IoCounters IoInfo;
        internal UIntPtr ProcessMemoryLimit;
        internal UIntPtr JobMemoryLimit;
        internal UIntPtr PeakProcessMemoryUsed;
        internal UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreateProcess(
        string applicationName,
        StringBuilder commandLine,
        IntPtr processAttributes,
        IntPtr threadAttributes,
        [MarshalAs(UnmanagedType.Bool)] bool inheritHandles,
        uint creationFlags,
        IntPtr environment,
        string currentDirectory,
        ref StartupInfo startupInfo,
        out ProcessInformation processInformation);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeJobHandle CreateJobObject(IntPtr securityAttributes, string? name);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetInformationJobObject(
        SafeJobHandle job,
        int informationClass,
        IntPtr information,
        uint informationLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AssignProcessToJobObject(SafeJobHandle job, SafeKernelHandle process);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TerminateProcess(SafeKernelHandle process, uint exitCode);
}

public sealed class NativeProcessLaunchSpec
{
    private const int MaxArgumentCount = 256;
    private const int MaxArgumentLength = 8_192;

    private NativeProcessLaunchSpec(string executable, IReadOnlyList<string> arguments, string workingDirectory)
    {
        Executable = executable;
        Arguments = arguments;
        WorkingDirectory = workingDirectory;
    }

    public string Executable { get; }
    public IReadOnlyList<string> Arguments { get; }
    public string WorkingDirectory { get; }

    public static NativeProcessLaunchSpec Create(
        string? executable,
        IEnumerable<string?>? arguments,
        string? workingDirectory)
    {
        var normalizedExecutable = NormalizeLocalPath(executable, mustExistAsFile: true, "executable");
        if (!string.Equals(Path.GetExtension(normalizedExecutable), ".exe", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("The contained executable must be a Windows .exe file.", nameof(executable));
        if (NativeLaunchContainmentPolicy.IsSharedBroker(Path.GetFileNameWithoutExtension(normalizedExecutable)))
            throw new ArgumentException("Shared Windows brokers cannot be used as contained launch targets.", nameof(executable));

        var normalizedArguments = (arguments ?? Array.Empty<string?>()).ToArray();
        if (normalizedArguments.Length > MaxArgumentCount)
            throw new ArgumentException("The contained process has too many arguments.", nameof(arguments));
        var safeArguments = new List<string>(normalizedArguments.Length);
        foreach (var argument in normalizedArguments)
        {
            if (argument is null || argument.Length > MaxArgumentLength || argument.IndexOf('\0') >= 0)
                throw new ArgumentException("A contained process argument is invalid.", nameof(arguments));
            safeArguments.Add(argument);
        }

        var defaultDirectory = Path.GetDirectoryName(normalizedExecutable)
            ?? throw new ArgumentException("The executable directory is invalid.", nameof(executable));
        var normalizedDirectory = string.IsNullOrWhiteSpace(workingDirectory)
            ? defaultDirectory
            : NormalizeLocalPath(workingDirectory, mustExistAsFile: false, "workingDirectory");
        if (!Directory.Exists(normalizedDirectory))
            throw new ArgumentException("The contained process working directory does not exist.", nameof(workingDirectory));

        _ = NativeContainedProcessLauncher.BuildCommandLine(normalizedExecutable, safeArguments);
        return new NativeProcessLaunchSpec(normalizedExecutable, safeArguments.AsReadOnly(), normalizedDirectory);
    }

    private static string NormalizeLocalPath(string? candidate, bool mustExistAsFile, string parameter)
    {
        if (string.IsNullOrWhiteSpace(candidate) || candidate.IndexOf('\0') >= 0)
            throw new ArgumentException("A contained process path is required.", parameter);
        if (!Path.IsPathFullyQualified(candidate) || candidate.StartsWith("\\\\", StringComparison.Ordinal))
            throw new ArgumentException("Only fully-qualified local Windows paths are allowed.", parameter);

        var normalized = Path.GetFullPath(candidate);
        if (normalized.StartsWith("\\\\?\\", StringComparison.Ordinal)
            || normalized.StartsWith("\\\\.\\", StringComparison.Ordinal))
            throw new ArgumentException("Windows device paths are not allowed.", parameter);
        if (mustExistAsFile && !File.Exists(normalized))
            throw new ArgumentException("The contained executable does not exist.", parameter);
        return normalized;
    }
}

/// <summary>
/// Wire contract returned only by the host-authenticated backend launch route.
/// Arguments are an argv array by design: accepting an opaque command-line string
/// would require unsafe, lossy reparsing of shortcut quoting.
/// </summary>
public sealed class NativeProcessLaunchDescriptor
{
    [JsonPropertyName("executable")]
    public string? Executable { get; init; }

    [JsonPropertyName("arguments")]
    public string?[]? Arguments { get; init; }

    [JsonPropertyName("workingDirectory")]
    public string? WorkingDirectory { get; init; }

    public NativeProcessLaunchSpec Validate()
    {
        if (Arguments is null)
            throw new ArgumentException("The host launch descriptor must contain an argv array.", nameof(Arguments));
        if (string.IsNullOrWhiteSpace(WorkingDirectory))
            throw new ArgumentException("The host launch descriptor must contain a working directory.", nameof(WorkingDirectory));
        return NativeProcessLaunchSpec.Create(Executable, Arguments, WorkingDirectory);
    }
}

public sealed class NativeContainedProcessLease : IDisposable
{
    private const int JobObjectBasicProcessIdList = 3;
    private const int ErrorMoreData = 234;
    private const int MaxContainedProcesses = 256;
    private const int MaxProcessListStabilizationAttempts = 3;
    private static readonly int JobProcessListBufferSize = checked(8 + (IntPtr.Size * MaxContainedProcesses));

    private readonly SafeKernelHandle _nativeProcess;
    private readonly SafeJobHandle _job;
    private readonly object _jobQuerySync = new();
    private SafeKernelHandle? _primaryThread;
    private IntPtr _jobProcessListBuffer;
    private int _jobProcessListBufferAllocationCount;
    private bool _disposed;

    internal NativeContainedProcessLease(
        Process process,
        SafeKernelHandle nativeProcess,
        SafeKernelHandle primaryThread,
        SafeJobHandle job)
    {
        Process = process;
        _nativeProcess = nativeProcess;
        _primaryThread = primaryThread;
        _job = job;
    }

    public Process Process { get; }
    public int ProcessId => Process.Id;
    public bool IsResumed { get; private set; }

    internal int JobProcessListBufferAllocationCount
    {
        get
        {
            lock (_jobQuerySync) return _jobProcessListBufferAllocationCount;
        }
    }

    /// <summary>
    /// Returns every process currently assigned to the containment Job, including
    /// descendants. The bounded query fails closed if a launch fans out beyond the
    /// host's capability budget. The maximum-size native buffer is allocated lazily
    /// once per lease and reused by correlation and termination polling.
    /// </summary>
    public IReadOnlyList<int> GetMemberProcessIds()
    {
        lock (_jobQuerySync)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            var pointer = GetOrCreateJobProcessListBuffer();

            for (var attempt = 0; attempt < MaxProcessListStabilizationAttempts; attempt++)
            {
                if (!QueryInformationJobObject(
                    _job,
                    JobObjectBasicProcessIdList,
                    pointer,
                    (uint)JobProcessListBufferSize,
                    out _))
                {
                    var nativeError = Marshal.GetLastWin32Error();
                    if (nativeError == ErrorMoreData)
                    {
                        var assigned = Marshal.ReadInt32(pointer, 0);
                        if (assigned > MaxContainedProcesses)
                            throw new InvalidOperationException("The contained Job exceeded the process capability budget.");
                        throw new InvalidOperationException("The contained Job process list did not fit the bounded query buffer.");
                    }
                    throw new Win32Exception(nativeError, "QueryInformationJobObject failed.");
                }

                var assignedProcesses = Marshal.ReadInt32(pointer, 0);
                var listedProcesses = Marshal.ReadInt32(pointer, 4);
                if (assignedProcesses < 0 || assignedProcesses > MaxContainedProcesses
                    || listedProcesses < 0 || listedProcesses > assignedProcesses
                    || listedProcesses > MaxContainedProcesses)
                {
                    throw new InvalidOperationException("The contained Job returned an invalid process list.");
                }

                // Windows documents a short list as a signal that the caller needs a larger
                // buffer. Ours already fits the entire CloudOS capability budget, so retry the
                // same buffer briefly to tolerate a process joining/exiting during the query.
                if (listedProcesses != assignedProcesses)
                {
                    if (attempt + 1 < MaxProcessListStabilizationAttempts) continue;
                    throw new InvalidOperationException("The contained Job process list remained incomplete.");
                }

                var processIds = new List<int>(listedProcesses);
                for (var index = 0; index < listedProcesses; index++)
                {
                    var rawProcessId = Marshal.ReadIntPtr(pointer, 8 + (index * IntPtr.Size)).ToInt64();
                    if (rawProcessId is <= 0 or > int.MaxValue)
                        throw new InvalidOperationException("The contained Job returned an invalid process identifier.");
                    processIds.Add((int)rawProcessId);
                }
                return processIds.AsReadOnly();
            }

            throw new InvalidOperationException("The contained Job process list could not be stabilized.");
        }
    }

    private IntPtr GetOrCreateJobProcessListBuffer()
    {
        if (_jobProcessListBuffer != IntPtr.Zero) return _jobProcessListBuffer;
        _jobProcessListBuffer = Marshal.AllocHGlobal(JobProcessListBufferSize);
        _jobProcessListBufferAllocationCount++;
        return _jobProcessListBuffer;
    }

    public void Resume()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (IsResumed) return;
        var thread = _primaryThread ?? throw new InvalidOperationException("The primary process thread is unavailable.");
        if (ResumeThread(thread) == uint.MaxValue)
        {
            var error = new Win32Exception(Marshal.GetLastWin32Error(), "ResumeThread failed for the contained process.");
            TryTerminate(3_000, out _);
            throw error;
        }
        IsResumed = true;
        thread.Dispose();
        _primaryThread = null;
    }

    public bool TryTerminate(int timeoutMilliseconds, out string? error)
    {
        if (timeoutMilliseconds < 0)
            throw new ArgumentOutOfRangeException(nameof(timeoutMilliseconds));
        if (_disposed)
        {
            error = null;
            return true;
        }

        try
        {
            if (!TerminateJobObject(_job, 1))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "TerminateJobObject failed.");

            var deadline = Environment.TickCount64 + timeoutMilliseconds;
            while (GetMemberProcessIds().Count > 0)
            {
                if (Environment.TickCount64 >= deadline)
                    throw new TimeoutException("The contained Job did not terminate before the deadline.");
                Thread.Sleep(20);
            }
            error = null;
            return true;
        }
        catch (Exception terminationError) when (terminationError is InvalidOperationException
            or Win32Exception or NotSupportedException or TimeoutException)
        {
            error = terminationError.Message;
            return false;
        }
    }

    public void Dispose()
    {
        lock (_jobQuerySync)
        {
            if (_disposed) return;

            // Keep the reusable query buffer alive until Job termination is observed. Monitor
            // locks are re-entrant, so TryTerminate can safely call GetMemberProcessIds here.
            TryTerminate(3_000, out _);
            _disposed = true;

            var queryBuffer = _jobProcessListBuffer;
            _jobProcessListBuffer = IntPtr.Zero;
            if (queryBuffer != IntPtr.Zero) Marshal.FreeHGlobal(queryBuffer);

            _primaryThread?.Dispose();
            _nativeProcess.Dispose();
            _job.Dispose(); // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE is the final fail-safe.
            Process.Dispose();
        }
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint ResumeThread(SafeKernelHandle thread);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TerminateJobObject(SafeJobHandle job, uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryInformationJobObject(
        SafeJobHandle job,
        int informationClass,
        IntPtr information,
        uint informationLength,
        out uint returnLength);
}

/// <summary>
/// Synchronizes every current Job member into the HWND capability table. A wrapper,
/// updater or helper process therefore cannot escape merely because the root PID did
/// not create the application's window.
/// </summary>
public static class NativeContainedJobTracker
{
    public static IReadOnlyList<int> Synchronize(
        NativeContainedProcessLease lease,
        NativeWindowManager windows)
    {
        ArgumentNullException.ThrowIfNull(lease);
        ArgumentNullException.ThrowIfNull(windows);

        var processIds = lease.GetMemberProcessIds();
        foreach (var processId in processIds)
        {
            if (windows.IsTrackedProcess(processId)) continue;
            using var process = Process.GetProcessById(processId);
            if (NativeLaunchContainmentPolicy.IsSharedBroker(process.ProcessName))
                throw new InvalidOperationException("A shared Windows broker entered the contained Job.");
            windows.TrackLaunchedProcess(process);
        }
        return processIds;
    }
}

internal sealed class SafeKernelHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    internal SafeKernelHandle(IntPtr handle, bool ownsHandle) : base(ownsHandle) => SetHandle(handle);

    protected override bool ReleaseHandle() => CloseHandle(handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);
}

internal sealed class SafeJobHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    private SafeJobHandle() : base(true) { }

    protected override bool ReleaseHandle() => CloseHandle(handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);
}

internal sealed class NativeEnvironmentBlock : IDisposable
{
    private static readonly string[] SecretMarkers =
    [
        "API_KEY", "AUTH", "CLOUDOS_", "CODEX_", "CREDENTIAL", "PASSWORD",
        "PRIVATE_KEY", "SECRET", "SUPERVISOR", "TOKEN"
    ];

    private NativeEnvironmentBlock(IntPtr pointer) => Pointer = pointer;

    internal IntPtr Pointer { get; private set; }

    internal static NativeEnvironmentBlock Create()
    {
        var entries = Environment.GetEnvironmentVariables()
            .Cast<System.Collections.DictionaryEntry>()
            .Select(entry => new KeyValuePair<string, string>(Convert.ToString(entry.Key)!, Convert.ToString(entry.Value) ?? string.Empty))
            .Where(entry => !string.IsNullOrEmpty(entry.Key)
                && entry.Key.IndexOf('=') < 0
                && !SecretMarkers.Any(marker => entry.Key.Contains(marker, StringComparison.OrdinalIgnoreCase)))
            .OrderBy(entry => entry.Key, StringComparer.OrdinalIgnoreCase)
            .Select(entry => $"{entry.Key}={entry.Value.Replace("\0", string.Empty, StringComparison.Ordinal)}")
            .ToArray();
        var serialized = string.Join('\0', entries) + "\0\0";
        return new NativeEnvironmentBlock(Marshal.StringToHGlobalUni(serialized));
    }

    public void Dispose()
    {
        var pointer = Pointer;
        Pointer = IntPtr.Zero;
        if (pointer != IntPtr.Zero) Marshal.FreeHGlobal(pointer);
    }
}
