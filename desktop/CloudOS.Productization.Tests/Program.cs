using Velopack;
using Velopack.Locators;
using Velopack.Logging;
using Velopack.Sources;

if (args.Length != 3) throw new ArgumentException("usage: <fixtureDir> <currentVersion> <nextVersion>");
var fixture = Path.GetFullPath(args[0]);
var currentVersion = args[1];
var nextVersion = args[2];
var temp = Path.Combine(Path.GetTempPath(), $"cloudos-velopack-tests-{Guid.NewGuid():N}");
Directory.CreateDirectory(temp);
try
{
    var packages = Path.Combine(temp, "packages-ok"); Directory.CreateDirectory(packages);
    var locator = new TestVelopackLocator("CloudOS.Experimental", currentVersion, packages);
    var options = new UpdateOptions { ExplicitChannel = "development", AllowVersionDowngrade = false, MaximumDeltasBeforeFallback = 0 };
    var manager = new UpdateManager(new SimpleFileSource(new DirectoryInfo(fixture)), options, locator);
    var update = await manager.CheckForUpdatesAsync() ?? throw new Exception("UPDATE_AVAILABLE_EXPECTED");
    if (update.TargetFullRelease.Version.ToString() != nextVersion) throw new Exception($"UPDATE_VERSION_MISMATCH:{update.TargetFullRelease.Version}");
    var progressSeen = false;
    await manager.DownloadUpdatesAsync(update, p => { if (p > 0) progressSeen = true; });
    if (!progressSeen) throw new Exception("UPDATE_PROGRESS_NOT_REPORTED");
    if (manager.UpdatePendingRestart is null) throw new Exception("UPDATE_NOT_STAGED_FOR_RESTART");

    var currentLocator = new TestVelopackLocator("CloudOS.Experimental", nextVersion, Path.Combine(temp, "packages-current"));
    Directory.CreateDirectory(currentLocator.PackagesDir!);
    var currentManager = new UpdateManager(new SimpleFileSource(new DirectoryInfo(fixture)), options, currentLocator);
    if (await currentManager.CheckForUpdatesAsync() is not null) throw new Exception("NO_UPDATE_EXPECTED_AT_LATEST");

    var corrupt = Path.Combine(temp, "corrupt-feed"); CopyDirectory(fixture, corrupt);
    var corruptPackage = Directory.GetFiles(corrupt, $"*{nextVersion}*-full.nupkg", SearchOption.TopDirectoryOnly).Single();
    using (var stream = new FileStream(corruptPackage, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
    {
        var first = stream.ReadByte(); if (first < 0) throw new Exception("CORRUPT_PACKAGE_EMPTY"); stream.Position = 0; stream.WriteByte((byte)(first ^ 0xff));
    }
    var corruptLocator = new TestVelopackLocator("CloudOS.Experimental", currentVersion, Path.Combine(temp, "packages-corrupt"));
    Directory.CreateDirectory(corruptLocator.PackagesDir!);
    var corruptManager = new UpdateManager(new SimpleFileSource(new DirectoryInfo(corrupt)), options, corruptLocator);
    var corruptUpdate = await corruptManager.CheckForUpdatesAsync() ?? throw new Exception("CORRUPT_UPDATE_FEED_NOT_READ");
    var corruptRejected = false;
    try { await corruptManager.DownloadUpdatesAsync(corruptUpdate); }
    catch { corruptRejected = true; }
    if (!corruptRejected) throw new Exception("CORRUPT_PACKAGE_OR_HASH_MISMATCH_ACCEPTED");

    var slowPackages = Path.Combine(temp, "packages-cancel"); Directory.CreateDirectory(slowPackages);
    var slowLocator = new TestVelopackLocator("CloudOS.Experimental", currentVersion, slowPackages);
    var slowManager = new UpdateManager(new SlowSource(new SimpleFileSource(new DirectoryInfo(fixture))), options, slowLocator);
    var slowUpdate = await slowManager.CheckForUpdatesAsync() ?? throw new Exception("CANCEL_UPDATE_AVAILABLE_EXPECTED");
    using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(150));
    var cancelled = false;
    try { await slowManager.DownloadUpdatesAsync(slowUpdate, null, cancellation.Token); }
    catch (OperationCanceledException) { cancelled = true; }
    if (!cancelled) throw new Exception("UPDATE_CANCELLATION_NOT_PROPAGATED");
    Console.WriteLine("PRODUCTIZATION_VELOPACK_UPDATE_TESTS_OK available=true noUpdate=true corruptRejected=true cancellation=true");
}
finally { try { Directory.Delete(temp, true); } catch { } }

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
