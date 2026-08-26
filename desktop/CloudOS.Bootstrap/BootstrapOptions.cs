using System.IO;

namespace CloudOS.Bootstrap;

public sealed record BootstrapOptions(
    string HostPath,
    IReadOnlyList<string> HostArguments,
    bool AllowEarlyCleanExit)
{
    public static BootstrapOptions Parse(IReadOnlyList<string> arguments)
    {
        string? requestedHost = null;
        var hostArguments = new List<string>();
        var allowEarlyCleanExit = false;

        for (var index = 0; index < arguments.Count; index++)
        {
            switch (arguments[index])
            {
                case "--host":
                    requestedHost = ReadValue(arguments, ref index, "--host");
                    break;
                case "--root":
                case "--node":
                    var option = arguments[index];
                    hostArguments.Add(option);
                    hostArguments.Add(ReadValue(arguments, ref index, option));
                    break;
                case "--fullscreen":
                case "--kiosk":
                case "--developer-mode":
                    hostArguments.Add(arguments[index]);
                    break;
                case "--preview":
                    allowEarlyCleanExit = true;
                    break;
                default:
                    throw new ArgumentException($"Opção desconhecida: {arguments[index]}");
            }
        }

        var hostPath = ResolveHostPath(requestedHost);
        if (!string.Equals(Path.GetFileName(hostPath), "CloudOS.Host.exe", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("O bootstrap somente inicia CloudOS.Host.exe.");
        return new BootstrapOptions(hostPath, hostArguments, allowEarlyCleanExit);
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

        var candidates = new List<string> { Path.Combine(AppContext.BaseDirectory, "CloudOS.Host.exe") };
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
