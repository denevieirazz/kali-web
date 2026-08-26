using System.Runtime.CompilerServices;
using CloudOS.Host.Browser;

internal static class BrowserCloudOsDriveContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        var temp = Path.Combine(Path.GetTempPath(), "cloudos-browser-drive-contract", Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(temp);
            var expectedRoot = Path.Combine(temp, "CloudOS", "Drive");
            var downloads = BrowserStorageLayout.CloudOsDriveDownloads(temp);
            Assert(Path.GetFullPath(downloads) == Path.GetFullPath(Path.Combine(expectedRoot, "Home", "Downloads")),
                "Browser and backend must derive the same CloudOS Drive Downloads layout.");

            var overrideRoot = Path.Combine(temp, "custom drive");
            var overrideDownloads = BrowserStorageLayout.CloudOsDriveDownloads(temp, overrideRoot);
            Assert(Path.GetFullPath(overrideDownloads) == Path.GetFullPath(Path.Combine(overrideRoot, "Home", "Downloads")),
                "CLOUDOS_DRIVE_DIR override must preserve the shared Downloads layout.");

            var first = BrowserStorageLayout.AllocateCloudOsDownloadPath(downloads, "report.txt");
            Assert(Path.GetFileName(first) == "report.txt", "The first download should keep a safe suggested name.");
            File.WriteAllText(first, "existing");
            var second = BrowserStorageLayout.AllocateCloudOsDownloadPath(downloads, "report.txt");
            Assert(Path.GetFileName(second) == "report (1).txt", "An existing CloudOS download must never be overwritten implicitly.");

            var activeReservation = BrowserStorageLayout.AllocateCloudOsDownloadPath(
                downloads,
                "parallel.zip",
                new[] { Path.Combine(downloads, "parallel.zip") });
            Assert(Path.GetFileName(activeReservation) == "parallel (1).zip",
                "Concurrent active downloads must reserve distinct CloudOS Drive paths before files exist.");

            var reserved = BrowserStorageLayout.SanitizeDownloadName("CON.txt");
            Assert(!reserved.Equals("CON.txt", StringComparison.OrdinalIgnoreCase),
                "Windows device names must not be emitted into CloudOS Downloads.");
            var traversal = BrowserStorageLayout.SanitizeDownloadName("..\\escape.exe");
            Assert(!traversal.Contains("..", StringComparison.Ordinal) && !traversal.Contains('\\') && !traversal.Contains('/'),
                "Suggested download names may not create paths outside CloudOS Downloads.");

            Console.WriteLine("PASS native Browser CloudOS Drive download contract");
        }
        finally
        {
            try { Directory.Delete(temp, recursive: true); } catch { }
        }
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
