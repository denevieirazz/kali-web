namespace CloudOS.Bootstrap;

public sealed class CrashLoopPolicy
{
    public CrashLoopPolicy(int failureThreshold = 3, TimeSpan? failureWindow = null)
    {
        if (failureThreshold is < 2 or > 10) throw new ArgumentOutOfRangeException(nameof(failureThreshold));
        FailureThreshold = failureThreshold;
        FailureWindow = failureWindow ?? TimeSpan.FromMinutes(2);
        if (FailureWindow < TimeSpan.FromSeconds(10) || FailureWindow > TimeSpan.FromHours(1))
            throw new ArgumentOutOfRangeException(nameof(failureWindow));
    }

    public int FailureThreshold { get; }
    public TimeSpan FailureWindow { get; }

    public bool ShouldEnterRecovery(BootstrapState state, DateTimeOffset now) =>
        RecentFailures(state, now).Count >= FailureThreshold;

    public BootstrapState RecordReady(BootstrapState state, DateTimeOffset now) =>
        Prune(state, now) with { LastReadyAtUtc = now };

    public BootstrapState RecordStable(BootstrapState state, DateTimeOffset now) =>
        state with
        {
            FailureTimesUtc = Array.Empty<DateTimeOffset>(),
            LastStableAtUtc = now,
            LastFailure = null,
            LastExitCode = null
        };

    public BootstrapState RecordCleanExit(BootstrapState state, DateTimeOffset now, int exitCode) =>
        state with
        {
            FailureTimesUtc = Array.Empty<DateTimeOffset>(),
            LastCleanExitAtUtc = now,
            LastFailure = null,
            LastExitCode = exitCode
        };

    public BootstrapState RecordFailure(
        BootstrapState state,
        DateTimeOffset now,
        int? exitCode,
        string reason)
    {
        var recent = RecentFailures(state, now);
        recent.Add(now);
        return state with
        {
            FailureTimesUtc = recent,
            LastExitCode = exitCode,
            LastFailure = string.IsNullOrWhiteSpace(reason) ? "Falha inesperada do host." : reason
        };
    }

    public TimeSpan RestartDelay(BootstrapState state, DateTimeOffset now)
    {
        var count = RecentFailures(state, now).Count;
        var exponent = Math.Min(Math.Max(0, count - 1), 3);
        return TimeSpan.FromSeconds(Math.Min(8, 1 << exponent));
    }

    private BootstrapState Prune(BootstrapState state, DateTimeOffset now) =>
        state with { FailureTimesUtc = RecentFailures(state, now) };

    private List<DateTimeOffset> RecentFailures(BootstrapState state, DateTimeOffset now)
    {
        var earliest = now - FailureWindow;
        return state.FailureTimesUtc
            .Where(timestamp => timestamp >= earliest && timestamp <= now + TimeSpan.FromMinutes(1))
            .OrderBy(timestamp => timestamp)
            .ToList();
    }
}
