using CloudOS.Installer;

namespace CloudOS.Host.Installer;

public sealed class InstallerArtifactRegisteredEventArgs : EventArgs
{
    public InstallerArtifactRegisteredEventArgs(InstallerArtifactPublicView artifact)
    {
        Artifact = artifact ?? throw new ArgumentNullException(nameof(artifact));
    }

    public InstallerArtifactPublicView Artifact { get; }
}

/// <summary>
/// Host-owned installer authority. Web content never supplies native paths to this type.
/// Downloads are admitted only from the canonical CloudOS Downloads root, then installation
/// requests use opaque artifact/capability IDs with SHA-256 revalidation and one-shot staging.
/// </summary>
public sealed class CloudOsInstallerManager : IDisposable
{
    private readonly InstallerCatalog _catalog;
    private readonly InstallerCapabilityService _capabilities;
    private readonly IInstallerElevationBroker _elevationBroker;
    private bool _disposed;

    public CloudOsInstallerManager(
        string localApplicationData,
        IInstallerElevationBroker? elevationBroker = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(localApplicationData);
        InstallerStorageLayout.EnsureDirectories(localApplicationData);
        ManagedDownloadsRoot = InstallerStorageLayout.DownloadsRoot(localApplicationData);
        _catalog = new InstallerCatalog(
            ManagedDownloadsRoot,
            InstallerStorageLayout.CatalogPath(localApplicationData));
        _capabilities = new InstallerCapabilityService(
            _catalog,
            InstallerStorageLayout.StagingRoot(localApplicationData),
            InstallerStorageLayout.LogsRoot(localApplicationData));
        _elevationBroker = elevationBroker ?? new UnavailableInstallerElevationBroker();
    }

    public event EventHandler<InstallerArtifactRegisteredEventArgs>? ArtifactRegistered;

    public string ManagedDownloadsRoot { get; }
    public bool ElevationBrokerAvailable => _elevationBroker.IsAvailable;

    public async Task<InstallerArtifactPublicView> RegisterDownloadedInstallerAsync(
        string path,
        string? downloadId,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        var artifact = await _catalog.RegisterManagedDownloadAsync(path, downloadId, cancellationToken);
        ArtifactRegistered?.Invoke(this, new InstallerArtifactRegisteredEventArgs(artifact));
        return artifact;
    }

    public Task<IReadOnlyList<InstallerArtifactPublicView>> ListArtifactsAsync(
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        return _catalog.ListAsync(cancellationToken);
    }

    public Task<PreparedInstallerCapability> PrepareAsync(
        string artifactId,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        return _capabilities.PrepareAsync(
            artifactId,
            _elevationBroker.IsAvailable,
            cancellationToken);
    }

    public Task<InstallerLaunchPlan> ConsumeAsync(
        string capabilityId,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        return _capabilities.ConsumeAsync(capabilityId, cancellationToken);
    }

    public void Complete(string capabilityId)
    {
        if (_disposed) return;
        _capabilities.Complete(capabilityId);
    }

    public Task<InstallerBrokerResult> StartElevatedAsync(
        InstallerBrokerRequest request,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        return _elevationBroker.StartElevatedAsync(request, cancellationToken);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _capabilities.Dispose();
    }

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(CloudOsInstallerManager));
    }
}
