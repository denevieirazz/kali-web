using System.IO;

namespace CloudOS.Bootstrap;

public sealed record BootstrapOptions(
    string HostPath,
    IReadOnlyList<string> HostArguments,
    bool AllowEarlyCleanExit,
    bool ShowPrerequisites,
    bool SkipPrerequisites,
    bool CheckUpdateOnly,
    string? UpdateSource,
    string? UpdateChannel,
    string? ProjectRoot,
    string? NodePath)
{
    public static BootstrapOptions Parse(IReadOnlyList<string> arguments)
    {
        string? requestedHost = null;
        string? projectRoot = null;
        string? nodePath = null;
        string? updateSource = null;
        string? updateChannel = null;
        var hostArguments = new List<string>();
        var allowEarlyCleanExit = false;
        var showPrerequisites = false;
        var skipPrerequisites = false;
        var checkUpdateOnly = false;

        for (var index = 0; index < arguments.Count; index++)
        {
            switch (arguments[index])
            {
                case "--host":
                    requestedHost = ReadValue(arguments, ref index, "--host");
                    break;
                case "--root":
                    projectRoot = Path.GetFullPath(ReadValue(arguments, ref index, "--root"));
                    hostArguments.Add("--root");
                    hostArguments.Add(projectRoot);
                    break;
                case "--node":
                    nodePath = Path.GetFullPath(ReadValue(arguments, ref index, "--node"));
                    hostArguments.Add("--node");
                    hostArguments.Add(nodePath);
                    break;
                case "--fullscreen":
                case "--kiosk":
                case "--developer-mode":
                    hostArguments.Add(arguments[index]);
                    break;
                case "--preview":
                    allowEarlyCleanExit = true;
                    break;
                case "--prerequisites":
                    showPrerequisites = true;
                    break;
                case "--skip-prerequisites":
                    skipPrerequisites = true;
                    break;
                case "--check-update":
                    checkUpdateOnly = true;
                    break;
                case "--update-source":
                    updateSource = ReadValue(arguments, ref index, "--update-source");
                    break;
                case "--channel":
                    updateChannel = ReadValue(arguments, ref index, "--channel").ToLowerInvariant();
                    if (updateChannel is not ("stable" or "preview" or "development"))
                        throw new ArgumentException("Canal de atualização inválido.");
                    break;
                default:
                    throw new ArgumentException($"Opção desconhecida: {arguments[index]}");
            }
        }

        var hostPath = ResolveHostPath(requestedHost);
        if (!string.Equals(Path.GetFileName(hostPath), "CloudOS.Host.exe", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("O bootstrap somente inicia CloudOS.Host.exe.");
        return new BootstrapOptions(
            hostPath,
            hostArguments,
            allowEarlyCleanExit,
            showPrerequisites,
            skipPrerequisites,
            checkUpdateOnly,
            updateSource,
            updateChannel,
            projectRoot,
            nodePath);
    }

    private static string ReadValue(IReadOnlyList<string> arguments, ref int index, string option)
    {
        if (++index >= arguments.Count || string.IsNullOrWhiteSpace(arguments[index]))
            throw new ArgumentException($"A opção {option} exige um valor.");
        return arguments[index];
    }

    private static string ResolveHostPath(string? requestedHost)
    {
        if (!string.IsNullOrWhiteSpace(requestedHost))
        {
            var fullPath = Path.GetFullPath(requestedHost);
            if (!File.Exists(fullPath)) throw new FileNotFoundException("CloudOS.Host.exe não foi encontrado.", fullPath);
            return fullPath;
        }

        var candidates = new List<string>
        {
            Path.Combine(AppContext.BaseDirectory, "CloudOS.Host.exe"),
            Path.Combine(AppContext.BaseDirectory, "app", "host", "CloudOS.Host.exe")
        };
        var cursor = new DirectoryInfo(AppContext.BaseDirectory);
        for (var depth = 0; cursor is not null && depth < 8; depth++, cursor = cursor.Parent)
        {
            candidates.Add(Path.Combine(cursor.FullName, "desktop", "publish", "CloudOS.Host.exe"));
            candidates.Add(Path.Combine(cursor.FullName, "CloudOS.Host", "bin", "Release", "net8.0-windows10.0.19041.0", "CloudOS.Host.exe"));
        }

        var match = candidates.Select(Path.GetFullPath).FirstOrDefault(File.Exists);
        return match ?? throw new FileNotFoundException("CloudOS.Host.exe não foi encontrado. Publique-o ao lado do bootstrap ou informe --host.");
    }
}
