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
    private readonly CancellationTokenSource _disposeSignal = new();
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
        if (!File.Exists(record.CanonicalPath))
        {
            return Blocked(
                record,
                InstallerReadinessStatus.ArtifactMissing,
                integrityValid: false,
                elevatedBrokerAvailable,
                "The downloaded artifact no longer exists.");
        }

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

        InstallerArtifactInspection currentInspection;
        try
        {
            currentInspection = await InstallerArtifactInspector.InspectAsync(record.CanonicalPath, cancellationToken);
        }
        catch (FileNotFoundException)
        {
            return Blocked(
                record,
                InstallerReadinessStatus.ArtifactMissing,
                integrityValid: false,
                elevatedBrokerAvailable,
                "The downloaded artifact disappeared during validation.");
        }

        if (!MatchesRegisteredArtifact(record, currentInspection))
        {
            return Blocked(
                RefreshSecurityMetadata(record, currentInspection),
                InstallerReadinessStatus.ArtifactChanged,
                integrityValid: false,
                elevatedBrokerAvailable,
                "The downloaded artifact changed while CloudOS was validating it.");
        }

        var currentRecord = RefreshSecurityMetadata(record, currentInspection);
        var supported = currentRecord.Kind is InstallerArtifactKind.WindowsExecutable or InstallerArtifactKind.WindowsInstallerPackage;
        if (!supported)
        {
            return Blocked(
                currentRecord,
                InstallerReadinessStatus.UnsupportedFormat,
                integrityValid: true,
                elevatedBrokerAvailable,
                "This installer format is cataloged but does not yet have a CloudOS execution broker.");
        }

        if (currentRecord.Trust != InstallerTrustStatus.Trusted && !allowUntrusted)
        {
            return Blocked(
                currentRecord,
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

        var stagedPath = Path.Combine(capabilityDirectory, currentRecord.FileName);
        try
        {
            InstallerStagingCopy.CopyPreservingStreams(currentRecord.CanonicalPath, stagedPath);
            var stagedInspection = await InstallerArtifactInspector.InspectAsync(stagedPath, cancellationToken);
            if (!MatchesRegisteredArtifact(currentRecord, stagedInspection))
                throw new InvalidDataException("Staged installer no longer matches the approved artifact.");

            var requireTrustedPublisher = currentRecord.Trust == InstallerTrustStatus.Trusted;
            if (requireTrustedPublisher && stagedInspection.Trust != InstallerTrustStatus.Trusted)
                throw new InvalidDataException("Staged installer publisher trust changed after approval.");

            var stagedRecord = RefreshSecurityMetadata(currentRecord, stagedInspection);
            File.SetAttributes(stagedPath, File.GetAttributes(stagedPath) | FileAttributes.ReadOnly);

            var logPath = Path.Combine(_logsRoot, $"install-{capabilityId}.log");
            var launchPlan = InstallerLaunchPlanBuilder.Build(stagedRecord, stagedPath, logPath);
            var capability = new InstallerCapability(
                capabilityId,
                stagedRecord.ArtifactId,
                issuedAt,
                expiresAt,
                stagedRecord.Sha256);
            var expirationToken = _disposeSignal.Token;

            lock (_sync)
            {
                ThrowIfDisposed();
                PurgeExpiredLocked(issuedAt);
                _capabilities.Add(
                    capabilityId,
                    new CapabilityState(
                        capability,
                        launchPlan,
                        stagedPath,
                        requireTrustedPublisher));
            }
            _ = ExpireCapabilityAsync(capabilityId, expiresAt, expirationToken);

            var readiness = new InstallerReadiness(
                InstallerReadinessStatus.Ready,
                stagedRecord.ToPublicView(),
                IntegrityValid: true,
                TrustValid: stagedRecord.Trust == InstallerTrustStatus.Trusted,
                CanLaunchInUserSession: true,
                ElevatedBrokerAvailable: elevatedBrokerAvailable,
                Reason: stagedRecord.Trust == InstallerTrustStatus.Trusted
                    ? null
                    : "User explicitly confirmed an installer whose publisher trust is not verified.");

            return new PreparedInstallerCapability(capability, stagedRecord.ToPublicView(), launchPlan, readiness);
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

            var stagedInspection = await InstallerArtifactInspector.InspectAsync(state.StagedPath, cancellationToken);
            if (!stagedInspection.Sha256.Equals(state.Capability.ExpectedSha256, StringComparison.OrdinalIgnoreCase)
                || stagedInspection.Kind != state.LaunchPlan.Kind)
            {
                throw new InvalidDataException("Staged installer changed after capability issuance.");
            }
            if (state.RequireTrustedPublisher && stagedInspection.Trust != InstallerTrustStatus.Trusted)
                throw new InvalidDataException("Staged installer publisher trust is no longer valid.");

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
        ThrowIfDisposed();
        ValidateCapabilityId(capabilityId);
        CapabilityState? state;
        lock (_sync)
            _capabilities.Remove(capabilityId, out state);
        var directory = state is null
            ? Path.Combine(_stagingRoot, capabilityId)
            : Path.GetDirectoryName(state.StagedPath)!;
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
        _disposeSignal.Cancel();
        foreach (var state in states)
            TryDeleteDirectory(Path.GetDirectoryName(state.StagedPath)!);
    }

    private async Task ExpireCapabilityAsync(
        string capabilityId,
        DateTimeOffset expiresAtUtc,
        CancellationToken cancellationToken)
    {
        var delay = expiresAtUtc - DateTimeOffset.UtcNow;
        if (delay > TimeSpan.Zero)
        {
            try
            {
                await Task.Delay(delay, cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                return;
            }
        }

        CapabilityState? expired = null;
        lock (_sync)
        {
            if (_disposed) return;
            if (_capabilities.TryGetValue(capabilityId, out var state)
                && DateTimeOffset.UtcNow >= state.Capability.ExpiresAtUtc)
            {
                _capabilities.Remove(capabilityId);
                expired = state;
            }
        }
        if (expired is not null)
            TryDeleteDirectory(Path.GetDirectoryName(expired.StagedPath)!);
    }

    private static bool MatchesRegisteredArtifact(
        InstallerArtifactRecord record,
        InstallerArtifactInspection inspection) =>
        inspection.Kind == record.Kind
        && inspection.SizeBytes == record.SizeBytes
        && inspection.Sha256.Equals(record.Sha256, StringComparison.OrdinalIgnoreCase);

    private static InstallerArtifactRecord RefreshSecurityMetadata(
        InstallerArtifactRecord record,
        InstallerArtifactInspection inspection) =>
        record with
        {
            FileName = Path.GetFileName(record.CanonicalPath),
            Kind = inspection.Kind,
            Sha256 = inspection.Sha256,
            SizeBytes = inspection.SizeBytes,
            LastWriteTimeUtc = inspection.LastWriteTimeUtc,
            Trust = inspection.Trust,
            Publisher = inspection.Publisher
        };

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
        ArgumentException.ThrowIfNullOrWhiteSpace(capabilityId);
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
        string StagedPath,
        bool RequireTrustedPublisher);
}
