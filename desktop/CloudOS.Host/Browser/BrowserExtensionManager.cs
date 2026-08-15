using System.IO;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;

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

public sealed class BrowserExtensionManager
{
    public const int MaxManifestBytes = 1024 * 1024;
    public const int MaxPackageFiles = 4096;
    public const long MaxPackageBytes = 128L * 1024 * 1024;

    private readonly string _managedRoot;
    private readonly string _statePath;
    private readonly JsonSerializerOptions _json = new() { WriteIndented = true };
    private Dictionary<string, string> _managedByExtensionId;

    public BrowserExtensionManager(string browserUserDataFolder)
    {
        var udf = Path.GetFullPath(browserUserDataFolder);
        var browserRoot = Directory.GetParent(udf)?.FullName
            ?? throw new BrowserExtensionPackageException("EXTENSION_STORAGE_ROOT_INVALID");
        _managedRoot = Path.Combine(browserRoot, "Extensions");
        _statePath = Path.Combine(_managedRoot, "managed-extensions.v1.json");
        Directory.CreateDirectory(_managedRoot);
        EnsureDirectoryNotReparsePoint(_managedRoot);
        _managedByExtensionId = LoadState();
    }

    public string ManagedRoot => _managedRoot;

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

        var manifestLength = new FileInfo(manifestPath).Length;
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

    public async Task<CoreWebView2BrowserExtension> InstallAsync(
        CoreWebView2Profile profile,
        string sourceDirectory,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(profile);
        var package = ValidatePackage(sourceDirectory);
        var source = Path.GetFullPath(sourceDirectory);

        if (IsDescendantOrSame(source, _managedRoot))
            throw new BrowserExtensionPackageException("EXTENSION_SOURCE_ALREADY_MANAGED");

        var staging = Path.Combine(_managedRoot, ".staging-" + Guid.NewGuid().ToString("N"));
        var managed = Path.Combine(_managedRoot, "package-" + Guid.NewGuid().ToString("N"));
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            Directory.CreateDirectory(staging);
            await Task.Run(() => CopyPackageTree(source, staging, cancellationToken), cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();

            Directory.Move(staging, managed);
            CoreWebView2BrowserExtension extension;
            try
            {
                extension = await profile.AddBrowserExtensionAsync(managed);
            }
            catch (Exception error) when (
                error is ArgumentException or InvalidOperationException or IOException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException)
            {
                throw new BrowserExtensionPackageException("EXTENSION_WEBVIEW_INSTALL_FAILED");
            }

            try
            {
                _managedByExtensionId[extension.Id] = managed;
                SaveState();
            }
            catch
            {
                try { await extension.RemoveAsync(); } catch { }
                TryDeleteManagedDirectory(managed);
                throw;
            }

            _ = package;
            return extension;
        }
        catch (BrowserExtensionPackageException)
        {
            TryDeleteManagedDirectory(staging);
            if (Directory.Exists(managed) && !_managedByExtensionId.Values.Contains(managed, StringComparer.OrdinalIgnoreCase))
                TryDeleteManagedDirectory(managed);
            throw;
        }
        catch (OperationCanceledException)
        {
            TryDeleteManagedDirectory(staging);
            if (Directory.Exists(managed) && !_managedByExtensionId.Values.Contains(managed, StringComparer.OrdinalIgnoreCase))
                TryDeleteManagedDirectory(managed);
            throw;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            TryDeleteManagedDirectory(staging);
            if (Directory.Exists(managed) && !_managedByExtensionId.Values.Contains(managed, StringComparer.OrdinalIgnoreCase))
                TryDeleteManagedDirectory(managed);
            throw new BrowserExtensionPackageException("EXTENSION_MANAGED_COPY_FAILED");
        }
    }

    public async Task RemoveAsync(CoreWebView2BrowserExtension extension)
    {
        ArgumentNullException.ThrowIfNull(extension);
        var id = extension.Id;
        try
        {
            await extension.RemoveAsync();
        }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            throw new BrowserExtensionPackageException("EXTENSION_WEBVIEW_REMOVE_FAILED");
        }

        if (!_managedByExtensionId.Remove(id, out var managedPath))
            return;

        try
        {
            SaveState();
        }
        catch (BrowserExtensionPackageException)
        {
            _managedByExtensionId[id] = managedPath;
            throw;
        }

        TryDeleteManagedDirectory(managedPath);
    }

    public void ReconcileManagedPackages(IEnumerable<string> installedExtensionIds)
    {
        var installed = installedExtensionIds.ToHashSet(StringComparer.Ordinal);
        var changed = false;
        foreach (var entry in _managedByExtensionId.ToArray())
        {
            if (installed.Contains(entry.Key)) continue;
            _managedByExtensionId.Remove(entry.Key);
            TryDeleteManagedDirectory(entry.Value);
            changed = true;
        }

        if (changed) SaveState();
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
                try { length = new FileInfo(file).Length; }
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

    private static void CopyPackageTree(string sourceRoot, string destinationRoot, CancellationToken cancellationToken)
    {
        var pending = new Stack<string>();
        pending.Push(sourceRoot);

        while (pending.Count > 0)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var current = pending.Pop();
            EnsureInsideRoot(sourceRoot, current);
            EnsureDirectoryNotReparsePoint(current);

            var relative = Path.GetRelativePath(sourceRoot, current);
            var destinationCurrent = relative == "."
                ? destinationRoot
                : Path.Combine(destinationRoot, relative);
            Directory.CreateDirectory(destinationCurrent);

            foreach (var directory in Directory.EnumerateDirectories(current))
            {
                EnsureInsideRoot(sourceRoot, directory);
                EnsureDirectoryNotReparsePoint(directory);
                pending.Push(directory);
            }

            foreach (var file in Directory.EnumerateFiles(current))
            {
                cancellationToken.ThrowIfCancellationRequested();
                EnsureInsideRoot(sourceRoot, file);
                EnsureFileNotReparsePoint(file);
                var fileRelative = Path.GetRelativePath(sourceRoot, file);
                var destinationFile = Path.Combine(destinationRoot, fileRelative);
                var destinationDirectory = Path.GetDirectoryName(destinationFile)
                    ?? throw new BrowserExtensionPackageException("EXTENSION_MANAGED_COPY_FAILED");
                Directory.CreateDirectory(destinationDirectory);
                File.Copy(file, destinationFile, overwrite: false);
            }
        }
    }

    private Dictionary<string, string> LoadState()
    {
        if (!File.Exists(_statePath))
            return new Dictionary<string, string>(StringComparer.Ordinal);
        try
        {
            var state = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(_statePath))
                ?? new Dictionary<string, string>();
            return state
                .Where(pair =>
                    !string.IsNullOrWhiteSpace(pair.Key) &&
                    !string.IsNullOrWhiteSpace(pair.Value) &&
                    IsDescendantOrSame(pair.Value, _managedRoot))
                .ToDictionary(pair => pair.Key, pair => Path.GetFullPath(pair.Value), StringComparer.Ordinal);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or ArgumentException)
        {
            return new Dictionary<string, string>(StringComparer.Ordinal);
        }
    }

    private void SaveState()
    {
        try
        {
            Directory.CreateDirectory(_managedRoot);
            EnsureDirectoryNotReparsePoint(_managedRoot);
            var temp = _statePath + ".tmp-" + Guid.NewGuid().ToString("N");
            File.WriteAllText(temp, JsonSerializer.Serialize(_managedByExtensionId, _json));
            File.Move(temp, _statePath, overwrite: true);
        }
        catch (BrowserExtensionPackageException)
        {
            throw;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new BrowserExtensionPackageException("EXTENSION_STATE_WRITE_FAILED");
        }
    }

    private static void EnsureInsideRoot(string root, string candidate)
    {
        var rootFull = Path.GetFullPath(root);
        var candidateFull = Path.GetFullPath(candidate);
        if (!IsDescendantOrSame(candidateFull, rootFull))
            throw new BrowserExtensionPackageException("EXTENSION_PATH_ESCAPE");
    }

    private static bool IsDescendantOrSame(string candidate, string root)
    {
        var rootFull = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var candidateFull = Path.GetFullPath(candidate).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (candidateFull.Equals(rootFull, StringComparison.OrdinalIgnoreCase))
            return true;

        return candidateFull.StartsWith(
            rootFull + Path.DirectorySeparatorChar,
            StringComparison.OrdinalIgnoreCase);
    }

    private static void EnsureDirectoryNotReparsePoint(string path)
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

    private static void EnsureFileNotReparsePoint(string path)
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

    private static string SanitizeLabel(string value, string fallback)
    {
        var normalized = new string(value.Where(ch => !char.IsControl(ch)).ToArray()).Trim();
        if (string.IsNullOrWhiteSpace(normalized)) return fallback;
        return normalized.Length <= 80 ? normalized : normalized[..80] + "…";
    }

    private static void TryDeleteManagedDirectory(string path)
    {
        try
        {
            if (!IsSafeManagedDirectoryName(path)) return;
            if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
        }
    }

    private static bool IsSafeManagedDirectoryName(string path)
    {
        var name = Path.GetFileName(Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        return name.StartsWith("package-", StringComparison.Ordinal) ||
               name.StartsWith(".staging-", StringComparison.Ordinal);
    }
}
