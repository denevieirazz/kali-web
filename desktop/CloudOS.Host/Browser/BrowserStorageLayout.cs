using System.IO;

namespace CloudOS.Host.Browser;

public static class BrowserStorageLayout
{
    public const string StateFileName = "browser-state.v1.json";
    private const int MaxDownloadNameLength = 180;
    private const int MaxCollisionAttempts = 10_000;
    private static readonly HashSet<string> ReservedDeviceNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    };

    public static string BrowserRoot(string localApplicationData) => Path.Combine(localApplicationData, "CloudOS", "Browser");
    public static string BrowserUserDataFolder(string localApplicationData) => Path.Combine(BrowserRoot(localApplicationData), "WebView2");
    public static string BrowserStatePath(string localApplicationData) => Path.Combine(BrowserRoot(localApplicationData), StateFileName);
    public static string ShellUserDataFolder(string localApplicationData) => Path.Combine(localApplicationData, "CloudOS", "WebView2");

    public static string CloudOsDriveRoot(string localApplicationData, string? overrideRoot = null)
    {
        if (!string.IsNullOrWhiteSpace(overrideRoot)) return Path.GetFullPath(overrideRoot);
        return Path.GetFullPath(Path.Combine(localApplicationData, "CloudOS", "Drive"));
    }

    public static string CloudOsDriveDownloads(string localApplicationData, string? overrideRoot = null) =>
        Path.Combine(CloudOsDriveRoot(localApplicationData, overrideRoot), "Home", "Downloads");

    internal static string AllocateCloudOsDownloadPath(
        string directory,
        string suggestedName,
        IEnumerable<string>? reservedPaths = null)
    {
        if (string.IsNullOrWhiteSpace(directory) || !Path.IsPathFullyQualified(directory))
            throw new ArgumentException("A fully-qualified CloudOS Downloads directory is required.", nameof(directory));

        var normalizedDirectory = Path.GetFullPath(directory);
        Directory.CreateDirectory(normalizedDirectory);
        var safeName = SanitizeDownloadName(suggestedName);
        var extension = Path.GetExtension(safeName);
        var stem = Path.GetFileNameWithoutExtension(safeName);
        if (string.IsNullOrWhiteSpace(stem)) stem = "download";

        var reserved = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (reservedPaths is not null)
        {
            foreach (var reservedPath in reservedPaths)
            {
                if (string.IsNullOrWhiteSpace(reservedPath)) continue;
                try { reserved.Add(Path.GetFullPath(reservedPath)); }
                catch (Exception error) when (error is ArgumentException or NotSupportedException) { }
            }
        }

        for (var attempt = 0; attempt < MaxCollisionAttempts; attempt++)
        {
            var fileName = attempt == 0 ? safeName : $"{stem} ({attempt}){extension}";
            var candidate = Path.GetFullPath(Path.Combine(normalizedDirectory, fileName));
            var candidateDirectory = Path.GetDirectoryName(candidate);
            if (!string.Equals(
                    candidateDirectory?.TrimEnd(Path.DirectorySeparatorChar),
                    normalizedDirectory.TrimEnd(Path.DirectorySeparatorChar),
                    StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("The download destination escaped CloudOS Drive.");
            if (!reserved.Contains(candidate) && !File.Exists(candidate) && !Directory.Exists(candidate)) return candidate;
        }

        throw new IOException("CloudOS Downloads could not allocate a unique file name.");
    }

    internal static string SanitizeDownloadName(string suggestedName)
    {
        var name = Path.GetFileName(suggestedName ?? string.Empty);
        if (string.IsNullOrWhiteSpace(name)) name = "download";

        var invalid = Path.GetInvalidFileNameChars();
        var characters = name.Select(character => invalid.Contains(character) || char.IsControl(character) ? '_' : character).ToArray();
        name = new string(characters).Trim().TrimEnd('.', ' ');
        if (string.IsNullOrWhiteSpace(name) || name is "." or "..") name = "download";

        var extension = Path.GetExtension(name);
        var stem = Path.GetFileNameWithoutExtension(name);
        if (ReservedDeviceNames.Contains(stem)) stem = $"_{stem}";

        var maximumStemLength = Math.Max(1, MaxDownloadNameLength - extension.Length);
        if (stem.Length > maximumStemLength) stem = stem[..maximumStemLength];
        name = (stem + extension).TrimEnd('.', ' ');
        return string.IsNullOrWhiteSpace(name) ? "download" : name;
    }

    public static bool AreIsolated(string browserFolder, string shellFolder) =>
        !Path.GetFullPath(browserFolder).TrimEnd(Path.DirectorySeparatorChar)
            .Equals(Path.GetFullPath(shellFolder).TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase);
}
