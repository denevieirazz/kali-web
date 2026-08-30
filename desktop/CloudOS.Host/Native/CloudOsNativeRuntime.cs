using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace CloudOS.Host.Native;

internal enum CloudOsNativeRuntimePreference
{
    Auto,
    Managed,
    Cpp
}

/// <summary>
/// Thin C ABI boundary for the C++ Windows runtime. High-level containment policy and launch
/// capability validation remain in the Host; Win32 process/Job/HWND mutations progressively
/// live in CloudOS.NativeRuntime.dll.
/// </summary>
internal static class CloudOsNativeRuntime
{
    internal const uint ExpectedAbi = 5;
    private const string LibraryName = "CloudOS.NativeRuntime.dll";
    private const int MaxContainedProcesses = 256;

    internal static CloudOsNativeRuntimePreference Preference
    {
        get
        {
            var requested = Environment.GetEnvironmentVariable("CLOUDOS_NATIVE_RUNTIME")?.Trim();
            if (string.Equals(requested, "managed", StringComparison.OrdinalIgnoreCase))
                return CloudOsNativeRuntimePreference.Managed;
            if (string.Equals(requested, "cpp", StringComparison.OrdinalIgnoreCase))
                return CloudOsNativeRuntimePreference.Cpp;
            return CloudOsNativeRuntimePreference.Auto;
        }
    }

    internal static bool IsAvailable
    {
        get
        {
            if (!OperatingSystem.IsWindows()) return false;
            try
            {
                return NativeRuntimeAbi() == ExpectedAbi;
            }
            catch (Exception error) when (IsLoaderFailure(error))
            {
                return false;
            }
        }
    }

    internal static bool CanUseWindowOperations =>
        Preference != CloudOsNativeRuntimePreference.Managed && IsAvailable;

    internal static bool TryStartSuspended(
        NativeProcessLaunchSpec spec,
        out NativeContainedProcessLease? lease)
    {
        ArgumentNullException.ThrowIfNull(spec);
        lease = null;

        if (Preference == CloudOsNativeRuntimePreference.Managed) return false;
        if (!OperatingSystem.IsWindows())
        {
            if (Preference == CloudOsNativeRuntimePreference.Cpp)
                throw new PlatformNotSupportedException("The CloudOS C++ runtime requires Windows.");
            return false;
        }

        uint abi;
        try
        {
            abi = NativeRuntimeAbi();
        }
        catch (Exception error) when (IsLoaderFailure(error))
        {
            if (Preference == CloudOsNativeRuntimePreference.Cpp)
                throw new InvalidOperationException(
                    "CLOUDOS_NATIVE_RUNTIME=cpp was requested, but CloudOS.NativeRuntime.dll could not be loaded.",
                    error);
            return false;
        }

        if (abi != ExpectedAbi)
        {
            if (Preference == CloudOsNativeRuntimePreference.Cpp)
                throw new InvalidOperationException(
                    $"CloudOS.NativeRuntime ABI mismatch. Expected {ExpectedAbi}, received {abi}.");
            return false;
        }

        using var environment = NativeEnvironmentBlock.Create();
        var commandLine = NativeContainedProcessLauncher.BuildCommandLine(spec.Executable, spec.Arguments);
        if (!NativeLaunchSuspended(
            spec.Executable,
            commandLine,
            environment.Pointer,
            spec.WorkingDirectory,
            out var rawLease,
            out var processId))
        {
            throw NativeFailure("CloudOS.NativeRuntime failed to create the contained process.");
        }

        var safeLease = new SafeCloudOsNativeLeaseHandle(rawLease, ownsHandle: true);
        try
        {
            if (processId is 0 or > int.MaxValue)
                throw new InvalidOperationException("CloudOS.NativeRuntime returned an invalid root process identifier.");
            var process = Process.GetProcessById((int)processId);
            lease = new NativeContainedProcessLease(process, safeLease);
            safeLease = null!;
            return true;
        }
        finally
        {
            safeLease?.Dispose();
        }
    }

    internal static IReadOnlyList<int> GetMemberProcessIds(SafeCloudOsNativeLeaseHandle lease)
    {
        ArgumentNullException.ThrowIfNull(lease);
        var ids = new uint[MaxContainedProcesses];
        if (!NativeQueryMembers(lease, ids, (uint)ids.Length, out var count))
            throw NativeFailure("CloudOS.NativeRuntime failed to query the containment Job.");
        if (count > ids.Length)
            throw new InvalidOperationException("CloudOS.NativeRuntime exceeded the process capability budget.");

        var result = new List<int>((int)count);
        for (var index = 0; index < count; index++)
        {
            var processId = ids[index];
            if (processId is 0 or > int.MaxValue)
                throw new InvalidOperationException("CloudOS.NativeRuntime returned an invalid Job process identifier.");
            result.Add((int)processId);
        }
        return result.AsReadOnly();
    }

    internal static void Resume(SafeCloudOsNativeLeaseHandle lease)
    {
        ArgumentNullException.ThrowIfNull(lease);
        if (!NativeResume(lease))
            throw NativeFailure("CloudOS.NativeRuntime failed to resume the contained process.");
    }

    internal static bool TryTerminate(
        SafeCloudOsNativeLeaseHandle lease,
        int timeoutMilliseconds,
        out string? error)
    {
        ArgumentNullException.ThrowIfNull(lease);
        if (timeoutMilliseconds < 0)
            throw new ArgumentOutOfRangeException(nameof(timeoutMilliseconds));
        if (NativeTerminate(lease, checked((uint)timeoutMilliseconds)))
        {
            error = null;
            return true;
        }

        error = NativeFailure("CloudOS.NativeRuntime failed to terminate the containment Job.").Message;
        return false;
    }

    internal static bool TryAttachWindow(
        IntPtr window,
        IntPtr owner,
        NativeWindowBounds bounds,
        bool visible,
        out long appliedStyle,
        out long appliedExtendedStyle,
        out string? error)
    {
        appliedStyle = 0;
        appliedExtendedStyle = 0;
        if (!CanUseWindowOperations)
        {
            error = "The C++ HWND runtime is unavailable.";
            return false;
        }

        if (NativeWindowAttach(
            window,
            owner,
            bounds.X,
            bounds.Y,
            bounds.Width,
            bounds.Height,
            visible,
            out var style,
            out var extendedStyle))
        {
            appliedStyle = style.ToInt64();
            appliedExtendedStyle = extendedStyle.ToInt64();
            error = null;
            return true;
        }

        error = NativeFailure("CloudOS.NativeRuntime failed to attach the real Windows HWND.").Message;
        return false;
    }

    internal static bool TryLayoutWindow(
        IntPtr window,
        IntPtr owner,
        long expectedStyle,
        long expectedExtendedStyle,
        NativeWindowBounds bounds,
        bool visible,
        bool preserveMinimized,
        out string? error)
    {
        if (!CanUseWindowOperations)
        {
            error = "The C++ HWND runtime is unavailable.";
            return false;
        }

        if (NativeWindowLayout(
            window,
            owner,
            new IntPtr(expectedStyle),
            new IntPtr(expectedExtendedStyle),
            bounds.X,
            bounds.Y,
            bounds.Width,
            bounds.Height,
            visible,
            preserveMinimized))
        {
            error = null;
            return true;
        }

        error = NativeFailure("CloudOS.NativeRuntime failed to lay out the real Windows HWND.").Message;
        return false;
    }

    internal static bool TryFocusWindow(
        IntPtr window,
        IntPtr owner,
        long expectedStyle,
        long expectedExtendedStyle,
        NativeWindowBounds bounds,
        int restoreTimeoutMilliseconds,
        out string? error)
    {
        if (!CanUseWindowOperations)
        {
            error = "The C++ HWND runtime is unavailable.";
            return false;
        }

        if (NativeWindowFocus(
            window,
            owner,
            new IntPtr(expectedStyle),
            new IntPtr(expectedExtendedStyle),
            bounds.X,
            bounds.Y,
            bounds.Width,
            bounds.Height,
            checked((uint)restoreTimeoutMilliseconds)))
        {
            error = null;
            return true;
        }

        error = NativeFailure("CloudOS.NativeRuntime failed to focus the real Windows HWND.").Message;
        return false;
    }

    internal static void Release(IntPtr lease)
    {
        if (lease == IntPtr.Zero) return;
        NativeRelease(lease);
    }

    private static Win32Exception NativeFailure(string message)
    {
        var nativeError = Marshal.GetLastWin32Error();
        var systemMessage = new Win32Exception(nativeError).Message;
        return new Win32Exception(nativeError, $"{message} Win32 error {nativeError}: {systemMessage}");
    }

    private static bool IsLoaderFailure(Exception error) =>
        error is DllNotFoundException or EntryPointNotFoundException or BadImageFormatException;

    [DllImport(LibraryName, EntryPoint = "cloudos_native_runtime_abi", ExactSpelling = true, CallingConvention = CallingConvention.Winapi)]
    private static extern uint NativeRuntimeAbi();

    [DllImport(LibraryName, EntryPoint = "cloudos_native_launch_suspended", ExactSpelling = true,
        CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool NativeLaunchSuspended(
        string executable,
        string commandLine,
        IntPtr environmentBlock,
        string workingDirectory,
        out IntPtr lease,
        out uint processId);

    [DllImport(LibraryName, EntryPoint = "cloudos_native_resume", ExactSpelling = true,
        CallingConvention = CallingConvention.Winapi, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool NativeResume(SafeCloudOsNativeLeaseHandle lease);

    [DllImport(LibraryName, EntryPoint = "cloudos_native_query_members", ExactSpelling = true,
        CallingConvention = CallingConvention.Winapi, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool NativeQueryMembers(
        SafeCloudOsNativeLeaseHandle lease,
        [Out] uint[] processIds,
        uint capacity,
        out uint processCount);

    [DllImport(LibraryName, EntryPoint = "cloudos_native_terminate", ExactSpelling = true,
        CallingConvention = CallingConvention.Winapi, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool NativeTerminate(
        SafeCloudOsNativeLeaseHandle lease,
        uint timeoutMilliseconds);

    [DllImport(LibraryName, EntryPoint = "cloudos_native_release", ExactSpelling = true,
        CallingConvention = CallingConvention.Winapi)]
    private static extern void NativeRelease(IntPtr lease);

    [DllImport(LibraryName, EntryPoint = "cloudos_native_window_attach", ExactSpelling = true,
        CallingConvention = CallingConvention.Winapi, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool NativeWindowAttach(
        IntPtr window,
        IntPtr owner,
        int x,
        int y,
        int width,
        int height,
        [MarshalAs(UnmanagedType.Bool)] bool visible,
        out IntPtr appliedStyle,
        out IntPtr appliedExtendedStyle);

    [DllImport(LibraryName, EntryPoint = "cloudos_native_window_layout", ExactSpelling = true,
        CallingConvention = CallingConvention.Winapi, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool NativeWindowLayout(
        IntPtr window,
        IntPtr owner,
        IntPtr expectedStyle,
        IntPtr expectedExtendedStyle,
        int x,
        int y,
        int width,
        int height,
        [MarshalAs(UnmanagedType.Bool)] bool visible,
        [MarshalAs(UnmanagedType.Bool)] bool preserveMinimized);

    [DllImport(LibraryName, EntryPoint = "cloudos_native_window_focus", ExactSpelling = true,
        CallingConvention = CallingConvention.Winapi, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool NativeWindowFocus(
        IntPtr window,
        IntPtr owner,
        IntPtr expectedStyle,
        IntPtr expectedExtendedStyle,
        int x,
        int y,
        int width,
        int height,
        uint restoreTimeoutMilliseconds);
}

internal sealed class SafeCloudOsNativeLeaseHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    internal SafeCloudOsNativeLeaseHandle(IntPtr handle, bool ownsHandle) : base(ownsHandle) => SetHandle(handle);

    protected override bool ReleaseHandle()
    {
        try
        {
            CloudOsNativeRuntime.Release(handle);
            return true;
        }
        catch
        {
            return false;
        }
    }
}
