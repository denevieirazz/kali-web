namespace CloudOS.Installer;

public sealed record InstallerBrokerRequest(
    string CapabilityId,
    string ArtifactId,
    string ExpectedSha256,
    InstallerArtifactKind Kind,
    IReadOnlyList<string> Arguments);

public sealed record InstallerBrokerResult(
    bool Accepted,
    string Status,
    int? ProcessId,
    string? Failure);

public interface IInstallerElevationBroker
{
    bool IsAvailable { get; }
    Task<InstallerBrokerResult> StartElevatedAsync(
        InstallerBrokerRequest request,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Product default until a separately installed and authenticated privileged CloudOS service
/// is present. This class intentionally does not call ShellExecute("runas"), PowerShell,
/// scheduled tasks, services.exe, or any other elevation workaround. Elevated installation
/// must fail closed instead of escaping to the Windows secure desktop or exposing arbitrary
/// administrator execution to web content.
/// </summary>
public sealed class UnavailableInstallerElevationBroker : IInstallerElevationBroker
{
    public bool IsAvailable => false;

    public Task<InstallerBrokerResult> StartElevatedAsync(
        InstallerBrokerRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(new InstallerBrokerResult(
            Accepted: false,
            Status: "ELEVATION_BROKER_UNAVAILABLE",
            ProcessId: null,
            Failure: "CloudOS privileged installer broker is not installed or authorized."));
    }
}
