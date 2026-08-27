using CloudOS.Host.Installer;
using CloudOS.Installer;

internal static class InstallerContainedExecutionCoordinatorGate
{
    internal const string FixtureArgument = "--installer-contained-fixture-wait";

    internal static async Task RunAsync()
    {
        var executable = Environment.ProcessPath
            ?? throw new InvalidOperationException("Installer execution fixture apphost is unavailable.");
        var workingDirectory = Path.GetDirectoryName(executable)
            ?? throw new InvalidOperationException("Installer execution fixture directory is unavailable.");
        var capabilityId = new string('c', 64);
        var artifactId = new string('d', 32);
        var plan = new InstallerLaunchPlan(
            artifactId,
            InstallerArtifactKind.WindowsExecutable,
            executable,
            new[] { FixtureArgument },
            workingDirectory,
            null,
            MayRequireElevation: true,
            ElevatedBrokerRequired: false,
            new string('e', 64));

        var completed = new List<string>();
        var coordinator = new InstallerContainedExecutionCoordinator(
            (id, _) => Task.FromResult(id == capabilityId
                ? plan
                : throw new InvalidOperationException("Coordinator consumed the wrong capability.")),
            id => completed.Add(id));

        var trackingObservedSuspendedRoot = false;
        var started = await coordinator.StartAsync(
            capabilityId,
            lease =>
            {
                Require(!lease.IsResumed, "Host tracking callback ran after the installer root resumed");
                Require(lease.GetMemberProcessIds().Contains(lease.ProcessId), "suspended installer root was not inside its Job");
                trackingObservedSuspendedRoot = true;
            });

        Require(started.Started, $"contained installer fixture was denied: {started.ErrorCode}");
        Require(trackingObservedSuspendedRoot, "Host tracking callback was not invoked");
        var lease = started.Lease ?? throw new InvalidOperationException("started installer did not return its Job lease");
        Require(lease.IsResumed, "installer root did not resume after Host tracking and ownership registration");
        Require(started.Ownership?.RootProcessId == lease.ProcessId, "installer ownership is not keyed by the Job root");
        Require(coordinator.Ownership.TryGetByCapabilityId(capabilityId, out var active) && active is not null,
            "active installer capability is missing from Job ownership registry");

        try
        {
            Require(lease.TryTerminate(5_000, out var terminationError),
                $"installer fixture Job did not terminate: {terminationError}");
            Require(lease.GetMemberProcessIds().Count == 0, "installer fixture Job was not empty after termination");
            var retired = coordinator.CompleteRootAfterJobEmpty(lease.ProcessId);
            Require(retired?.CapabilityId == capabilityId, "Job completion did not retire the installer capability");
            Require(completed.SequenceEqual(new[] { capabilityId }), "installer staging completion was not emitted exactly once");
            Require(!coordinator.Ownership.TryGetByCapabilityId(capabilityId, out _), "retired capability remained active");
            Require(coordinator.CompleteRootAfterJobEmpty(lease.ProcessId) is null, "Job root completed more than once");
        }
        finally
        {
            lease.Dispose();
        }

        await RunTrackingFailureRollbackAsync(plan, capabilityId);
        await RunDeniedPlanCleanupAsync(executable, workingDirectory);
    }

    private static async Task RunTrackingFailureRollbackAsync(
        InstallerLaunchPlan plan,
        string capabilityId)
    {
        var completed = new List<string>();
        var coordinator = new InstallerContainedExecutionCoordinator(
            (_, _) => Task.FromResult(plan),
            id => completed.Add(id));

        try
        {
            await coordinator.StartAsync(
                capabilityId,
                lease =>
                {
                    Require(!lease.IsResumed, "rollback fixture resumed before failing Host tracking");
                    throw new InvalidOperationException("fixture tracking failure");
                });
            throw new InvalidOperationException("tracking failure did not abort installer execution");
        }
        catch (InvalidOperationException error) when (error.Message == "fixture tracking failure")
        {
        }

        Require(completed.SequenceEqual(new[] { capabilityId }), "tracking failure did not clean consumed capability staging");
        Require(coordinator.Ownership.Snapshot().Count == 0, "tracking failure left installer ownership registered");
    }

    private static async Task RunDeniedPlanCleanupAsync(
        string executable,
        string workingDirectory)
    {
        var capabilityId = new string('f', 64);
        var plan = new InstallerLaunchPlan(
            new string('a', 32),
            InstallerArtifactKind.WindowsInstallerPackage,
            executable,
            Array.Empty<string>(),
            workingDirectory,
            null,
            MayRequireElevation: true,
            ElevatedBrokerRequired: false,
            new string('b', 64));
        var completed = new List<string>();
        var coordinator = new InstallerContainedExecutionCoordinator(
            (_, _) => Task.FromResult(plan),
            id => completed.Add(id));

        var trackingCalled = false;
        var denied = await coordinator.StartAsync(capabilityId, _ => trackingCalled = true);
        Require(!denied.Started, "broker-only MSI plan entered direct contained execution");
        Require(denied.ErrorCode == InstallerContainedLaunchPolicy.BrokerRequiredCode, "denied MSI returned the wrong error code");
        Require(!trackingCalled, "Host tracking ran for a denied installer plan");
        Require(completed.SequenceEqual(new[] { capabilityId }), "denied installer capability staging was not cleaned");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
