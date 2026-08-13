using CloudOS.Bootstrap;

var tests = new (string Name, Action Run)[]
{
    ("three recent failures enter recovery", ThreeFailuresEnterRecovery),
    ("old and future failures are ignored", InvalidTimestampsAreIgnored),
    ("stable host resets crash loop", StableHostResetsFailures),
    ("restart delay is bounded", RestartDelayIsBounded),
    ("preview clean-exit flag is explicit and not forwarded", PreviewFlagIsExplicit),
    ("state store persists and quarantines corrupt JSON", StateStoreRoundTripAndRecovery)
};

foreach (var test in tests)
{
    test.Run();
    Console.WriteLine($"PASS {test.Name}");
}

static void ThreeFailuresEnterRecovery()
{
    var now = DateTimeOffset.Parse("2026-08-12T20:00:00Z");
    var policy = new CrashLoopPolicy();
    var state = new BootstrapState();
    state = policy.RecordFailure(state, now - TimeSpan.FromSeconds(50), 1, "one");
    state = policy.RecordFailure(state, now - TimeSpan.FromSeconds(20), 1, "two");
    Assert(!policy.ShouldEnterRecovery(state, now), "Two failures must still allow a bounded restart.");
    state = policy.RecordFailure(state, now, 1, "three");
    Assert(policy.ShouldEnterRecovery(state, now), "Three recent failures must enter recovery.");
}

static void InvalidTimestampsAreIgnored()
{
    var now = DateTimeOffset.Parse("2026-08-12T20:00:00Z");
    var policy = new CrashLoopPolicy();
    var state = new BootstrapState
    {
        FailureTimesUtc = new[]
        {
            now - TimeSpan.FromMinutes(10),
            now + TimeSpan.FromMinutes(5),
            now - TimeSpan.FromSeconds(30)
        }
    };
    Assert(!policy.ShouldEnterRecovery(state, now), "Stale or implausibly future timestamps cannot trigger recovery.");
}

static void StableHostResetsFailures()
{
    var now = DateTimeOffset.Parse("2026-08-12T20:00:00Z");
    var policy = new CrashLoopPolicy();
    var failed = new BootstrapState { FailureTimesUtc = new[] { now, now, now } };
    var stable = policy.RecordStable(failed, now);
    Assert(stable.FailureTimesUtc.Count == 0, "Stable readiness must clear failures.");
    Assert(stable.LastStableAtUtc == now, "Stable timestamp must be recorded.");
}

static void RestartDelayIsBounded()
{
    var now = DateTimeOffset.Parse("2026-08-12T20:00:00Z");
    var policy = new CrashLoopPolicy(failureThreshold: 10);
    var state = new BootstrapState();
    for (var index = 0; index < 9; index++) state = policy.RecordFailure(state, now, 1, "failure");
    var delay = policy.RestartDelay(state, now);
    Assert(delay >= TimeSpan.FromSeconds(1) && delay <= TimeSpan.FromSeconds(8), "Backoff must stay bounded.");
}

static void PreviewFlagIsExplicit()
{
    var root = Path.Combine(Path.GetTempPath(), $"cloudos-bootstrap-options-{Guid.NewGuid():N}");
    Directory.CreateDirectory(root);
    var host = Path.Combine(root, "CloudOS.Host.exe");
    try
    {
        File.WriteAllBytes(host, Array.Empty<byte>());
        var preview = BootstrapOptions.Parse(new[] { "--preview", "--host", host, "--fullscreen" });
        Assert(preview.AllowEarlyCleanExit, "Only an explicit preview may accept an early clean exit.");
        Assert(!preview.HostArguments.Contains("--preview"), "The preview policy flag must not reach CloudOS.Host.");
        var candidate = BootstrapOptions.Parse(new[] { "--host", host, "--fullscreen" });
        Assert(!candidate.AllowEarlyCleanExit, "A shell candidate must treat an early exit as a failure.");
    }
    finally
    {
        try { Directory.Delete(root, recursive: true); } catch (IOException) { }
    }
}

static void StateStoreRoundTripAndRecovery()
{
    var root = Path.Combine(Path.GetTempPath(), $"cloudos-bootstrap-tests-{Guid.NewGuid():N}");
    try
    {
        var store = new BootStateStore(root);
        var timestamp = DateTimeOffset.Parse("2026-08-12T20:00:00Z");
        store.Save(new BootstrapState { LastFailure = "test", FailureTimesUtc = new[] { timestamp } });
        var loaded = store.Load();
        Assert(loaded.LastFailure == "test" && loaded.FailureTimesUtc.SequenceEqual(new[] { timestamp }), "State must round-trip.");

        File.WriteAllText(store.StatePath, "{not-json");
        var recovered = store.Load();
        Assert(recovered.FailureTimesUtc.Count == 0, "Corrupt state must fall back to a clean state.");
        Assert(Directory.EnumerateFiles(root, "bootstrap-state.json.corrupt-*").Any(), "Corrupt state must be quarantined.");
    }
    finally
    {
        try { Directory.Delete(root, recursive: true); } catch (IOException) { }
    }
}

static void Assert(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
