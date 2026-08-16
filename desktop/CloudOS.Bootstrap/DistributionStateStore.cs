using System.Text.Json;

namespace CloudOS.Bootstrap;

public sealed class DistributionState
{
    public int SchemaVersion { get; init; } = 1;
    public string? CurrentVersion { get; set; }
    public string? PreviousVersion { get; set; }
    public string? PendingVersion { get; set; }
    public string? PendingSource { get; set; }
    public string? PendingChannel { get; set; }
    public string? HealthyVersion { get; set; }
    public DateTimeOffset? PreparedAtUtc { get; set; }
    public DateTimeOffset? HealthyAtUtc { get; set; }
}

public sealed class DistributionStateStore
{
    private readonly JsonSerializerOptions _json = new() { WriteIndented = true };
    public DistributionStateStore(string localRoot)
    {
        LocalRoot = Path.GetFullPath(localRoot);
        Directory.CreateDirectory(LocalRoot);
        StatePath = Path.Combine(LocalRoot, "distribution-state.json");
    }
    public string LocalRoot { get; }
    public string StatePath { get; }

    public DistributionState Load()
    {
        try
        {
            if (!File.Exists(StatePath)) return new DistributionState();
            var state = JsonSerializer.Deserialize<DistributionState>(File.ReadAllText(StatePath));
            return state is { SchemaVersion: 1 } ? state : new DistributionState();
        }
        catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException)
        {
            return new DistributionState();
        }
    }

    public void Save(DistributionState state)
    {
        var temp = $"{StatePath}.{Environment.ProcessId}.{Guid.NewGuid():N}.tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(state, _json));
        File.Move(temp, StatePath, true);
    }

    public void RecordPrepared(PreparedUpdate update)
    {
        var state = Load();
        var current = update.CurrentVersion;
        if (!string.IsNullOrWhiteSpace(current)) state.CurrentVersion = current;
        state.PreviousVersion = state.CurrentVersion;
        state.PendingVersion = update.Version;
        state.PendingSource = update.Source;
        state.PendingChannel = update.Channel;
        state.PreparedAtUtc = DateTimeOffset.UtcNow;
        Save(state);
    }

    public void MarkHealthy(string version)
    {
        var state = Load();
        if (!string.IsNullOrWhiteSpace(state.PendingVersion)) state.CurrentVersion = state.PendingVersion;
        else if (!string.IsNullOrWhiteSpace(version)) state.CurrentVersion = version;
        state.HealthyVersion = state.CurrentVersion;
        state.PendingVersion = null;
        state.PendingSource = null;
        state.PendingChannel = null;
        state.HealthyAtUtc = DateTimeOffset.UtcNow;
        Save(state);
    }

    public bool CanRollback()
    {
        var state = Load();
        return !string.IsNullOrWhiteSpace(state.PreviousVersion)
            && !string.IsNullOrWhiteSpace(state.PendingSource)
            && !string.IsNullOrWhiteSpace(state.PendingChannel);
    }
}
