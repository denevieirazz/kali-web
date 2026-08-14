using System.IO;

namespace CloudOS.Host.Browser;

public static class BrowserStorageLayout
{
    public const string StateFileName = "browser-state.v1.json";

    public static string BrowserRoot(string localApplicationData) => Path.Combine(localApplicationData, "CloudOS", "Browser");
    public static string BrowserUserDataFolder(string localApplicationData) => Path.Combine(BrowserRoot(localApplicationData), "WebView2");
    public static string BrowserStatePath(string localApplicationData) => Path.Combine(BrowserRoot(localApplicationData), StateFileName);
    public static string ShellUserDataFolder(string localApplicationData) => Path.Combine(localApplicationData, "CloudOS", "WebView2");

    public static bool AreIsolated(string browserFolder, string shellFolder) =>
        !Path.GetFullPath(browserFolder).TrimEnd(Path.DirectorySeparatorChar)
            .Equals(Path.GetFullPath(shellFolder).TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase);
}
