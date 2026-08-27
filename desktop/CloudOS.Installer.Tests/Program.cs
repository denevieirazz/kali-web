using CloudOS.Installer;

var tests = new (string Name, Func<Task> Run)[]
{
    ("managed path rejects escape", TestManagedPathEscapeAsync),
    ("catalog registers installer and persists opaque metadata", TestCatalogPersistenceAsync),
    ("artifact mutation blocks capability", TestArtifactMutationAsync),
    ("untrusted installer requires explicit approval", TestUntrustedApprovalAsync),
    ("capability stages exact hash and is one shot", TestCapabilityOneShotAsync),
    ("capability cleanup rejects invalid ids", TestCapabilityCleanupIdAsync),
    ("unsupported format is rejected", TestUnsupportedFormatAsync),
    ("msi plan uses msiexec without forced restart", TestMsiPlanAsync),
    ("elevation broker fails closed", TestElevationBrokerAsync),
};

var failures = new List<string>();
foreach (var test in tests)
{
    try
    {
        await test.Run();
        Console.WriteLine($"PASS: {test.Name}");
    }
    catch (Exception error)
    {
        var message = $"{test.Name}: {error.GetType().Name}: {error.Message}";
        failures.Add(message);
        Console.Error.WriteLine($"FAIL: {message}");
    }
}

if (failures.Count > 0)
{
    Console.Error.WriteLine($"INSTALLER_CONTRACT_TESTS=FAIL count={failures.Count}");
    return 1;
}

Console.WriteLine($"INSTALLER_CONTRACT_TESTS=PASS count={tests.Length}");
return 0;

static Task TestManagedPathEscapeAsync()
{
    using var env = TestEnvironment.Create();
    var outside = Path.Combine(env.Root, "outside.exe");
    File.WriteAllText(outside, "outside");
    RequireThrows<UnauthorizedAccessException>(() =>
        InstallerStorageLayout.NormalizeManagedDownloadPath(env.Downloads, outside));
    return Task.CompletedTask;
}

static async Task TestCatalogPersistenceAsync()
{
    using var env = TestEnvironment.Create();
    var path = Path.Combine(env.Downloads, "setup.exe");
    await File.WriteAllTextAsync(path, "cloudos-installer-fixture-v1");

    var catalog = env.CreateCatalog();
    var registered = await catalog.RegisterManagedDownloadAsync(path, "download-fixture-1");
    Require(registered.ArtifactId.Length == 32, "artifact ID is not opaque GUID form");
    Require(registered.Kind == InstallerArtifactKind.WindowsExecutable, "wrong executable kind");
    Require(registered.Sha256.Length == 64, "missing SHA-256");
    Require(registered.SourceDownloadId == "download-fixture-1", "download correlation lost");

    var reloaded = env.CreateCatalog();
    var items = await reloaded.ListAsync();
    Require(items.Count == 1, "catalog did not persist exactly one artifact");
    Require(items[0].ArtifactId == registered.ArtifactId, "artifact ID changed after reload");
    Require(items[0].Sha256 == registered.Sha256, "artifact hash changed after reload");
}

static async Task TestArtifactMutationAsync()
{
    using var env = TestEnvironment.Create();
    var path = Path.Combine(env.Downloads, "mutating.exe");
    await File.WriteAllTextAsync(path, "original");
    var catalog = env.CreateCatalog();
    var artifact = await catalog.RegisterManagedDownloadAsync(path);
    await File.AppendAllTextAsync(path, "-changed");

    using var capabilities = env.CreateCapabilities(catalog);
    var prepared = await capabilities.PrepareAsync(
        artifact.ArtifactId,
        elevatedBrokerAvailable: false,
        allowUntrusted: false);
    Require(prepared.Readiness.Status == InstallerReadinessStatus.ArtifactChanged, "mutated artifact was not blocked");
    Require(!prepared.Readiness.IntegrityValid, "mutated artifact was reported integral");
    Require(string.IsNullOrEmpty(prepared.Capability.CapabilityId), "mutated artifact received capability");
}

static async Task TestUntrustedApprovalAsync()
{
    using var env = TestEnvironment.Create();
    var path = Path.Combine(env.Downloads, "unsigned.exe");
    await File.WriteAllTextAsync(path, "unsigned-fixture");
    var catalog = env.CreateCatalog();
    var artifact = await catalog.RegisterManagedDownloadAsync(path);
    Require(artifact.Trust != InstallerTrustStatus.Trusted, "unsigned fixture unexpectedly trusted");

    using var capabilities = env.CreateCapabilities(catalog);
    var blocked = await capabilities.PrepareAsync(
        artifact.ArtifactId,
        elevatedBrokerAvailable: false,
        allowUntrusted: false);
    Require(blocked.Readiness.Status == InstallerReadinessStatus.BlockedByPolicy, "untrusted artifact bypassed default policy");
    Require(string.IsNullOrEmpty(blocked.Capability.CapabilityId), "blocked untrusted artifact received capability");

    var approved = await capabilities.PrepareAsync(
        artifact.ArtifactId,
        elevatedBrokerAvailable: false,
        allowUntrusted: true);
    Require(approved.Readiness.Status == InstallerReadinessStatus.Ready, "explicitly approved untrusted artifact did not become ready");
    Require(approved.Capability.CapabilityId.Length == 64, "approved artifact did not receive opaque capability");
    capabilities.Complete(approved.Capability.CapabilityId);
}

static async Task TestCapabilityOneShotAsync()
{
    using var env = TestEnvironment.Create();
    var path = Path.Combine(env.Downloads, "one-shot.exe");
    await File.WriteAllTextAsync(path, "one-shot-payload");
    var catalog = env.CreateCatalog();
    var artifact = await catalog.RegisterManagedDownloadAsync(path);

    using var capabilities = env.CreateCapabilities(catalog);
    var prepared = await capabilities.PrepareAsync(
        artifact.ArtifactId,
        elevatedBrokerAvailable: false,
        allowUntrusted: true);
    Require(prepared.Readiness.Status == InstallerReadinessStatus.Ready, "artifact did not become ready after explicit untrusted approval");
    Require(prepared.Capability.CapabilityId.Length == 64, "capability does not have 256-bit opaque ID");
    Require(!prepared.LaunchPlan.ExecutablePath.Equals(path, StringComparison.OrdinalIgnoreCase), "launch plan points at mutable download instead of staging");
    Require(prepared.LaunchPlan.ExpectedSha256 == artifact.Sha256, "launch plan lost approved digest");

    var plan = await capabilities.ConsumeAsync(prepared.Capability.CapabilityId);
    Require(plan.ExecutablePath == prepared.LaunchPlan.ExecutablePath, "consumed launch plan changed staged path");
    RequireThrows<InvalidOperationException>(() => capabilities.ConsumeAsync(prepared.Capability.CapabilityId).GetAwaiter().GetResult());
    capabilities.Complete(prepared.Capability.CapabilityId);
    Require(!Directory.Exists(Path.GetDirectoryName(plan.ExecutablePath)), "staging directory survived completion");
}

static Task TestCapabilityCleanupIdAsync()
{
    using var env = TestEnvironment.Create();
    var catalog = env.CreateCatalog();
    using var capabilities = env.CreateCapabilities(catalog);
    var sentinel = Path.Combine(env.Root, "cleanup-sentinel.txt");
    File.WriteAllText(sentinel, "keep");

    foreach (var invalidId in new[] { "..\\..", "../..", "", "not-a-capability" })
        RequireThrows<ArgumentException>(() => capabilities.Complete(invalidId));

    Require(File.Exists(sentinel), "invalid cleanup capability escaped staging and touched an outside file");
    return Task.CompletedTask;
}

static async Task TestUnsupportedFormatAsync()
{
    using var env = TestEnvironment.Create();
    var path = Path.Combine(env.Downloads, "payload.txt");
    await File.WriteAllTextAsync(path, "not an installer");
    var catalog = env.CreateCatalog();
    await RequireThrowsAsync<NotSupportedException>(() => catalog.RegisterManagedDownloadAsync(path));
}

static async Task TestMsiPlanAsync()
{
    using var env = TestEnvironment.Create();
    var path = Path.Combine(env.Downloads, "fixture.msi");
    await File.WriteAllTextAsync(path, "not-a-real-msi-but-valid-contract-fixture");
    var catalog = env.CreateCatalog();
    var artifact = await catalog.RegisterManagedDownloadAsync(path);

    using var capabilities = env.CreateCapabilities(catalog);
    var prepared = await capabilities.PrepareAsync(
        artifact.ArtifactId,
        elevatedBrokerAvailable: false,
        allowUntrusted: true);
    Require(prepared.Readiness.Status == InstallerReadinessStatus.Ready, "MSI did not become ready after explicit untrusted approval");
    var plan = prepared.LaunchPlan;
    Require(Path.GetFileName(plan.ExecutablePath).Equals("msiexec.exe", StringComparison.OrdinalIgnoreCase), "MSI does not use msiexec.exe");
    Require(plan.Arguments.Count == 5, "MSI argument vector changed unexpectedly");
    Require(plan.Arguments[0].Equals("/i", StringComparison.OrdinalIgnoreCase), "MSI missing /i");
    Require(plan.Arguments.Contains("/norestart", StringComparer.OrdinalIgnoreCase), "MSI can reboot without CloudOS approval");
    Require(plan.Arguments.Contains("/L*V", StringComparer.OrdinalIgnoreCase), "MSI verbose log switch missing");
    Require(plan.LogPath is not null && Path.IsPathFullyQualified(plan.LogPath), "MSI log path missing");
}

static async Task TestElevationBrokerAsync()
{
    IInstallerElevationBroker broker = new UnavailableInstallerElevationBroker();
    Require(!broker.IsAvailable, "default elevation broker unexpectedly available");
    var result = await broker.StartElevatedAsync(new InstallerBrokerRequest(
        new string('a', 64),
        new string('b', 32),
        new string('c', 64),
        InstallerArtifactKind.WindowsExecutable,
        Array.Empty<string>()));
    Require(!result.Accepted, "unavailable broker accepted elevation");
    Require(result.Status == "ELEVATION_BROKER_UNAVAILABLE", "wrong fail-closed broker status");
    Require(result.ProcessId is null, "unavailable broker returned process ID");
}

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

static void RequireThrows<T>(Action action) where T : Exception
{
    try
    {
        action();
    }
    catch (T)
    {
        return;
    }
    throw new InvalidOperationException($"Expected {typeof(T).Name} was not thrown.");
}

static async Task RequireThrowsAsync<T>(Func<Task> action) where T : Exception
{
    try
    {
        await action();
    }
    catch (T)
    {
        return;
    }
    throw new InvalidOperationException($"Expected {typeof(T).Name} was not thrown.");
}

sealed class TestEnvironment : IDisposable
{
    private TestEnvironment(string root)
    {
        Root = root;
        Downloads = Path.Combine(root, "Downloads");
        Installer = Path.Combine(root, "Installer");
        Directory.CreateDirectory(Downloads);
        Directory.CreateDirectory(Installer);
        Directory.CreateDirectory(Path.Combine(Installer, "Staging"));
        Directory.CreateDirectory(Path.Combine(Installer, "Logs"));
    }

    public string Root { get; }
    public string Downloads { get; }
    public string Installer { get; }

    public static TestEnvironment Create() =>
        new(Path.Combine(Path.GetTempPath(), $"cloudos-installer-tests-{Guid.NewGuid():N}"));

    public InstallerCatalog CreateCatalog() =>
        new(Downloads, Path.Combine(Installer, InstallerStorageLayout.CatalogFileName));

    public InstallerCapabilityService CreateCapabilities(InstallerCatalog catalog) =>
        new(
            catalog,
            Path.Combine(Installer, "Staging"),
            Path.Combine(Installer, "Logs"),
            TimeSpan.FromMinutes(1));

    public void Dispose()
    {
        try
        {
            if (!Directory.Exists(Root)) return;
            foreach (var file in Directory.EnumerateFiles(Root, "*", SearchOption.AllDirectories))
            {
                try { File.SetAttributes(file, FileAttributes.Normal); } catch { }
            }
            Directory.Delete(Root, recursive: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
        }
    }
}
