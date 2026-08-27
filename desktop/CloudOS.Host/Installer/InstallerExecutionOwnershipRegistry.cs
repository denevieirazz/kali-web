namespace CloudOS.Host.Installer;

public sealed record InstallerExecutionOwnership(
    string CapabilityId,
    string ArtifactId,
    int RootProcessId,
    DateTimeOffset StartedAtUtc);

/// <summary>
/// Host-only correlation between an already-consumed installer capability and the
/// root PID of the CloudOS containment Job that owns its process tree. Completion
/// is keyed by Job root, not by the bootstrapper's Process.HasExited state, so a
/// descendant can never outlive capability cleanup unnoticed.
/// </summary>
public sealed class InstallerExecutionOwnershipRegistry
{
    private readonly object _sync = new();
    private readonly Dictionary<int, InstallerExecutionOwnership> _byRootProcessId = new();
    private readonly Dictionary<string, int> _rootByCapabilityId = new(StringComparer.Ordinal);
    private readonly HashSet<string> _retiredCapabilityIds = new(StringComparer.Ordinal);

    public InstallerExecutionOwnership Register(
        string capabilityId,
        string artifactId,
        int rootProcessId,
        DateTimeOffset? startedAtUtc = null)
    {
        InstallerBridgeContract.ValidateCapabilityId(capabilityId);
        InstallerBridgeContract.ValidateArtifactId(artifactId);
        if (rootProcessId <= 0) throw new ArgumentOutOfRangeException(nameof(rootProcessId));

        var ownership = new InstallerExecutionOwnership(
            capabilityId,
            artifactId,
            rootProcessId,
            startedAtUtc ?? DateTimeOffset.UtcNow);

        lock (_sync)
        {
            if (_byRootProcessId.ContainsKey(rootProcessId))
                throw new InvalidOperationException("The containment Job root already owns an installer capability.");
            if (_rootByCapabilityId.ContainsKey(capabilityId) || _retiredCapabilityIds.Contains(capabilityId))
                throw new InvalidOperationException("The installer capability is already active or retired in this Host session.");

            _byRootProcessId.Add(rootProcessId, ownership);
            _rootByCapabilityId.Add(capabilityId, rootProcessId);
            return ownership;
        }
    }

    public bool TryGetByRootProcessId(int rootProcessId, out InstallerExecutionOwnership? ownership)
    {
        lock (_sync) return _byRootProcessId.TryGetValue(rootProcessId, out ownership);
    }

    public bool TryGetByCapabilityId(string capabilityId, out InstallerExecutionOwnership? ownership)
    {
        ownership = null;
        if (string.IsNullOrWhiteSpace(capabilityId)) return false;
        lock (_sync)
        {
            if (!_rootByCapabilityId.TryGetValue(capabilityId, out var rootProcessId)) return false;
            return _byRootProcessId.TryGetValue(rootProcessId, out ownership);
        }
    }

    /// <summary>
    /// Removes ownership only after the caller has independently proven that the
    /// containment Job is empty. The returned capability becomes retired for the
    /// remainder of the Host session and is then eligible for staging cleanup and
    /// post-install catalog rescan.
    /// </summary>
    public InstallerExecutionOwnership? CompleteRoot(int rootProcessId)
    {
        lock (_sync)
        {
            if (!_byRootProcessId.Remove(rootProcessId, out var ownership)) return null;
            _rootByCapabilityId.Remove(ownership.CapabilityId);
            _retiredCapabilityIds.Add(ownership.CapabilityId);
            return ownership;
        }
    }

    public IReadOnlyList<InstallerExecutionOwnership> Snapshot()
    {
        lock (_sync) return _byRootProcessId.Values.OrderBy(item => item.RootProcessId).ToArray();
    }
}
