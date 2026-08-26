namespace CloudOS.Bootstrap;

public sealed record BootstrapState
{
    public int SchemaVersion { get; init; } = 1;
    public IReadOnlyList<DateTimeOffset> FailureTimesUtc { get; init; } = Array.Empty<DateTimeOffset>();
    public DateTimeOffset? LastReadyAtUtc { get; init; }
    public DateTimeOffset? LastStableAtUtc { get; init; }
    public DateTimeOffset? LastCleanExitAtUtc { get; init; }
    public int? LastExitCode { get; init; }
    public string? LastFailure { get; init; }
}
