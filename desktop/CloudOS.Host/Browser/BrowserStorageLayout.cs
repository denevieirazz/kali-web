using System.IO;

namespace CloudOS.Host.Browser;

public static class BrowserStorageLayout
{
    public const string StateFileName = "browser-state.v1.json";

    public static string BrowserRoot(string localApplicationData) => Path.Combine(localApplicationData, "CloudOS", "Browser");
    public static string BrowserUserDataFolder(string localApplicationData) => Path.Combine(BrowserRoot(localApplicationData), "WebView2");
    public static string BrowserStatePath(string localApplicationData) => Path.Combine(BrowserRoot(localApplicationData), StateFileName);
    public static string ShellUserDataFolder(string localApplicationData) => Path.Combine(localApplicationData, "CloudOS", "WebView2");

    public static string CloudOsDriveRoot(string localApplicationData, string? overrideRoot = null)
    {
        if (!string.IsNullOrWhiteSpace(overrideRoot)) return Path.GetFullPath(overrideRoot);
        return Path.GetFullPath(Path.Combine(localApplicationData, "CloudOS", "Drive"));
    }

    public static string CloudOsDriveDownloads(string localApplicationData, string? overrideRoot = null) =>
        Path.Combine(CloudOsDriveRoot(localApplicationData, overrideRoot), "Home", "Downloads");

    public static bool AreIsolated(string browserFolder, string shellFolder) =>
        !Path.GetFullPath(browserFolder).TrimEnd(Path.DirectorySeparatorChar)
            .Equals(Path.GetFullPath(shellFolder).TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase);
}
