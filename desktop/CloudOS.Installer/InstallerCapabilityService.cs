using System.Security.Cryptography;

namespace CloudOS.Installer;

public sealed record PreparedInstallerCapability(
    InstallerCapability Capability,
    InstallerArtifactPublicView Artifact,
    InstallerLaunchPlan LaunchPlan,
    InstallerReadiness Readiness);

public sealed class InstallerCapabilityService : IDisposable
{
    private readonly object _sync = new();
    private readonly InstallerCatalog _catalog;
    private readonly string _stagingRoot;
    private readonly string _logsRoot;
    private readonly TimeSpan _lifetime;
    private readonly Dictionary<string, CapabilityState> _capabilities = new(StringComparer.Ordinal);
    private bool _disposed;

    public InstallerCapabilityService(
        InstallerCatalog catalog,
        string stagingRoot,
        string logsRoot,
        TimeSpan? lifetime = null)
    {
        _catalog = catalog ?? throw new ArgumentNullException(nameof(catalog));
        ArgumentException.ThrowIfNullOrWhiteSpace(stagingRoot);
        ArgumentException.ThrowIfNullOrWhiteSpace(logsRoot);
        _stagingRoot = Path.GetFullPath(stagingRoot);
        _logsRoot = Path.GetFullPath(logsRoot);
        _lifetime = lifetime ?? TimeSpan.FromMinutes(5);
        if (_lifetime <= TimeSpan.Zero || _lifetime > TimeSpan.FromHours(1))
            throw new ArgumentOutOfRangeException(nameof(lifetime));
    }

    public async Task<PreparedInstallerCapability> PrepareAsync(
        string artifactId,
        bool elevatedBrokerAvailable,
        bool allowUntrusted,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        var record = await _catalog.GetRequiredAsync(artifactId, cancellationToken);
        var integrityValid = await _catalog.ValidateIntegrityAsync(record, cancellationToken);
        if (!integrityValid)
        {
            return Blocked(
                record,
                InstallerReadinessStatus.ArtifactChanged,
                integrityValid: false,
                elevatedBrokerAvailable,
                "The downloaded artifact no longer matches its registered SHA-256.");
        }

        var supported = record.Kind is InstallerArtifactKind.WindowsExecutable or InstallerArtifactKind.WindowsInstallerPackage;
        if (!supported)
        {
            return Blocked(
                record,
                InstallerReadinessStatus.UnsupportedFormat,
                integrityValid: true,
                elevatedBrokerAvailable,
                "This installer format is cataloged but does not yet have a CloudOS execution broker.");
        }

        if (record.Trust != InstallerTrustStatus.Trusted && !allowUntrusted)
        {
            return Blocked(
                record,
                InstallerReadinessStatus.BlockedByPolicy,
                integrityValid: true,
                elevatedBrokerAvailable,
                "Publisher trust is not verified. Explicit user confirmation is required before CloudOS may stage this installer.");
        }

        var capabilityId = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
        var issuedAt = DateTimeOffset.UtcNow;
        var expiresAt = issuedAt.Add(_lifetime);
        var capabilityDirectory = Path.Combine(_stagingRoot, capabilityId);
        Directory.CreateDirectory(capabilityDirectory);
        Directory.CreateDirectory(_logsRoot);

        var stagedPath = Path.Combine(capabilityDirectory, record.FileName);
        try
        {
            InstallerStagingCopy.CopyPreservingStreams(record.CanonicalPath, stagedPath);
            var stagedHash = await InstallerArtifactInspector.ComputeSha256Async(stagedPath, cancellationToken);
            if (!stagedHash.Equals(record.Sha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Staged installer hash does not match the approved artifact.");
            File.SetAttributes(stagedPath, File.GetAttributes(stagedPath) | FileAttributes.ReadOnly);

            var logPath = Path.Combine(_logsRoot, $"install-{capabilityId}.log");
            var launchPlan = InstallerLaunchPlanBuilder.Build(record, stagedPath, logPath);
            var capability = new InstallerCapability(
                capabilityId,
                record.ArtifactId,
                issuedAt,
                expiresAt,
                record.Sha256);

            lock (_sync)
            {
                ThrowIfDisposed();
                PurgeExpiredLocked(issuedAt);
                _capabilities.Add(capabilityId, new CapabilityState(capability, launchPlan, stagedPath));
            }

            var readiness = new InstallerReadiness(
                InstallerReadinessStatus.Ready,
                record.ToPublicView(),
                IntegrityValid: true,
                TrustValid: record.Trust == InstallerTrustStatus.Trusted,
                CanLaunchInUserSession: true,
                ElevatedBrokerAvailable: elevatedBrokerAvailable,
                Reason: record.Trust == InstallerTrustStatus.Trusted
                    ? null
                    : "User explicitly confirmed an installer whose publisher trust is not verified.");

            return new PreparedInstallerCapability(capability, record.ToPublicView(), launchPlan, readiness);
        }
        catch
        {
            TryDeleteDirectory(capabilityDirectory);
            throw;
        }
    }

    public async Task<InstallerLaunchPlan> ConsumeAsync(
        string capabilityId,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        ValidateCapabilityId(capabilityId);
        CapabilityState state;
        lock (_sync)
        {
            PurgeExpiredLocked(DateTimeOffset.UtcNow);
            if (!_capabilities.Remove(capabilityId, out state!))
                throw new InvalidOperationException("Installer capability is unknown, expired, or already consumed.");
        }

        try
        {
            if (DateTimeOffset.UtcNow > state.Capability.ExpiresAtUtc)
                throw new InvalidOperationException("Installer capability has expired.");
            if (!File.Exists(state.StagedPath))
                throw new FileNotFoundException("Staged installer disappeared before launch.", state.StagedPath);
            var stagedHash = await InstallerArtifactInspector.ComputeSha256Async(state.StagedPath, cancellationToken);
            if (!stagedHash.Equals(state.Capability.ExpectedSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Staged installer changed after capability issuance.");
            return state.LaunchPlan.Validate();
        }
        catch
        {
            TryDeleteDirectory(Path.GetDirectoryName(state.StagedPath)!);
            throw;
        }
    }

    public void Complete(string capabilityId)
    {
        if (string.IsNullOrWhiteSpace(capabilityId)) return;
        var directory = Path.Combine(_stagingRoot, capabilityId);
        TryDeleteDirectory(directory);
    }

    public void Dispose()
    {
        List<CapabilityState> states;
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true;
            states = [.. _capabilities.Values];
            _capabilities.Clear();
        }
        foreach (var state in states)
            TryDeleteDirectory(Path.GetDirectoryName(state.StagedPath)!);
    }

    private static PreparedInstallerCapability Blocked(
        InstallerArtifactRecord record,
        InstallerReadinessStatus status,
        bool integrityValid,
        bool elevatedBrokerAvailable,
        string reason) =>
        new(
            EmptyCapability(record),
            record.ToPublicView(),
            EmptyLaunchPlan(record),
            new InstallerReadiness(
                status,
                record.ToPublicView(),
                integrityValid,
                record.Trust == InstallerTrustStatus.Trusted,
                CanLaunchInUserSession: false,
                elevatedBrokerAvailable,
                reason));

    private void PurgeExpiredLocked(DateTimeOffset now)
    {
        foreach (var pair in _capabilities
            .Where(pair => now > pair.Value.Capability.ExpiresAtUtc)
            .ToArray())
        {
            _capabilities.Remove(pair.Key);
            TryDeleteDirectory(Path.GetDirectoryName(pair.Value.StagedPath)!);
        }
    }

    private static InstallerCapability EmptyCapability(InstallerArtifactRecord record) =>
        new(string.Empty, record.ArtifactId, DateTimeOffset.MinValue, DateTimeOffset.MinValue, record.Sha256);

    private static InstallerLaunchPlan EmptyLaunchPlan(InstallerArtifactRecord record) =>
        new(record.ArtifactId, record.Kind, string.Empty, Array.Empty<string>(), string.Empty, null, false, false, record.Sha256);

    private static void ValidateCapabilityId(string capabilityId)
    {
        if (capabilityId.Length != 64 || capabilityId.Any(character => !Uri.IsHexDigit(character)))
            throw new ArgumentException("Installer capability ID is invalid.", nameof(capabilityId));
    }

    private static void TryDeleteDirectory(string directory)
    {
        try
        {
            if (!Directory.Exists(directory)) return;
            foreach (var file in Directory.EnumerateFiles(directory, "*", SearchOption.AllDirectories))
            {
                try { File.SetAttributes(file, FileAttributes.Normal); } catch (IOException) { }
            }
            Directory.Delete(directory, recursive: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // Best-effort cleanup. Capability consumption/expiry still prevents reuse.
        }
    }

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(InstallerCapabilityService));
    }

    private sealed record CapabilityState(
        InstallerCapability Capability,
        InstallerLaunchPlan LaunchPlan,
        string StagedPath);
}
