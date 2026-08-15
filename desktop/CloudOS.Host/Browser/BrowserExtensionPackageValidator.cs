using System.IO;
using System.Text.Json;

namespace CloudOS.Host.Browser;

public sealed record BrowserExtensionPackageInfo(
    string Name,
    string Version,
    int ManifestVersion,
    int FileCount,
    long TotalBytes);

public sealed class BrowserExtensionPackageException : Exception
{
    public BrowserExtensionPackageException(string code) : base(code) => Code = code;
    public string Code { get; }
}

public static class BrowserExtensionPackageValidator
{
    public const int MaxManifestBytes = 1024 * 1024;
    public const int MaxPackageFiles = 4096;
    public const long MaxPackageBytes = 128L * 1024 * 1024;

    public static BrowserExtensionPackageInfo ValidatePackage(string sourceDirectory)
    {
        if (string.IsNullOrWhiteSpace(sourceDirectory))
            throw new BrowserExtensionPackageException("EXTENSION_PATH_EMPTY");

        string source;
        try
        {
            source = Path.GetFullPath(sourceDirectory);
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or PathTooLongException)
        {
            throw new BrowserExtensionPackageException("EXTENSION_PATH_INVALID");
        }

        if (!Directory.Exists(source))
            throw new BrowserExtensionPackageException("EXTENSION_DIRECTORY_NOT_FOUND");

        EnsureDirectoryNotReparsePoint(source);

        var manifestPath = Path.Combine(source, "manifest.json");
        if (!File.Exists(manifestPath))
            throw new BrowserExtensionPackageException("EXTENSION_MANIFEST_MISSING");
        EnsureFileNotReparsePoint(manifestPath);

        long manifestLength;
        try
        {
            manifestLength = new FileInfo(manifestPath).Length;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new BrowserExtensionPackageException("EXTENSION_MANIFEST_UNREADABLE");
        }

        if (manifestLength <= 0 || manifestLength > MaxManifestBytes)
            throw new BrowserExtensionPackageException("EXTENSION_MANIFEST_SIZE_INVALID");

        string manifestText;
        try
        {
            manifestText = File.ReadAllText(manifestPath);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new BrowserExtensionPackageException("EXTENSION_MANIFEST_UNREADABLE");
        }

        string name;
        string version;
        int manifestVersion;
        try
        {
            using var document = JsonDocument.Parse(manifestText, new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 64
            });
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
                throw new BrowserExtensionPackageException("EXTENSION_MANIFEST_INVALID");

            if (!root.TryGetProperty("name", out var nameNode) ||
                nameNode.ValueKind != JsonValueKind.String ||
                string.IsNullOrWhiteSpace(nameNode.GetString()))
                throw new BrowserExtensionPackageException("EXTENSION_MANIFEST_NAME_INVALID");

            if (!root.TryGetProperty("version", out var versionNode) ||
                versionNode.ValueKind != JsonValueKind.String ||
                string.IsNullOrWhiteSpace(versionNode.GetString()))
                throw new BrowserExtensionPackageException("EXTENSION_MANIFEST_VERSION_INVALID");

            if (!root.TryGetProperty("manifest_version", out var manifestVersionNode) ||
                manifestVersionNode.ValueKind != JsonValueKind.Number ||
                !manifestVersionNode.TryGetInt32(out manifestVersion) ||
                manifestVersion is not (2 or 3))
                throw new BrowserExtensionPackageException("EXTENSION_MANIFEST_VERSION_UNSUPPORTED");

            name = nameNode.GetString()!.Trim();
            version = versionNode.GetString()!.Trim();
        }
        catch (BrowserExtensionPackageException)
        {
            throw;
        }
        catch (JsonException)
        {
            throw new BrowserExtensionPackageException("EXTENSION_MANIFEST_INVALID");
        }

        var (fileCount, totalBytes) = InspectPackageTree(source);
        return new BrowserExtensionPackageInfo(
            SanitizeLabel(name, "Extensão local"),
            SanitizeLabel(version, "desconhecida"),
            manifestVersion,
            fileCount,
            totalBytes);
    }

    internal static bool IsDescendantOrSame(string candidate, string root)
    {
        var rootFull = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var candidateFull = Path.GetFullPath(candidate).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (candidateFull.Equals(rootFull, StringComparison.OrdinalIgnoreCase))
            return true;

        return candidateFull.StartsWith(
            rootFull + Path.DirectorySeparatorChar,
            StringComparison.OrdinalIgnoreCase);
    }

    internal static void EnsureInsideRoot(string root, string candidate)
    {
        var rootFull = Path.GetFullPath(root);
        var candidateFull = Path.GetFullPath(candidate);
        if (!IsDescendantOrSame(candidateFull, rootFull))
            throw new BrowserExtensionPackageException("EXTENSION_PATH_ESCAPE");
    }

    internal static void EnsureDirectoryNotReparsePoint(string path)
    {
        try
        {
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new BrowserExtensionPackageException("EXTENSION_REPARSE_POINT_BLOCKED");
        }
        catch (BrowserExtensionPackageException)
        {
            throw;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new BrowserExtensionPackageException("EXTENSION_TREE_UNREADABLE");
        }
    }

    internal static void EnsureFileNotReparsePoint(string path)
    {
        try
        {
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new BrowserExtensionPackageException("EXTENSION_REPARSE_POINT_BLOCKED");
        }
        catch (BrowserExtensionPackageException)
        {
            throw;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new BrowserExtensionPackageException("EXTENSION_TREE_UNREADABLE");
        }
    }

    private static (int FileCount, long TotalBytes) InspectPackageTree(string sourceRoot)
    {
        var count = 0;
        long bytes = 0;
        var pending = new Stack<string>();
        pending.Push(sourceRoot);

        while (pending.Count > 0)
        {
            var current = pending.Pop();
            EnsureInsideRoot(sourceRoot, current);
            EnsureDirectoryNotReparsePoint(current);

            IEnumerable<string> directories;
            IEnumerable<string> files;
            try
            {
                directories = Directory.EnumerateDirectories(current).ToArray();
                files = Directory.EnumerateFiles(current).ToArray();
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                throw new BrowserExtensionPackageException("EXTENSION_TREE_UNREADABLE");
            }

            foreach (var directory in directories)
            {
                EnsureInsideRoot(sourceRoot, directory);
                EnsureDirectoryNotReparsePoint(directory);
                pending.Push(directory);
            }

            foreach (var file in files)
            {
                EnsureInsideRoot(sourceRoot, file);
                EnsureFileNotReparsePoint(file);
                count++;
                if (count > MaxPackageFiles)
                    throw new BrowserExtensionPackageException("EXTENSION_TOO_MANY_FILES");

                long length;
                try
                {
                    length = new FileInfo(file).Length;
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                {
                    throw new BrowserExtensionPackageException("EXTENSION_TREE_UNREADABLE");
                }

                if (length < 0 || bytes > MaxPackageBytes - length)
                    throw new BrowserExtensionPackageException("EXTENSION_PACKAGE_TOO_LARGE");
                bytes += length;
            }
        }

        if (count == 0)
            throw new BrowserExtensionPackageException("EXTENSION_PACKAGE_EMPTY");

        return (count, bytes);
    }

    private static string SanitizeLabel(string value, string fallback)
    {
        var normalized = new string(value.Where(ch => !char.IsControl(ch)).ToArray()).Trim();
        if (string.IsNullOrWhiteSpace(normalized)) return fallback;
        return normalized.Length <= 80 ? normalized : normalized[..80] + "…";
    }
}
