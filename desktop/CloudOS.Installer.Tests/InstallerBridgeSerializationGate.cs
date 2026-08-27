using System.Runtime.CompilerServices;
using System.Text.Json;
using CloudOS.Host.Installer;
using CloudOS.Installer;

internal static class InstallerBridgeSerializationGate
{
    [ModuleInitializer]
    internal static void Run()
    {
        var artifact = new InstallerArtifactPublicView(
            new string('a', 32),
            "fixture.exe",
            InstallerArtifactKind.WindowsExecutable,
            new string('b', 64),
            1234,
            InstallerTrustStatus.Unsigned,
            null,
            DateTimeOffset.Parse("2026-08-27T00:00:00+00:00"),
            "download-fixture");

        var capability = new InstallerCapability(
            new string('c', 64),
            artifact.ArtifactId,
            DateTimeOffset.Parse("2026-08-27T00:00:00+00:00"),
            DateTimeOffset.Parse("2026-08-27T00:05:00+00:00"),
            artifact.Sha256);

        var nativeSentinel = @"C:\CloudOS\Installer\Staging\secret\fixture.exe";
        var launchPlan = new InstallerLaunchPlan(
            artifact.ArtifactId,
            InstallerArtifactKind.WindowsExecutable,
            nativeSentinel,
            new[] { "--secret-argument" },
            @"C:\CloudOS\Installer\Staging\secret",
            @"C:\CloudOS\Installer\Logs\secret.log",
            MayRequireElevation: true,
            ElevatedBrokerRequired: false,
            artifact.Sha256);

        var prepared = new PreparedInstallerCapability(
            capability,
            artifact,
            launchPlan,
            new InstallerReadiness(
                InstallerReadinessStatus.Ready,
                artifact,
                IntegrityValid: true,
                TrustValid: false,
                CanLaunchInUserSession: true,
                ElevatedBrokerAvailable: false,
                Reason: "User explicitly confirmed an installer whose publisher trust is not verified."));

        var response = InstallerBridgeContract.Prepare(prepared);
        var json = JsonSerializer.Serialize(response);

        Require(json.Contains("\"artifactId\"", StringComparison.Ordinal), "bridge artifactId is not camelCase");
        Require(json.Contains("\"kind\":\"WindowsExecutable\"", StringComparison.Ordinal), "bridge kind is not a stable enum name");
        Require(json.Contains("\"trust\":\"Unsigned\"", StringComparison.Ordinal), "bridge trust is not a stable enum name");
        Require(json.Contains("\"status\":\"Ready\"", StringComparison.Ordinal), "bridge readiness status is not a stable enum name");
        Require(json.Contains($"\"capabilityId\":\"{capability.CapabilityId}\"", StringComparison.Ordinal), "ready bridge response lost opaque capability ID");

        foreach (var forbidden in new[]
        {
            nativeSentinel,
            "ExecutablePath",
            "executablePath",
            "Arguments",
            "arguments",
            "WorkingDirectory",
            "workingDirectory",
            "LogPath",
            "logPath",
            "--secret-argument"
        })
        {
            Require(!json.Contains(forbidden, StringComparison.Ordinal), $"bridge response leaked native launch detail '{forbidden}'");
        }

        Console.WriteLine("PASS: installer bridge response is pathless and protocol-stable");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
