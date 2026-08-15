using System.Runtime.CompilerServices;
using System.Text;
using CloudOS.Host.Browser;

internal static class BrowserExtensionPackageContract
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        ValidateAcceptedPackage();
        RejectMissingManifest();
        RejectMalformedManifest();
        RejectOversizedManifest();
        Console.WriteLine("PASS browser local extension package validation");
    }

    private static void ValidateAcceptedPackage()
    {
        using var temp = new ExtensionTempDirectory();
        File.WriteAllText(
            Path.Combine(temp.Path, "manifest.json"),
            """{"manifest_version":3,"name":"CloudOS Test Extension","version":"1.0.0"}""");
        File.WriteAllText(Path.Combine(temp.Path, "background.js"), "console.log('cloudos');");

        var package = BrowserExtensionManager.ValidatePackage(temp.Path);
        Assert(package.Name == "CloudOS Test Extension", "Valid extension name was not preserved.");
        Assert(package.Version == "1.0.0", "Valid extension version was not preserved.");
        Assert(package.ManifestVersion == 3, "Manifest version was not validated.");
        Assert(package.FileCount == 2, "Extension file count is incorrect.");
    }

    private static void RejectMissingManifest()
    {
        using var temp = new ExtensionTempDirectory();
        File.WriteAllText(Path.Combine(temp.Path, "script.js"), "void 0;");
        AssertCode(
            () => BrowserExtensionManager.ValidatePackage(temp.Path),
            "EXTENSION_MANIFEST_MISSING");
    }

    private static void RejectMalformedManifest()
    {
        using var temp = new ExtensionTempDirectory();
        File.WriteAllText(Path.Combine(temp.Path, "manifest.json"), "{not-json");
        AssertCode(
            () => BrowserExtensionManager.ValidatePackage(temp.Path),
            "EXTENSION_MANIFEST_INVALID");
    }

    private static void RejectOversizedManifest()
    {
        using var temp = new ExtensionTempDirectory();
        File.WriteAllText(
            Path.Combine(temp.Path, "manifest.json"),
            new string('x', BrowserExtensionManager.MaxManifestBytes + 1),
            Encoding.UTF8);
        AssertCode(
            () => BrowserExtensionManager.ValidatePackage(temp.Path),
            "EXTENSION_MANIFEST_SIZE_INVALID");
    }

    private static void AssertCode(Action action, string expectedCode)
    {
        try
        {
            action();
        }
        catch (BrowserExtensionPackageException error) when (error.Code == expectedCode)
        {
            return;
        }

        throw new InvalidOperationException($"Expected extension validation code {expectedCode}.");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private sealed class ExtensionTempDirectory : IDisposable
    {
        public string Path { get; } = System.IO.Path.Combine(
            System.IO.Path.GetTempPath(),
            "cloudos-extension-tests",
            Guid.NewGuid().ToString("N"));

        public ExtensionTempDirectory() => Directory.CreateDirectory(Path);

        public void Dispose()
        {
            try { Directory.Delete(Path, recursive: true); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
    }
}
