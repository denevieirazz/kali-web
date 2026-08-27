using CloudOS.Host.Native;
using CloudOS.Installer;

namespace CloudOS.Host.Installer;

public sealed record InstallerContainedExecutionStart(
    bool Started,
    string? ErrorCode,
    string? Message,
    InstallerExecutionOwnership? Ownership,
    NativeContainedProcessLease? Lease)
{
    public static InstallerContainedExecutionStart Denied(string errorCode, string message) =>
        new(false, errorCode, message, null, null);

    public static InstallerContainedExecutionStart Running(
        InstallerExecutionOwnership ownership,
        NativeContainedProcessLease lease) =>
        new(
            true,
            null,
            null,
            ownership ?? throw new ArgumentNullException(nameof(ownership)),
            lease ?? throw new ArgumentNullException(nameof(lease)));
}

/// <summary>
/// Host-only transaction that consumes a one-shot installer capability and moves a
/// direct EXE into the same suspended/Job-contained launch boundary used by native
/// CloudOS applications. The caller installs HWND/process tracking while the root
/// process is still suspended; only then is ownership registered and Resume called.
/// Web content never supplies executable paths to this type.
/// </summary>
public sealed class InstallerContainedExecutionCoordinator
{
    private readonly Func<string, CancellationToken, Task<InstallerLaunchPlan>> _consumeCapability;
    private readonly Action<string> _completeCapability;
    private readonly InstallerExecutionOwnershipRegistry _ownership;

    public InstallerContainedExecutionCoordinator(
        Func<string, CancellationToken, Task<InstallerLaunchPlan>> consumeCapability,
        Action<string> completeCapability,
        InstallerExecutionOwnershipRegistry? ownership = null)
    {
        _consumeCapability = consumeCapability ?? throw new ArgumentNullException(nameof(consumeCapability));
        _completeCapability = completeCapability ?? throw new ArgumentNullException(nameof(completeCapability));
        _ownership = ownership ?? new InstallerExecutionOwnershipRegistry();
    }

    public InstallerExecutionOwnershipRegistry Ownership => _ownership;

    public async Task<InstallerContainedExecutionStart> StartAsync(
        string capabilityId,
        Action<NativeContainedProcessLease> installHostTrackingBeforeResume,
        CancellationToken cancellationToken = default)
    {
        InstallerBridgeContract.ValidateCapabilityId(capabilityId);
        ArgumentNullException.ThrowIfNull(installHostTrackingBeforeResume);

        var launchPlan = await _consumeCapability(capabilityId, cancellationToken);
        var admission = InstallerContainedLaunchPolicy.Evaluate(launchPlan);
        if (!admission.Allowed || admission.LaunchSpec is null)
        {
            CompleteCapabilityBestEffort(capabilityId);
            return InstallerContainedExecutionStart.Denied(
                admission.ErrorCode ?? InstallerContainedLaunchPolicy.UnsupportedCode,
                admission.Message ?? "The installer cannot enter the contained Windows runtime.");
        }

        NativeContainedProcessLease? lease = null;
        InstallerExecutionOwnership? ownership = null;
        try
        {
            lease = NativeContainedProcessLauncher.StartSuspended(admission.LaunchSpec);
            installHostTrackingBeforeResume(lease);

            // Ownership is installed before Resume so a process cannot execute between
            // Job admission and capability correlation.
            ownership = _ownership.Register(
                capabilityId,
                launchPlan.ArtifactId,
                lease.ProcessId);
            lease.Resume();
            return InstallerContainedExecutionStart.Running(ownership, lease);
        }
        catch
        {
            if (ownership is not null)
                _ownership.CompleteRoot(ownership.RootProcessId);
            if (lease is not null)
            {
                lease.TryTerminate(3_000, out _);
                lease.Dispose();
            }
            CompleteCapabilityBestEffort(capabilityId);
            throw;
        }
    }

    /// <summary>
    /// Completes staging only after the caller has independently observed that the
    /// containment Job is empty. This is intentionally keyed by Job root rather than
    /// Process.HasExited, because installers may spawn descendants before the root
    /// bootstrapper exits.
    /// </summary>
    public InstallerExecutionOwnership? CompleteRootAfterJobEmpty(int rootProcessId)
    {
        var ownership = _ownership.CompleteRoot(rootProcessId);
        if (ownership is null) return null;
        CompleteCapabilityBestEffort(ownership.CapabilityId);
        return ownership;
    }

    private void CompleteCapabilityBestEffort(string capabilityId)
    {
        try
        {
            _completeCapability(capabilityId);
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException
            or ObjectDisposedException or IOException or UnauthorizedAccessException)
        {
            // The capability has already been consumed or denied. Startup stale-staging
            // cleanup is the final recovery path if immediate cleanup cannot complete.
        }
    }
}
