using System.IO;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Host.Browser;

public sealed class BrowserExtensionManager
{
    public const int MaxManifestBytes = BrowserExtensionPackageValidator.MaxManifestBytes;
    public const int MaxPackageFiles = BrowserExtensionPackageValidator.MaxPackageFiles;
    public const long MaxPackageBytes = BrowserExtensionPackageValidator.MaxPackageBytes;

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
        BrowserExtensionPackageValidator.EnsureDirectoryNotReparsePoint(_managedRoot);
        _managedByExtensionId = LoadState();
    }

    public string ManagedRoot => _managedRoot;

    public static BrowserExtensionPackageInfo ValidatePackage(string sourceDirectory) =>
        BrowserExtensionPackageValidator.ValidatePackage(sourceDirectory);

    public bool IsManagedExtension(string extensionId)
    {
        if (!TryGetManagedPackagePath(extensionId, out var managedPath) || !Directory.Exists(managedPath))
            return false;
        try
        {
            BrowserExtensionPackageValidator.EnsureDirectoryNotReparsePoint(managedPath);
            return true;
        }
        catch (BrowserExtensionPackageException)
        {
            return false;
        }
    }

    public async Task<CoreWebView2BrowserExtension> InstallAsync(
        CoreWebView2Profile profile,
        string sourceDirectory,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(profile);
        _ = BrowserExtensionPackageValidator.ValidatePackage(sourceDirectory);
        var source = Path.GetFullPath(sourceDirectory);

        if (BrowserExtensionPackageValidator.IsDescendantOrSame(source, _managedRoot))
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
        if (!TryGetManagedPackagePath(id, out var managedPath) || !IsManagedExtension(id))
            throw new BrowserExtensionPackageException("EXTENSION_NOT_CLOUDOS_MANAGED");

        try
        {
            await extension.RemoveAsync();
        }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            throw new BrowserExtensionPackageException("EXTENSION_WEBVIEW_REMOVE_FAILED");
        }

        if (!_managedByExtensionId.Remove(id))
            throw new BrowserExtensionPackageException("EXTENSION_NOT_CLOUDOS_MANAGED");

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
            if (installed.Contains(entry.Key) && IsManagedExtension(entry.Key)) continue;
            _managedByExtensionId.Remove(entry.Key);
            TryDeleteManagedDirectory(entry.Value);
            changed = true;
        }

        if (changed) SaveState();
    }

    private bool TryGetManagedPackagePath(string extensionId, out string managedPath) =>
        BrowserManagedExtensionOwnership.TryResolveManagedPackage(
            _managedByExtensionId,
            _managedRoot,
            extensionId,
            out managedPath);

    private static void CopyPackageTree(string sourceRoot, string destinationRoot, CancellationToken cancellationToken)
    {
        var pending = new Stack<string>();
        pending.Push(sourceRoot);

        while (pending.Count > 0)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var current = pending.Pop();
            BrowserExtensionPackageValidator.EnsureInsideRoot(sourceRoot, current);
            BrowserExtensionPackageValidator.EnsureDirectoryNotReparsePoint(current);

            var relative = Path.GetRelativePath(sourceRoot, current);
            var destinationCurrent = relative == "."
                ? destinationRoot
                : Path.Combine(destinationRoot, relative);
            Directory.CreateDirectory(destinationCurrent);

            foreach (var directory in Directory.EnumerateDirectories(current))
            {
                BrowserExtensionPackageValidator.EnsureInsideRoot(sourceRoot, directory);
                BrowserExtensionPackageValidator.EnsureDirectoryNotReparsePoint(directory);
                pending.Push(directory);
            }

            foreach (var file in Directory.EnumerateFiles(current))
            {
                cancellationToken.ThrowIfCancellationRequested();
                BrowserExtensionPackageValidator.EnsureInsideRoot(sourceRoot, file);
                BrowserExtensionPackageValidator.EnsureFileNotReparsePoint(file);
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
                    BrowserManagedExtensionOwnership.IsSafeManagedPackagePath(_managedRoot, pair.Value))
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
            BrowserExtensionPackageValidator.EnsureDirectoryNotReparsePoint(_managedRoot);
            var safeState = _managedByExtensionId
                .Where(pair => BrowserManagedExtensionOwnership.IsSafeManagedPackagePath(_managedRoot, pair.Value))
                .ToDictionary(pair => pair.Key, pair => Path.GetFullPath(pair.Value), StringComparer.Ordinal);
            if (safeState.Count != _managedByExtensionId.Count)
                throw new BrowserExtensionPackageException("EXTENSION_STATE_WRITE_FAILED");

            var temp = _statePath + ".tmp-" + Guid.NewGuid().ToString("N");
            File.WriteAllText(temp, JsonSerializer.Serialize(safeState, _json));
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

    private void TryDeleteManagedDirectory(string path)
    {
        try
        {
            var safe = BrowserManagedExtensionOwnership.IsSafeManagedPackagePath(_managedRoot, path) ||
                       BrowserManagedExtensionOwnership.IsSafeStagingPath(_managedRoot, path);
            if (!safe || !Directory.Exists(path)) return;
            BrowserExtensionPackageValidator.EnsureDirectoryNotReparsePoint(path);
            Directory.Delete(path, recursive: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException or BrowserExtensionPackageException)
        {
        }
    }
}
