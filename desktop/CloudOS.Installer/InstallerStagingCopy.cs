using System.ComponentModel;
using System.Runtime.InteropServices;

namespace CloudOS.Installer;

public static class InstallerStagingCopy
{
    private const uint CopyFileFailIfExists = 0x00000001;

    /// <summary>
    /// Uses the Win32 copy primitive because Windows documents that CopyFileEx preserves
    /// NTFS alternate data streams. This keeps Zone.Identifier / Mark-of-the-Web when it
    /// exists on a Browser download instead of silently laundering origin metadata while
    /// creating the immutable installer staging copy.
    /// </summary>
    public static void CopyPreservingStreams(string source, string destination)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(source);
        ArgumentException.ThrowIfNullOrWhiteSpace(destination);
        var canonicalSource = Path.GetFullPath(source);
        var canonicalDestination = Path.GetFullPath(destination);
        if (!File.Exists(canonicalSource))
            throw new FileNotFoundException("Installer source artifact does not exist.", canonicalSource);
        if (File.Exists(canonicalDestination))
            throw new IOException("Installer staging destination already exists.");

        var cancel = false;
        if (!CopyFileExW(
                canonicalSource,
                canonicalDestination,
                IntPtr.Zero,
                IntPtr.Zero,
                ref cancel,
                CopyFileFailIfExists))
        {
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "CopyFileExW failed while preserving installer origin metadata.");
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CopyFileExW(
        string existingFileName,
        string newFileName,
        IntPtr progressRoutine,
        IntPtr data,
        [MarshalAs(UnmanagedType.Bool)] ref bool cancel,
        uint copyFlags);
}
