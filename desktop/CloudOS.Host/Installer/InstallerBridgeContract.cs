using CloudOS.Installer;

namespace CloudOS.Host.Installer;

public sealed record InstallerArtifactListBridgeResponse(
    IReadOnlyList<InstallerArtifactPublicView> Artifacts,
    bool ElevationBrokerAvailable);

public sealed record InstallerReadinessBridgeView(
    InstallerReadinessStatus Status,
    bool IntegrityValid,
    bool TrustValid,
    bool CanLaunchInUserSession,
    bool ElevatedBrokerAvailable,
    string? Reason);

public sealed record InstallerPrepareBridgeResponse(
    InstallerArtifactPublicView Artifact,
    InstallerReadinessBridgeView Readiness,
    string? CapabilityId,
    DateTimeOffset? ExpiresAtUtc);

/// <summary>
/// Public WebView contract for installer discovery/preparation. It deliberately
/// omits launch-plan paths, argv, working directories and native log paths.
/// </summary>
public static class InstallerBridgeContract
{
    public static InstallerArtifactListBridgeResponse List(
        IReadOnlyList<InstallerArtifactPublicView> artifacts,
        bool elevationBrokerAvailable)
    {
        ArgumentNullException.ThrowIfNull(artifacts);
        return new InstallerArtifactListBridgeResponse(
            artifacts.ToArray(),
            elevationBrokerAvailable);
    }

    public static InstallerPrepareBridgeResponse Prepare(PreparedInstallerCapability prepared)
    {
        ArgumentNullException.ThrowIfNull(prepared);
        var ready = prepared.Readiness.Status == InstallerReadinessStatus.Ready;
        var capabilityId = ready ? prepared.Capability.CapabilityId : null;
        DateTimeOffset? expiresAt = ready ? prepared.Capability.ExpiresAtUtc : null;

        if (ready)
            ValidateCapabilityId(capabilityId!);
        else if (!string.IsNullOrEmpty(prepared.Capability.CapabilityId))
            throw new InvalidOperationException("A blocked installer response cannot expose a capability.");

        return new InstallerPrepareBridgeResponse(
            prepared.Artifact,
            new InstallerReadinessBridgeView(
                prepared.Readiness.Status,
                prepared.Readiness.IntegrityValid,
                prepared.Readiness.TrustValid,
                prepared.Readiness.CanLaunchInUserSession,
                prepared.Readiness.ElevatedBrokerAvailable,
                prepared.Readiness.Reason),
            capabilityId,
            expiresAt);
    }

    public static string ValidateArtifactId(string artifactId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(artifactId);
        if (artifactId.Length != 32 || artifactId.Any(character => !Uri.IsHexDigit(character)))
            throw new ArgumentException("Installer artifact ID is invalid.", nameof(artifactId));
        return artifactId;
    }

    public static string ValidateCapabilityId(string capabilityId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(capabilityId);
        if (capabilityId.Length != 64 || capabilityId.Any(character => !Uri.IsHexDigit(character)))
            throw new ArgumentException("Installer capability ID is invalid.", nameof(capabilityId));
        return capabilityId;
    }
}
