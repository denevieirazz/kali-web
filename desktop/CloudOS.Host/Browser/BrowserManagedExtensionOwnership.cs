using System.IO;

namespace CloudOS.Host.Browser;

internal static class BrowserManagedExtensionOwnership
{
    private const string PackagePrefix = "package-";
    private const string StagingPrefix = ".staging-";

    internal static bool TryResolveManagedPackage(
        IReadOnlyDictionary<string, string> state,
        string managedRoot,
        string extensionId,
        out string managedPath)
    {
        managedPath = string.Empty;
        if (string.IsNullOrWhiteSpace(extensionId) ||
            !state.TryGetValue(extensionId, out var candidate) ||
            string.IsNullOrWhiteSpace(candidate) ||
            !IsSafeManagedPackagePath(managedRoot, candidate))
            return false;

        managedPath = Path.GetFullPath(candidate);
        return true;
    }

    internal static bool IsSafeManagedPackagePath(string managedRoot, string candidate) =>
        IsDirectManagedChild(managedRoot, candidate, PackagePrefix);

    internal static bool IsSafeStagingPath(string managedRoot, string candidate) =>
        IsDirectManagedChild(managedRoot, candidate, StagingPrefix);

    private static bool IsDirectManagedChild(string managedRoot, string candidate, string prefix)
    {
        try
        {
            var root = Normalize(managedRoot);
            var full = Normalize(candidate);
            if (full.Equals(root, StringComparison.OrdinalIgnoreCase)) return false;

            var parent = Directory.GetParent(full)?.FullName;
            if (parent is null || !Normalize(parent).Equals(root, StringComparison.OrdinalIgnoreCase))
                return false;

            var name = Path.GetFileName(full);
            if (!name.StartsWith(prefix, StringComparison.Ordinal)) return false;
            var suffix = name[prefix.Length..];
            return Guid.TryParseExact(suffix, "N", out _);
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    private static string Normalize(string path) =>
        Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
}
