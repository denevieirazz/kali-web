using System.Runtime.CompilerServices;
using CloudOS.Host.Installer;

internal static class InstallerExecutionOwnershipGate
{
    [ModuleInitializer]
    internal static void Run()
    {
        var registry = new InstallerExecutionOwnershipRegistry();
        var capabilityA = new string('a', 64);
        var capabilityB = new string('b', 64);
        var artifactA = new string('c', 32);
        var artifactB = new string('d', 32);
        var startedAt = DateTimeOffset.Parse("2026-08-27T00:00:00+00:00");

        var first = registry.Register(capabilityA, artifactA, 4100, startedAt);
        Require(first.RootProcessId == 4100, "ownership lost Job root PID");
        Require(first.CapabilityId == capabilityA, "ownership lost capability ID");
        Require(first.ArtifactId == artifactA, "ownership lost artifact ID");
        Require(first.StartedAtUtc == startedAt, "ownership changed start timestamp");

        Require(registry.TryGetByRootProcessId(4100, out var byRoot) && byRoot == first,
            "ownership lookup by Job root failed");
        Require(registry.TryGetByCapabilityId(capabilityA, out var byCapability) && byCapability == first,
            "ownership lookup by capability failed");
        Require(registry.Snapshot().Count == 1, "ownership snapshot did not contain exactly one active Job");

        RequireThrows<InvalidOperationException>(() => registry.Register(capabilityB, artifactB, 4100),
            "duplicate Job root was accepted");
        RequireThrows<InvalidOperationException>(() => registry.Register(capabilityA, artifactB, 4200),
            "duplicate active capability was accepted");
        RequireThrows<ArgumentException>(() => registry.Register("../escape", artifactA, 4300),
            "invalid capability ID was accepted");
        RequireThrows<ArgumentException>(() => registry.Register(capabilityB, "../escape", 4300),
            "invalid artifact ID was accepted");
        RequireThrows<ArgumentOutOfRangeException>(() => registry.Register(capabilityB, artifactB, 0),
            "invalid Job root PID was accepted");

        var completed = registry.CompleteRoot(4100);
        Require(completed == first, "Job completion did not return its installer ownership");
        Require(registry.CompleteRoot(4100) is null, "Job completion was not one-shot");
        Require(!registry.TryGetByRootProcessId(4100, out _), "completed Job ownership remained active");
        Require(!registry.TryGetByCapabilityId(capabilityA, out _), "completed capability remained active");
        Require(registry.Snapshot().Count == 0, "completed ownership remained in snapshot");
        RequireThrows<InvalidOperationException>(() => registry.Register(capabilityA, artifactA, 4400),
            "retired capability was resurrected on a new Job root");

        var second = registry.Register(capabilityB, artifactB, 4500);
        Require(second.RootProcessId == 4500, "independent capability could not register after prior completion");

        Console.WriteLine("PASS: installer capability ownership is Job-rooted and one-shot");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private static void RequireThrows<T>(Action action, string message) where T : Exception
    {
        try
        {
            action();
        }
        catch (T)
        {
            return;
        }
        throw new InvalidOperationException(message);
    }
}
