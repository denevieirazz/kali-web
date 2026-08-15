using System.Runtime.CompilerServices;
using CloudOS.Host.Browser;

internal static class BrowserExtensionOwnershipContract
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        var root = Path.Combine(Path.GetTempPath(), "cloudos-extension-ownership", Guid.NewGuid().ToString("N"), "Extensions");
        var owned = Path.Combine(root, "package-" + Guid.NewGuid().ToString("N"));
        var staging = Path.Combine(root, ".staging-" + Guid.NewGuid().ToString("N"));
        var nested = Path.Combine(root, "nested", "package-" + Guid.NewGuid().ToString("N"));
        var sibling = Path.Combine(Path.GetDirectoryName(root)!, "Extensions-evil", "package-" + Guid.NewGuid().ToString("N"));

        Assert(BrowserManagedExtensionOwnership.IsSafeManagedPackagePath(root, owned), "CloudOS package-* direct child must be owned.");
        Assert(BrowserManagedExtensionOwnership.IsSafeStagingPath(root, staging), "CloudOS staging direct child must be recognized.");
        Assert(!BrowserManagedExtensionOwnership.IsSafeManagedPackagePath(root, root), "Managed root itself must never be removable.");
        Assert(!BrowserManagedExtensionOwnership.IsSafeManagedPackagePath(root, nested), "Nested package-* path must not acquire ownership.");
        Assert(!BrowserManagedExtensionOwnership.IsSafeManagedPackagePath(root, sibling), "Sibling prefix-confusion path must not acquire ownership.");
        Assert(!BrowserManagedExtensionOwnership.IsSafeManagedPackagePath(root, Path.Combine(root, "package-not-a-guid")), "Malformed package name must not acquire ownership.");

        var state = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["cloudos-owned"] = owned,
            ["webview-internal"] = sibling
        };
        Assert(
            BrowserManagedExtensionOwnership.TryResolveManagedPackage(state, root, "cloudos-owned", out var resolved) &&
            Path.GetFullPath(resolved) == Path.GetFullPath(owned),
            "Owned extension id must resolve only to its controlled package-* path.");
        Assert(
            !BrowserManagedExtensionOwnership.TryResolveManagedPackage(state, root, "webview-internal", out _),
            "Non-CloudOS extension id must never resolve as removable ownership.");
        Assert(
            !BrowserManagedExtensionOwnership.TryResolveManagedPackage(state, root, "missing", out _),
            "Unknown extension id must fail closed.");

        Console.WriteLine("PASS browser extension ownership is CloudOS package-only and fail-closed");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
