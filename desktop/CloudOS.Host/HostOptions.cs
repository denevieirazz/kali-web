namespace CloudOS.Host;

public sealed record HostOptions(
    string? ProjectRoot,
    string? NodePath,
    bool Fullscreen,
    bool Kiosk,
    bool DeveloperMode,
    string? BootstrapPipe)
{
    public static HostOptions Parse(IReadOnlyList<string> arguments)
    {
        string? root = null;
        string? node = null;
        var fullscreen = false;
        var kiosk = false;
        var developerMode = false;
        string? bootstrapPipe = null;

        for (var index = 0; index < arguments.Count; index++)
        {
            switch (arguments[index])
            {
                case "--root":
                    root = ReadValue(arguments, ref index, "--root");
                    break;
                case "--node":
                    node = ReadValue(arguments, ref index, "--node");
                    break;
                case "--fullscreen":
                    fullscreen = true;
                    break;
                case "--kiosk":
                    kiosk = true;
                    fullscreen = true;
                    break;
                case "--developer-mode":
                    developerMode = true;
                    break;
                case "--bootstrap-pipe":
                    bootstrapPipe = ReadValue(arguments, ref index, "--bootstrap-pipe");
                    if (bootstrapPipe.Length > 180 || bootstrapPipe.Any(character =>
                        !char.IsAsciiLetterOrDigit(character) && character is not ('.' or '_' or '-')))
                        throw new ArgumentException("O nome do pipe de bootstrap é inválido.");
                    break;
                default:
                    throw new ArgumentException($"Opção desconhecida: {arguments[index]}");
            }
        }

        return new HostOptions(root, node, fullscreen, kiosk, developerMode, bootstrapPipe);
    }

    private static string ReadValue(IReadOnlyList<string> arguments, ref int index, string option)
    {
        if (++index >= arguments.Count || string.IsNullOrWhiteSpace(arguments[index]))
            throw new ArgumentException($"A opção {option} exige um valor.");
        return arguments[index];
    }
}
