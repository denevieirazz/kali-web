using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace CloudOS.Installer;

public static class InstallerArtifactInspector
{
    private static readonly Guid WinTrustActionGenericVerifyV2 = new(
        "00AAC56B-CD44-11D0-8CC2-00C04FC295EE");

    private const uint WtdUiNone = 2;
    private const uint WtdRevokeNone = 0;
    private const uint WtdChoiceFile = 1;
    private const uint WtdStateActionIgnore = 0;
    private const uint WtdCacheOnlyUrlRetrieval = 0x00000004;
    private const int TrustENoSignature = unchecked((int)0x800B0100);

    public static async Task<InstallerArtifactInspection> InspectAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var canonicalPath = Path.GetFullPath(path);
        var file = new FileInfo(canonicalPath);
        if (!file.Exists) throw new FileNotFoundException("Installer artifact does not exist.", canonicalPath);
        if (file.Length <= 0) throw new InvalidDataException("Installer artifact is empty.");

        var kind = DetectKind(canonicalPath);
        var sha256 = await ComputeSha256Async(canonicalPath, cancellationToken);
        var trust = VerifyAuthenticode(canonicalPath);
        var publisher = TryReadPublisher(canonicalPath);

        return new InstallerArtifactInspection(
            kind,
            sha256,
            file.Length,
            new DateTimeOffset(file.LastWriteTimeUtc, TimeSpan.Zero),
            trust.Status,
            publisher,
            trust.NativeStatus);
    }

    public static InstallerArtifactKind DetectKind(string path) =>
        Path.GetExtension(path).ToLowerInvariant() switch
        {
            ".exe" => InstallerArtifactKind.WindowsExecutable,
            ".msi" => InstallerArtifactKind.WindowsInstallerPackage,
            ".msix" => InstallerArtifactKind.MsixPackage,
            ".appx" => InstallerArtifactKind.AppxPackage,
            _ => InstallerArtifactKind.Unsupported
        };

    public static async Task<string> ComputeSha256Async(
        string path,
        CancellationToken cancellationToken = default)
    {
        await using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize: 128 * 1024,
            options: FileOptions.Asynchronous | FileOptions.SequentialScan);
        var digest = await SHA256.HashDataAsync(stream, cancellationToken);
        return Convert.ToHexString(digest).ToLowerInvariant();
    }

    private static (InstallerTrustStatus Status, int NativeStatus) VerifyAuthenticode(string path)
    {
        IntPtr pathPointer = IntPtr.Zero;
        IntPtr fileInfoPointer = IntPtr.Zero;
        try
        {
            pathPointer = Marshal.StringToCoTaskMemUni(path);
            var fileInfo = new WinTrustFileInfo
            {
                StructSize = (uint)Marshal.SizeOf<WinTrustFileInfo>(),
                FilePath = pathPointer,
                FileHandle = IntPtr.Zero,
                KnownSubject = IntPtr.Zero
            };
            fileInfoPointer = Marshal.AllocHGlobal(Marshal.SizeOf<WinTrustFileInfo>());
            Marshal.StructureToPtr(fileInfo, fileInfoPointer, fDeleteOld: false);

            var trustData = new WinTrustData
            {
                StructSize = (uint)Marshal.SizeOf<WinTrustData>(),
                PolicyCallbackData = IntPtr.Zero,
                SipClientData = IntPtr.Zero,
                UiChoice = WtdUiNone,
                RevocationChecks = WtdRevokeNone,
                UnionChoice = WtdChoiceFile,
                FileInfo = fileInfoPointer,
                StateAction = WtdStateActionIgnore,
                StateData = IntPtr.Zero,
                UrlReference = IntPtr.Zero,
                ProviderFlags = WtdCacheOnlyUrlRetrieval,
                UiContext = 0,
                SignatureSettings = IntPtr.Zero
            };

            var action = WinTrustActionGenericVerifyV2;
            var status = WinVerifyTrust(new IntPtr(-1), ref action, ref trustData);
            return status switch
            {
                0 => (InstallerTrustStatus.Trusted, status),
                TrustENoSignature => (InstallerTrustStatus.Unsigned, status),
                _ => (InstallerTrustStatus.Untrusted, status)
            };
        }
        catch (DllNotFoundException)
        {
            return (InstallerTrustStatus.VerificationUnavailable, -1);
        }
        catch (EntryPointNotFoundException)
        {
            return (InstallerTrustStatus.VerificationUnavailable, -1);
        }
        finally
        {
            if (fileInfoPointer != IntPtr.Zero) Marshal.FreeHGlobal(fileInfoPointer);
            if (pathPointer != IntPtr.Zero) Marshal.FreeCoTaskMem(pathPointer);
        }
    }

    private static string? TryReadPublisher(string path)
    {
        try
        {
            using var signer = X509Certificate.CreateFromSignedFile(path);
            using var certificate = new X509Certificate2(signer);
            var simpleName = certificate.GetNameInfo(X509NameType.SimpleName, forIssuer: false);
            return string.IsNullOrWhiteSpace(simpleName) ? certificate.Subject : simpleName;
        }
        catch (CryptographicException)
        {
            return null;
        }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WinTrustFileInfo
    {
        public uint StructSize;
        public IntPtr FilePath;
        public IntPtr FileHandle;
        public IntPtr KnownSubject;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WinTrustData
    {
        public uint StructSize;
        public IntPtr PolicyCallbackData;
        public IntPtr SipClientData;
        public uint UiChoice;
        public uint RevocationChecks;
        public uint UnionChoice;
        public IntPtr FileInfo;
        public uint StateAction;
        public IntPtr StateData;
        public IntPtr UrlReference;
        public uint ProviderFlags;
        public uint UiContext;
        public IntPtr SignatureSettings;
    }

    [DllImport("wintrust.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int WinVerifyTrust(
        IntPtr windowHandle,
        ref Guid actionId,
        ref WinTrustData trustData);
}
