using System.IO;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Host.Runtime;

public static class CloudOsLocalPaths
{
    public const string TestLocalRootEnvironmentVariable = "CLOUDOS_TEST_LOCAL_ROOT";
    public const string ShellTestCdpPortEnvironmentVariable = "CLOUDOS_SHELL_TEST_CDP_PORT";

    public static string ResolveRoot(bool developerMode)
    {
        var productionRoot = Path.GetFullPath(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CloudOS"));
        if (!developerMode) return productionRoot;

        var candidate = Environment.GetEnvironmentVariable(TestLocalRootEnvironmentVariable);
        if (string.IsNullOrWhiteSpace(candidate)) return productionRoot;
        if (!Path.IsPathFullyQualified(candidate))
            throw new InvalidOperationException("CLOUDOS_TEST_LOCAL_ROOT deve ser um caminho absoluto.");

        var full = Path.GetFullPath(candidate).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var root = Path.GetPathRoot(full)?.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (string.IsNullOrWhiteSpace(full) || full.Equals(root, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("CLOUDOS_TEST_LOCAL_ROOT não pode apontar para a raiz do volume.");
        if (full.Equals(productionRoot.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar), StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("CLOUDOS_TEST_LOCAL_ROOT deve ser isolado do perfil de produção.");
        return full;
    }

    public static CoreWebView2EnvironmentOptions? CreateShellTestEnvironmentOptions(bool developerMode)
    {
        if (!developerMode) return null;
        var value = Environment.GetEnvironmentVariable(ShellTestCdpPortEnvironmentVariable);
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (!int.TryParse(value, out var port) || port is < 1024 or > 65535)
            throw new InvalidOperationException("CLOUDOS_SHELL_TEST_CDP_PORT inválida.");
        return new CoreWebView2EnvironmentOptions($"--remote-debugging-port={port}");
    }
}
