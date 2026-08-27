using CloudOS.Host.Installer;
using CloudOS.Host.Native;
using CloudOS.Installer;

internal static class CloudOsInstallerManagerContainedGate
{
    internal static async Task RunAsync()
    {
        var root = Path.Combine(Path.GetTempPath(), $"cloudos-installer-host-gate-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            using var manager = new CloudOsInstallerManager(root);
            var systemNotepad = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "System32",
                "notepad.exe");
            Require(File.Exists(systemNotepad), "Windows notepad fixture is unavailable");

            var managedArtifactPath = InstallerStorageLayout.CreateUniqueDownloadPath(
                manager.ManagedDownloadsRoot,
                "host-gate-notepad.exe");
            File.Copy(systemNotepad, managedArtifactPath, overwrite: false);

            var artifact = await manager.RegisterDownloadedInstallerAsync(
                managedArtifactPath,
                "host-contained-gate");
            Require(artifact.Kind == InstallerArtifactKind.WindowsExecutable,
                "Host gate fixture was not cataloged as a Windows executable");

            var prepared = await manager.PrepareAsync(
                artifact.ArtifactId,
                allowUntrusted: true);
            Require(prepared.Readiness.Status == InstallerReadinessStatus.Ready,
                $"Host gate fixture did not become ready: {prepared.Readiness.Status}");
            var capabilityId = prepared.Capability.CapabilityId;
            Require(capabilityId.Length == 64, "Host gate did not receive a one-shot capability");

            var stagingDirectory = Path.Combine(
                InstallerStorageLayout.StagingRoot(root),
                capabilityId);
            Require(Directory.Exists(stagingDirectory), "prepared Host capability has no staging directory");

            var callbackObservedSuspendedRoot = false;
            var started = await manager.StartContainedAsync(
                capabilityId,
                lease =>
                {
                    Require(!lease.IsResumed, "Host authority tracking callback ran after Resume");
                    Require(lease.GetMemberProcessIds().Contains(lease.ProcessId),
                        "Host authority root was not inside its Job before Resume");
                    callbackObservedSuspendedRoot = true;
                });

            Require(started.Started, $"Host authority denied contained EXE: {started.ErrorCode}");
            Require(callbackObservedSuspendedRoot, "Host authority never installed pre-Resume tracking");
            var lease = started.Lease
                ?? throw new InvalidOperationException("Host authority did not return its contained Job lease");
            try
            {
                Require(lease.IsResumed, "Host authority did not resume the contained installer root");
                var active = manager.ListActiveContainedExecutions();
                Require(active.Count == 1, "Host authority did not expose exactly one active contained execution");
                Require(active[0].CapabilityId == capabilityId, "Host authority ownership lost the capability ID");
                Require(active[0].ArtifactId == artifact.ArtifactId, "Host authority ownership lost the artifact ID");
                Require(active[0].RootProcessId == lease.ProcessId, "Host authority ownership is not Job-rooted");

                Require(lease.TryTerminate(5_000, out var terminationError),
                    $"Host authority fixture Job did not terminate: {terminationError}");
                Require(lease.GetMemberProcessIds().Count == 0,
                    "Host authority fixture Job was not empty after termination");

                var completed = manager.CompleteContainedRootAfterJobEmpty(lease.ProcessId);
                Require(completed?.CapabilityId == capabilityId,
                    "Host authority did not retire capability ownership when the Job became empty");
                Require(manager.ListActiveContainedExecutions().Count == 0,
                    "Host authority retained installer ownership after Job completion");
                Require(!Directory.Exists(stagingDirectory),
                    "Host authority retained capability staging after Job completion");
                Require(manager.CompleteContainedRootAfterJobEmpty(lease.ProcessId) is null,
                    "Host authority completed the same Job root more than once");
            }
            finally
            {
                lease.Dispose();
            }
        }
        finally
        {
            DeleteTreeBestEffort(root);
        }
    }

    private static void DeleteTreeBestEffort(string root)
    {
        try
        {
            if (!Directory.Exists(root)) return;
            foreach (var file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
            {
                try { File.SetAttributes(file, FileAttributes.Normal); } catch { }
            }
            Directory.Delete(root, recursive: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
        }
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
