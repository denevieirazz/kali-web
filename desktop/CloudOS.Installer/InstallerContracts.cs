namespace CloudOS.Installer;

public enum InstallerArtifactKind
{
    WindowsExecutable,
    WindowsInstallerPackage,
    MsixPackage,
    AppxPackage,
    Unsupported
}

public enum InstallerTrustStatus
{
    Trusted,
    Unsigned,
    Untrusted,
    VerificationUnavailable
}

public enum InstallerReadinessStatus
{
    Ready,
    UnsupportedFormat,
    ArtifactMissing,
    ArtifactChanged,
    BrokerRequired,
    BlockedByPolicy
}

public sealed record InstallerArtifactInspection(
    InstallerArtifactKind Kind,
    string Sha256,
    long SizeBytes,
    DateTimeOffset LastWriteTimeUtc,
    InstallerTrustStatus Trust,
    string? Publisher,
    int TrustNativeStatus);

public sealed record InstallerArtifactRecord(
    string ArtifactId,
    string FileName,
    string CanonicalPath,
    InstallerArtifactKind Kind,
    string Sha256,
    long SizeBytes,
    DateTimeOffset LastWriteTimeUtc,
    InstallerTrustStatus Trust,
    string? Publisher,
    DateTimeOffset RegisteredAtUtc,
    string? SourceDownloadId)
{
    public InstallerArtifactPublicView ToPublicView() => new(
        ArtifactId,
        FileName,
        Kind,
        Sha256,
        SizeBytes,
        Trust,
        Publisher,
        RegisteredAtUtc,
        SourceDownloadId);
}

public sealed record InstallerArtifactPublicView(
    string ArtifactId,
    string FileName,
    InstallerArtifactKind Kind,
    string Sha256,
    long SizeBytes,
    InstallerTrustStatus Trust,
    string? Publisher,
    DateTimeOffset RegisteredAtUtc,
    string? SourceDownloadId);

public sealed record InstallerCapability(
    string CapabilityId,
    string ArtifactId,
    DateTimeOffset IssuedAtUtc,
    DateTimeOffset ExpiresAtUtc,
    string ExpectedSha256);

public sealed record InstallerLaunchPlan(
    string ArtifactId,
    InstallerArtifactKind Kind,
    string ExecutablePath,
    IReadOnlyList<string> Arguments,
    string WorkingDirectory,
    string? LogPath,
    bool MayRequireElevation,
    bool ElevatedBrokerRequired,
    string ExpectedSha256)
{
    public InstallerLaunchPlan Validate()
    {
        if (string.IsNullOrWhiteSpace(ArtifactId)) throw new ArgumentException("Artifact ID is required.", nameof(ArtifactId));
        if (!Path.IsPathFullyQualified(ExecutablePath)) throw new ArgumentException("Executable path must be absolute.", nameof(ExecutablePath));
        if (!Path.IsPathFullyQualified(WorkingDirectory)) throw new ArgumentException("Working directory must be absolute.", nameof(WorkingDirectory));
        if (Arguments is null) throw new ArgumentNullException(nameof(Arguments));
        if (Arguments.Count > 16) throw new ArgumentOutOfRangeException(nameof(Arguments));
        if (Arguments.Any(argument => argument is null || argument.Length > 32768)) throw new ArgumentException("Installer argument vector is invalid.", nameof(Arguments));
        if (ExpectedSha256.Length != 64 || ExpectedSha256.Any(character => !Uri.IsHexDigit(character)))
            throw new ArgumentException("Expected SHA-256 is invalid.", nameof(ExpectedSha256));
        return this;
    }
}

public sealed record InstallerReadiness(
    InstallerReadinessStatus Status,
    InstallerArtifactPublicView Artifact,
    bool IntegrityValid,
    bool TrustValid,
    bool CanLaunchInUserSession,
    bool ElevatedBrokerAvailable,
    string? Reason);
