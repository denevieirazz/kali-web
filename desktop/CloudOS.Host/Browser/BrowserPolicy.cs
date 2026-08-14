using System.Globalization;
using System.Net;

namespace CloudOS.Host.Browser;

public sealed record BrowserNavigationDecision(bool Allowed, Uri? Uri, bool IsSearch, string? ErrorCode, string? Message)
{
    public static BrowserNavigationDecision Allow(Uri uri, bool isSearch = false) => new(true, uri, isSearch, null, null);
    public static BrowserNavigationDecision Block(string code, string message) => new(false, null, false, code, message);
}

public sealed class BrowserPolicy
{
    public const int MaxInputLength = 8192;
    public const string HomeUrl = "https://duckduckgo.com/";
    public const string SearchBaseUrl = "https://duckduckgo.com/?q=";

    private static readonly HashSet<string> BlockedSchemes = new(StringComparer.OrdinalIgnoreCase)
    {
        "file", "ftp", "javascript", "vbscript", "shell", "cmd", "powershell", "ms-settings", "ms-appx",
        "edge", "chrome", "devtools", "view-source"
    };

    private readonly HashSet<string> _blockedOrigins = new(StringComparer.OrdinalIgnoreCase);

    public BrowserPolicy(Uri shellOrigin, Uri backendOrigin)
    {
        AddBlockedOrigin(shellOrigin);
        AddBlockedOrigin(backendOrigin);
    }

    public BrowserNavigationDecision ParseAddressInput(string? raw)
    {
        var input = (raw ?? string.Empty).Trim();
        if (input.Length == 0) return BrowserNavigationDecision.Allow(new Uri(HomeUrl));
        if (input.Length > MaxInputLength) return BrowserNavigationDecision.Block("URL_TOO_LONG", "O endereço excede o limite permitido.");
        if (ContainsControlCharacters(input)) return BrowserNavigationDecision.Block("INVALID_URL", "O endereço contém caracteres de controle.");

        if (Uri.TryCreate(input, UriKind.Absolute, out var absolute))
            return ValidateExternalUri(absolute, fromAddressBar: true);

        if (LooksLikeLocalHost(input))
            return ValidateExternalUri(new Uri($"http://{input}"), fromAddressBar: true);

        if (LooksLikeDomain(input))
            return ValidateExternalUri(new Uri($"https://{input}"), fromAddressBar: true);

        var search = new Uri(SearchBaseUrl + Uri.EscapeDataString(input));
        return BrowserNavigationDecision.Allow(search, isSearch: true);
    }

    public BrowserNavigationDecision ValidateNavigation(string? rawUri, bool allowAboutBlank = false)
    {
        if (string.IsNullOrWhiteSpace(rawUri)) return BrowserNavigationDecision.Block("INVALID_URL", "Endereço inválido.");
        if (rawUri.Length > MaxInputLength || ContainsControlCharacters(rawUri))
            return BrowserNavigationDecision.Block("INVALID_URL", "Endereço inválido.");
        if (!Uri.TryCreate(rawUri, UriKind.Absolute, out var uri))
            return BrowserNavigationDecision.Block("INVALID_URL", "Endereço inválido.");
        if (allowAboutBlank && uri.Scheme.Equals("about", StringComparison.OrdinalIgnoreCase) && uri.OriginalString.Equals("about:blank", StringComparison.OrdinalIgnoreCase))
            return BrowserNavigationDecision.Allow(uri);
        return ValidateExternalUri(uri, fromAddressBar: false);
    }

    public bool IsBlockedRequest(string? rawUri)
    {
        if (!Uri.TryCreate(rawUri, UriKind.Absolute, out var uri)) return true;
        if (uri.Scheme is "blob" or "data") return false;
        if (uri.Scheme.Equals("about", StringComparison.OrdinalIgnoreCase) && uri.OriginalString.Equals("about:blank", StringComparison.OrdinalIgnoreCase)) return false;
        return !ValidateExternalUri(uri, fromAddressBar: false).Allowed;
    }

    public string DisplayUri(Uri uri)
    {
        if (!uri.IsAbsoluteUri) return uri.OriginalString;
        if (uri.Scheme is not ("http" or "https")) return uri.OriginalString;
        var builder = new UriBuilder(uri) { Host = uri.IdnHost };
        return builder.Uri.AbsoluteUri;
    }

    private BrowserNavigationDecision ValidateExternalUri(Uri uri, bool fromAddressBar)
    {
        var scheme = uri.Scheme.ToLowerInvariant();
        if (BlockedSchemes.Contains(scheme))
            return BrowserNavigationDecision.Block("SCHEME_BLOCKED", $"O esquema '{scheme}:' não é permitido.");
        if (scheme is "blob" or "data")
            return fromAddressBar
                ? BrowserNavigationDecision.Block("SCHEME_BLOCKED", "Este tipo de endereço só pode ser aberto por uma página já carregada.")
                : BrowserNavigationDecision.Allow(uri);
        if (scheme is not ("http" or "https"))
            return BrowserNavigationDecision.Block("SCHEME_BLOCKED", "Este tipo de link não é suportado pelo Navegador CloudOS.");
        if (!string.IsNullOrEmpty(uri.UserInfo))
            return BrowserNavigationDecision.Block("USERINFO_BLOCKED", "Usuário ou senha embutidos na URL não são permitidos.");

        string asciiHost;
        try
        {
            asciiHost = new IdnMapping().GetAscii(uri.IdnHost.TrimEnd('.'));
        }
        catch (ArgumentException)
        {
            return BrowserNavigationDecision.Block("INVALID_IDN", "O domínio internacional não pôde ser normalizado com segurança.");
        }
        if (string.IsNullOrWhiteSpace(asciiHost)) return BrowserNavigationDecision.Block("INVALID_HOST", "Host inválido.");

        var normalized = new UriBuilder(uri) { Host = asciiHost }.Uri;
        if (_blockedOrigins.Contains(Origin(normalized)))
            return BrowserNavigationDecision.Block("CLOUDOS_ORIGIN_BLOCKED", "Este endereço pertence à infraestrutura privada do CloudOS.");
        return BrowserNavigationDecision.Allow(normalized);
    }

    private void AddBlockedOrigin(Uri uri)
    {
        if (uri.IsAbsoluteUri) _blockedOrigins.Add(Origin(uri));
    }

    private static string Origin(Uri uri)
    {
        var port = uri.IsDefaultPort ? -1 : uri.Port;
        return $"{uri.Scheme.ToLowerInvariant()}://{uri.IdnHost.ToLowerInvariant()}:{port}";
    }

    private static bool ContainsControlCharacters(string value) => value.Any(char.IsControl);

    private static bool LooksLikeLocalHost(string value)
    {
        var host = value.Split('/', 2)[0].Split(':', 2)[0];
        return host.Equals("localhost", StringComparison.OrdinalIgnoreCase) || IPAddress.TryParse(host, out var ip) && IPAddress.IsLoopback(ip);
    }

    private static bool LooksLikeDomain(string value)
    {
        if (value.Any(char.IsWhiteSpace)) return false;
        var host = value.Split('/', 2)[0].Split(':', 2)[0];
        return host.Contains('.', StringComparison.Ordinal) && !host.StartsWith('.', StringComparison.Ordinal) && !host.EndsWith('.', StringComparison.Ordinal);
    }
}
