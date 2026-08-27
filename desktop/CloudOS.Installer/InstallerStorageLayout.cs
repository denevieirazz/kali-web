namespace CloudOS.Installer;

public static class InstallerStorageLayout
{
    public const string CatalogFileName = "installer-catalog.v1.json";

    public static string CloudOsRoot(string localApplicationData) =>
        Path.Combine(localApplicationData, "CloudOS");

    public static string DownloadsRoot(string localApplicationData) =>
        Path.Combine(CloudOsRoot(localApplicationData), "Downloads");

    public static string InstallerRoot(string localApplicationData) =>
        Path.Combine(CloudOsRoot(localApplicationData), "Installer");

    public static string CatalogPath(string localApplicationData) =>
        Path.Combine(InstallerRoot(localApplicationData), CatalogFileName);

    public static string StagingRoot(string localApplicationData) =>
        Path.Combine(InstallerRoot(localApplicationData), "Staging");

    public static string LogsRoot(string localApplicationData) =>
        Path.Combine(InstallerRoot(localApplicationData), "Logs");

    public static void EnsureDirectories(string localApplicationData)
    {
        Directory.CreateDirectory(DownloadsRoot(localApplicationData));
        Directory.CreateDirectory(InstallerRoot(localApplicationData));
        Directory.CreateDirectory(StagingRoot(localApplicationData));
        Directory.CreateDirectory(LogsRoot(localApplicationData));
    }

    public static string NormalizeManagedDownloadPath(string downloadsRoot, string path)
    {
        if (string.IsNullOrWhiteSpace(downloadsRoot)) throw new ArgumentException("Downloads root is required.", nameof(downloadsRoot));
        if (string.IsNullOrWhiteSpace(path)) throw new ArgumentException("Path is required.", nameof(path));

        var normalizedRoot = Path.GetFullPath(downloadsRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var normalizedPath = Path.GetFullPath(path);
        var relative = Path.GetRelativePath(normalizedRoot, normalizedPath);
        if (relative.Equals("..", StringComparison.Ordinal) ||
            relative.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal) ||
            relative.StartsWith($"..{Path.AltDirectorySeparatorChar}", StringComparison.Ordinal) ||
            Path.IsPathRooted(relative))
        {
            throw new UnauthorizedAccessException("Installer artifact must remain inside the CloudOS managed downloads root.");
        }

        return normalizedPath;
    }

    public static string CreateUniqueDownloadPath(string downloadsRoot, string suggestedName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(suggestedName);
        Directory.CreateDirectory(downloadsRoot);

        var safeName = SanitizeFileName(Path.GetFileName(suggestedName));
        if (string.IsNullOrWhiteSpace(safeName)) safeName = "download";
        var extension = Path.GetExtension(safeName);
        var stem = Path.GetFileNameWithoutExtension(safeName);
        if (stem.Length > 120) stem = stem[..120];
        if (extension.Length > 16) extension = string.Empty;

        var candidate = Path.Combine(downloadsRoot, stem + extension);
        if (!File.Exists(candidate)) return candidate;

        for (var index = 2; index <= 9999; index++)
        {
            candidate = Path.Combine(downloadsRoot, $"{stem} ({index}){extension}");
            if (!File.Exists(candidate)) return candidate;
        }

        return Path.Combine(downloadsRoot, $"{stem}-{Guid.NewGuid():N}{extension}");
    }

    private static string SanitizeFileName(string fileName)
    {
        var invalid = Path.GetInvalidFileNameChars().ToHashSet();
        var chars = fileName.Select(character => invalid.Contains(character) ? '_' : character).ToArray();
        return new string(chars).Trim().TrimEnd('.');
    }
}
