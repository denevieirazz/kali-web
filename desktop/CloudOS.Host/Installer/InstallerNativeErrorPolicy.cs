using System.ComponentModel;

namespace CloudOS.Host.Installer;

public static class InstallerNativeErrorPolicy
{
    // Win32 ERROR_ELEVATION_REQUIRED. CloudOS must never answer this with ShellExecute
    // runas; the only admissible future path is the explicit privileged installer broker.
    public const int ErrorElevationRequired = 740;

    public static bool RequiresPrivilegedBroker(Exception error) =>
        error is Win32Exception win32
        && win32.NativeErrorCode == ErrorElevationRequired;
}
