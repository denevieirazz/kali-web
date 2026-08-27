using System.Text.Json.Serialization;
using CloudOS.Installer;

namespace CloudOS.Host.Installer;

public sealed record InstallerArtifactBridgeView(
    [property: JsonPropertyName("artifactId")] string ArtifactId,
    [property: JsonPropertyName("fileName")] string FileName,
    [property: JsonPropertyName("kind")] string Kind,
    [property: JsonPropertyName("sha256")] string Sha256,
    [property: JsonPropertyName("sizeBytes")] long SizeBytes,
    [property: JsonPropertyName("trust")] string Trust,
    [property: JsonPropertyName("publisher")] string? Publisher,
    [property: JsonPropertyName("registeredAtUtc")] DateTimeOffset RegisteredAtUtc,
    [property: JsonPropertyName("sourceDownloadId")] string? SourceDownloadId);

public sealed record InstallerArtifactListBridgeResponse(
    [property: JsonPropertyName("artifacts")] IReadOnlyList<InstallerArtifactBridgeView> Artifacts,
    [property: JsonPropertyName("elevationBrokerAvailable")] bool ElevationBrokerAvailable);

public sealed record InstallerReadinessBridgeView(
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("integrityValid")] bool IntegrityValid,
    [property: JsonPropertyName("trustValid")] bool TrustValid,
    [property: JsonPropertyName("canLaunchInUserSession")] bool CanLaunchInUserSession,
    [property: JsonPropertyName("elevatedBrokerAvailable")] bool ElevatedBrokerAvailable,
    [property: JsonPropertyName("reason")] string? Reason);

public sealed record InstallerPrepareBridgeResponse(
    [property: JsonPropertyName("artifact")] InstallerArtifactBridgeView Artifact,
    [property: JsonPropertyName("readiness")] InstallerReadinessBridgeView Readiness,
    [property: JsonPropertyName("capabilityId")] string? CapabilityId,
    [property: JsonPropertyName("expiresAtUtc")] DateTimeOffset? ExpiresAtUtc);

/// <summary>
/// Public WebView contract for installer discovery/preparation. It deliberately
/// omits launch-plan paths, argv, working directories and native log paths. Enum
/// values and JSON field names are projected explicitly so the protocol does not
/// depend on serializer defaults.
/// </summary>
public static class InstallerBridgeContract
{
    public static InstallerArtifactListBridgeResponse List(
        IReadOnlyList<InstallerArtifactPublicView> artifacts,
        bool elevationBrokerAvailable)
    {
        ArgumentNullException.ThrowIfNull(artifacts);
        return new InstallerArtifactListBridgeResponse(
            artifacts.Select(ToBridgeView).ToArray(),
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
            ToBridgeView(prepared.Artifact),
            new InstallerReadinessBridgeView(
                prepared.Readiness.Status.ToString(),
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

    private static InstallerArtifactBridgeView ToBridgeView(InstallerArtifactPublicView artifact) =>
        new(
            artifact.ArtifactId,
            artifact.FileName,
            artifact.Kind.ToString(),
            artifact.Sha256,
            artifact.SizeBytes,
            artifact.Trust.ToString(),
            artifact.Publisher,
            artifact.RegisteredAtUtc,
            artifact.SourceDownloadId);
}
