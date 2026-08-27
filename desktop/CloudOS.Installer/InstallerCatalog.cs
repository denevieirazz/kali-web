using System.Text.Json;

namespace CloudOS.Installer;

public sealed class InstallerCatalog
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly string _downloadsRoot;
    private readonly string _catalogPath;
    private readonly Dictionary<string, InstallerArtifactRecord> _artifacts = new(StringComparer.Ordinal);
    private bool _loaded;

    public InstallerCatalog(string downloadsRoot, string catalogPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(downloadsRoot);
        ArgumentException.ThrowIfNullOrWhiteSpace(catalogPath);
        _downloadsRoot = Path.GetFullPath(downloadsRoot);
        _catalogPath = Path.GetFullPath(catalogPath);
    }

    public async Task<InstallerArtifactPublicView> RegisterManagedDownloadAsync(
        string path,
        string? sourceDownloadId = null,
        CancellationToken cancellationToken = default)
    {
        var canonicalPath = InstallerStorageLayout.NormalizeManagedDownloadPath(_downloadsRoot, path);
        var inspection = await InstallerArtifactInspector.InspectAsync(canonicalPath, cancellationToken);
        if (inspection.Kind == InstallerArtifactKind.Unsupported)
            throw new NotSupportedException("The downloaded file is not a supported Windows installer artifact.");

        var record = new InstallerArtifactRecord(
            Guid.NewGuid().ToString("N"),
            Path.GetFileName(canonicalPath),
            canonicalPath,
            inspection.Kind,
            inspection.Sha256,
            inspection.SizeBytes,
            inspection.LastWriteTimeUtc,
            inspection.Trust,
            inspection.Publisher,
            DateTimeOffset.UtcNow,
            string.IsNullOrWhiteSpace(sourceDownloadId) ? null : sourceDownloadId);

        await _gate.WaitAsync(cancellationToken);
        try
        {
            await EnsureLoadedLockedAsync(cancellationToken);
            foreach (var stale in _artifacts.Values
                .Where(item => item.CanonicalPath.Equals(canonicalPath, StringComparison.OrdinalIgnoreCase))
                .Select(item => item.ArtifactId)
                .ToArray())
            {
                _artifacts.Remove(stale);
            }
            _artifacts.Add(record.ArtifactId, record);
            await PersistLockedAsync(cancellationToken);
        }
        finally
        {
            _gate.Release();
        }

        return record.ToPublicView();
    }

    public async Task<IReadOnlyList<InstallerArtifactPublicView>> ListAsync(
        CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            await EnsureLoadedLockedAsync(cancellationToken);
            return _artifacts.Values
                .OrderByDescending(item => item.RegisteredAtUtc)
                .Select(item => item.ToPublicView())
                .ToArray();
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<InstallerArtifactRecord> GetRequiredAsync(
        string artifactId,
        CancellationToken cancellationToken = default)
    {
        ValidateArtifactId(artifactId);
        await _gate.WaitAsync(cancellationToken);
        try
        {
            await EnsureLoadedLockedAsync(cancellationToken);
            if (!_artifacts.TryGetValue(artifactId, out var record))
                throw new KeyNotFoundException($"Installer artifact '{artifactId}' was not found.");
            return record;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<bool> ValidateIntegrityAsync(
        InstallerArtifactRecord record,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(record);
        string canonicalPath;
        try
        {
            canonicalPath = InstallerStorageLayout.NormalizeManagedDownloadPath(_downloadsRoot, record.CanonicalPath);
        }
        catch (Exception error) when (error is ArgumentException or UnauthorizedAccessException or NotSupportedException)
        {
            return false;
        }

        if (!File.Exists(canonicalPath)) return false;
        var file = new FileInfo(canonicalPath);
        if (file.Length != record.SizeBytes) return false;
        var digest = await InstallerArtifactInspector.ComputeSha256Async(canonicalPath, cancellationToken);
        return digest.Equals(record.Sha256, StringComparison.OrdinalIgnoreCase);
    }

    public async Task<bool> RemoveAsync(
        string artifactId,
        CancellationToken cancellationToken = default)
    {
        ValidateArtifactId(artifactId);
        await _gate.WaitAsync(cancellationToken);
        try
        {
            await EnsureLoadedLockedAsync(cancellationToken);
            if (!_artifacts.Remove(artifactId)) return false;
            await PersistLockedAsync(cancellationToken);
            return true;
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task EnsureLoadedLockedAsync(CancellationToken cancellationToken)
    {
        if (_loaded) return;
        _loaded = true;
        if (!File.Exists(_catalogPath)) return;

        await using var stream = new FileStream(
            _catalogPath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize: 64 * 1024,
            options: FileOptions.Asynchronous | FileOptions.SequentialScan);
        CatalogDocument? document;
        try
        {
            document = await JsonSerializer.DeserializeAsync<CatalogDocument>(stream, JsonOptions, cancellationToken);
        }
        catch (JsonException error)
        {
            throw new InvalidDataException("CloudOS installer catalog is corrupt; refusing to discard trusted artifact state.", error);
        }

        if (document is null || document.SchemaVersion != 1 || document.Artifacts is null)
            throw new InvalidDataException("CloudOS installer catalog has an unsupported schema.");

        foreach (var record in document.Artifacts)
        {
            ValidateArtifactId(record.ArtifactId);
            if (_artifacts.ContainsKey(record.ArtifactId))
                throw new InvalidDataException("CloudOS installer catalog contains duplicate artifact IDs.");
            _artifacts.Add(record.ArtifactId, record);
        }
    }

    private async Task PersistLockedAsync(CancellationToken cancellationToken)
    {
        var directory = Path.GetDirectoryName(_catalogPath)
            ?? throw new InvalidOperationException("Installer catalog path has no parent directory.");
        Directory.CreateDirectory(directory);
        var temp = Path.Combine(directory, $".{Path.GetFileName(_catalogPath)}.{Guid.NewGuid():N}.tmp");
        try
        {
            await using (var stream = new FileStream(
                temp,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                bufferSize: 64 * 1024,
                options: FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                var document = new CatalogDocument(1, _artifacts.Values.OrderBy(item => item.ArtifactId).ToArray());
                await JsonSerializer.SerializeAsync(stream, document, JsonOptions, cancellationToken);
                await stream.FlushAsync(cancellationToken);
            }
            File.Move(temp, _catalogPath, overwrite: true);
        }
        finally
        {
            if (File.Exists(temp)) File.Delete(temp);
        }
    }

    private static void ValidateArtifactId(string artifactId)
    {
        if (artifactId.Length != 32 || artifactId.Any(character => !Uri.IsHexDigit(character)))
            throw new ArgumentException("Installer artifact ID is invalid.", nameof(artifactId));
    }

    private sealed record CatalogDocument(int SchemaVersion, InstallerArtifactRecord[] Artifacts);
}
