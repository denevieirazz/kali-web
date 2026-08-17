using System.Text.Json.Nodes;
using CloudOS.Bootstrap;
using Velopack;
using Velopack.Locators;
using Velopack.Logging;
using Velopack.Sources;

if (args.Length != 5) throw new ArgumentException("usage: <fixtureDir> <currentVersion> <nextVersion> <followingFixtureDir> <followingVersion>");
var fixture = Path.GetFullPath(args[0]);
var currentVersion = args[1];
var nextVersion = args[2];
var followingFixture = Path.GetFullPath(args[3]);
var followingVersion = args[4];
var temp = Path.Combine(Path.GetTempPath(), $"cloudos-velopack-tests-{Guid.NewGuid():N}");
Directory.CreateDirectory(temp);
try
{
    var policy = DistributionChannelPolicy.Load(Directory.GetCurrentDirectory());
    Assert(policy.IsTransitionAllowed("development", "development"), "CHANNEL_DEV_DEV_REQUIRED");
    Assert(policy.IsTransitionAllowed("development", "preview"), "CHANNEL_DEV_PREVIEW_REQUIRED");
    Assert(policy.IsTransitionAllowed("preview", "stable"), "CHANNEL_PREVIEW_STABLE_REQUIRED");
    Assert(policy.IsTransitionAllowed("stable", "stable"), "CHANNEL_STABLE_STABLE_REQUIRED");
    ExpectFailure(() => policy.AssertTransition("development", "preview", false), "CHANNEL_SILENT_SWITCH_ACCEPTED");
    ExpectFailure(() => policy.AssertTransition("stable", "preview", true), "CHANNEL_REVERSE_TRANSITION_ACCEPTED");
    policy.AssertVersionDirection(currentVersion, nextVersion, false);
    ExpectFailure(() => policy.AssertVersionDirection(nextVersion, currentVersion, false), "DOWNGRADE_NOT_BLOCKED");
    policy.AssertVersionDirection(nextVersion, currentVersion, true);
    var unsignedPreview = new ProductMetadata { SchemaVersion = 1, Channel = "preview", Signing = "unsigned-development", StableUpdatesEnabled = true };
    ExpectFailure(() => policy.AssertRuntimeReady("preview", unsignedPreview), "UNSIGNED_PREVIEW_ACCEPTED");
    var unsignedStable = new ProductMetadata { SchemaVersion = 1, Channel = "stable", Signing = "unsigned-development", StableUpdatesEnabled = true };
    ExpectFailure(() => policy.AssertRuntimeReady("stable", unsignedStable), "UNSIGNED_STABLE_ACCEPTED");
    ExpectFailure(() => policy.AssertRemoteOrigin("stable", new Uri("https://updates.invalid.example")), "UNAPPROVED_STABLE_ORIGIN_ACCEPTED");

    var packages = Path.Combine(temp, "packages-ok"); Directory.CreateDirectory(packages);
    var locator = new TestVelopackLocator("CloudOS.Experimental", currentVersion, packages);
    var options = new UpdateOptions { ExplicitChannel = "development", AllowVersionDowngrade = false, MaximumDeltasBeforeFallback = 0 };
    var manager = new UpdateManager(new SimpleFileSource(new DirectoryInfo(fixture)), options, locator);
    var update = await manager.CheckForUpdatesAsync() ?? throw new Exception("UPDATE_AVAILABLE_EXPECTED");
    Assert(update.TargetFullRelease.Version.ToString() == nextVersion, $"UPDATE_VERSION_MISMATCH:{update.TargetFullRelease.Version}");
    var progressSeen = false;
    await manager.DownloadUpdatesAsync(update, p => { if (p > 0) progressSeen = true; });
    Assert(progressSeen, "UPDATE_PROGRESS_NOT_REPORTED");
    Assert(manager.UpdatePendingRestart is not null, "UPDATE_NOT_STAGED_FOR_RESTART");

    var currentLocator = new TestVelopackLocator("CloudOS.Experimental", nextVersion, Path.Combine(temp, "packages-current"));
    Directory.CreateDirectory(currentLocator.PackagesDir!);
    var currentManager = new UpdateManager(new SimpleFileSource(new DirectoryInfo(fixture)), options, currentLocator);
    Assert(await currentManager.CheckForUpdatesAsync() is null, "NO_UPDATE_EXPECTED_AT_LATEST");

    var corrupt = Path.Combine(temp, "corrupt-feed"); CopyDirectory(fixture, corrupt);
    var corruptPackage = FindFullPackage(corrupt, nextVersion);
    using (var stream = new FileStream(corruptPackage, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
    {
        var first = stream.ReadByte(); if (first < 0) throw new Exception("CORRUPT_PACKAGE_EMPTY"); stream.Position = 0; stream.WriteByte((byte)(first ^ 0xff));
    }
    await AssertDownloadRejected(corrupt, currentVersion, temp, "corrupt", "CORRUPT_PACKAGE_OR_HASH_MISMATCH_ACCEPTED");

    var partial = Path.Combine(temp, "partial-feed"); CopyDirectory(fixture, partial);
    var partialPackage = FindFullPackage(partial, nextVersion);
    using (var stream = new FileStream(partialPackage, FileMode.Open, FileAccess.Write, FileShare.None)) stream.SetLength(Math.Max(1, stream.Length / 2));
    await AssertDownloadRejected(partial, currentVersion, temp, "partial", "PARTIAL_PACKAGE_ACCEPTED");

    var tampered = Path.Combine(temp, "tampered-feed"); CopyDirectory(fixture, tampered);
    var feedPath = Path.Combine(tampered, "releases.development.json");
    var feed = JsonNode.Parse(File.ReadAllText(feedPath))?.AsObject() ?? throw new Exception("TAMPERED_FEED_PARSE_FAILED");
    var assets = feed["Assets"]?.AsArray() ?? throw new Exception("TAMPERED_FEED_ASSETS_MISSING");
    var target = assets.Select(node => node?.AsObject()).FirstOrDefault(node => string.Equals(node?["Version"]?.GetValue<string>(), nextVersion, StringComparison.OrdinalIgnoreCase) && (node?["Type"]?.ToString().Contains("Full", StringComparison.OrdinalIgnoreCase) ?? false))
        ?? throw new Exception("TAMPERED_FEED_TARGET_MISSING");
    target["SHA256"] = new string('0', 64);
    File.WriteAllText(feedPath, feed.ToJsonString());
    await AssertDownloadRejected(tampered, currentVersion, temp, "tampered", "TAMPERED_MANIFEST_ACCEPTED");

    var slowPackages = Path.Combine(temp, "packages-cancel"); Directory.CreateDirectory(slowPackages);
    var slowLocator = new TestVelopackLocator("CloudOS.Experimental", currentVersion, slowPackages);
    var slowManager = new UpdateManager(new SlowSource(new SimpleFileSource(new DirectoryInfo(fixture))), options, slowLocator);
    var slowUpdate = await slowManager.CheckForUpdatesAsync() ?? throw new Exception("CANCEL_UPDATE_AVAILABLE_EXPECTED");
    using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(150));
    var cancelled = false;
    try { await slowManager.DownloadUpdatesAsync(slowUpdate, null, cancellation.Token); }
    catch (OperationCanceledException) { cancelled = true; }
    Assert(cancelled, "UPDATE_CANCELLATION_NOT_PROPAGATED");

    var followingPackages = Path.Combine(temp, "packages-following"); Directory.CreateDirectory(followingPackages);
    var followingLocator = new TestVelopackLocator("CloudOS.Experimental", nextVersion, followingPackages);
    var followingManager = new UpdateManager(new SimpleFileSource(new DirectoryInfo(followingFixture)), options, followingLocator);
    var followingUpdate = await followingManager.CheckForUpdatesAsync() ?? throw new Exception("FOLLOWING_UPDATE_AVAILABLE_EXPECTED");
    Assert(followingUpdate.TargetFullRelease.Version.ToString() == followingVersion, "FOLLOWING_UPDATE_VERSION_MISMATCH");
    await followingManager.DownloadUpdatesAsync(followingUpdate);
    Assert(followingManager.UpdatePendingRestart is not null, "FOLLOWING_UPDATE_NOT_STAGED");

    Console.WriteLine("PRODUCTIZATION_VELOPACK_UPDATE_TESTS_OK available=true noUpdate=true corruptRejected=true cancellation=true");
    Console.WriteLine("PRODUCTIZATION_UPDATE_HARDENING_OK downgradeBlocked=true explicitDowngrade=true signatureMissingRejected=true manifestTamper=true hashMismatch=true partial=true interrupted=true sequential=true channels=true");
}
finally { try { Directory.Delete(temp, true); } catch { } }

static async Task AssertDownloadRejected(string fixture, string currentVersion, string temp, string suffix, string failure)
{
    var packages = Path.Combine(temp, $"packages-{suffix}"); Directory.CreateDirectory(packages);
    var locator = new TestVelopackLocator("CloudOS.Experimental", currentVersion, packages);
    var manager = new UpdateManager(new SimpleFileSource(new DirectoryInfo(fixture)), new UpdateOptions { ExplicitChannel = "development", AllowVersionDowngrade = false, MaximumDeltasBeforeFallback = 0 }, locator);
    var update = await manager.CheckForUpdatesAsync() ?? throw new Exception($"{suffix.ToUpperInvariant()}_UPDATE_FEED_NOT_READ");
    var rejected = false;
    try { await manager.DownloadUpdatesAsync(update); }
    catch { rejected = true; }
    Assert(rejected, failure);
}

static string FindFullPackage(string directory, string version)
    => Directory.GetFiles(directory, $"*{version}*-full.nupkg", SearchOption.TopDirectoryOnly).Single();

static void ExpectFailure(Action action, string failure)
{
    var rejected = false;
    try { action(); } catch { rejected = true; }
    Assert(rejected, failure);
}

static void Assert(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

static void CopyDirectory(string source, string destination)
{
    Directory.CreateDirectory(destination);
    foreach (var file in Directory.GetFiles(source)) File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), true);
    foreach (var dir in Directory.GetDirectories(source)) CopyDirectory(dir, Path.Combine(destination, Path.GetFileName(dir)));
}

sealed class SlowSource(IUpdateSource inner) : IUpdateSource
{
    public Task<VelopackAssetFeed> GetReleaseFeed(IVelopackLogger logger, string? appId, string channel, Guid? stagingId = null, VelopackAsset? latestLocalRelease = null)
        => inner.GetReleaseFeed(logger, appId, channel, stagingId, latestLocalRelease);
    public async Task DownloadReleaseEntry(IVelopackLogger logger, VelopackAsset releaseEntry, string localFile, Action<int> progress, CancellationToken cancelToken = default)
    {
        progress(1);
        await Task.Delay(TimeSpan.FromSeconds(30), cancelToken);
    }
}
