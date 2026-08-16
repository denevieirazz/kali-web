using System.IO;

namespace CloudOS.Bootstrap;

public static class DistributionEnvironment
{
    public static string ResolveLocalRoot()
    {
        var configured = Environment.GetEnvironmentVariable("CLOUDOS_LOCAL_ROOT");
        if (!string.IsNullOrWhiteSpace(configured)) return Path.GetFullPath(configured);
        return Path.GetFullPath(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CloudOS"));
    }

    public static string ResolvePackageRoot(BootstrapOptions options)
    {
        if (!string.IsNullOrWhiteSpace(options.ProjectRoot)) return Path.GetFullPath(options.ProjectRoot);
        return Path.GetFullPath(AppContext.BaseDirectory);
    }
}
