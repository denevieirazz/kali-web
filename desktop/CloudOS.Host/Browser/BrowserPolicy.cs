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
        AddBackendLoopbackOrigins(backendOrigin);
    }

    public BrowserNavigationDecision ParseAddressInput(string? raw)
    {
        var input = (raw ?? string.Empty).Trim();
        if (input.Length == 0) return BrowserNavigationDecision.Allow(new Uri(HomeUrl));
        if (input.Length > MaxInputLength)
            return BrowserNavigationDecision.Block("URL_TOO_LONG", "O endereço excede o limite permitido.");
        if (ContainsControlCharacters(input))
            return BrowserNavigationDecision.Block("INVALID_URL", "O endereço contém caracteres de controle.");

        foreach (var scheme in BlockedSchemes)
        {
            if (input.StartsWith(scheme + ":", StringComparison.OrdinalIgnoreCase))
                return BrowserNavigationDecision.Block("SCHEME_BLOCKED", $"O esquema '{scheme}:' não é permitido.");
        }
        if (input.StartsWith("data:", StringComparison.OrdinalIgnoreCase) ||
            input.StartsWith("blob:", StringComparison.OrdinalIgnoreCase) ||
            input.StartsWith("about:", StringComparison.OrdinalIgnoreCase))
            return BrowserNavigationDecision.Block("SCHEME_BLOCKED", "Este tipo de endereço não pode ser digitado na barra.");

        if (input.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            input.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            return Uri.TryCreate(input, UriKind.Absolute, out var explicitUri)
                ? ValidateExternalUri(explicitUri, fromAddressBar: true)
                : BrowserNavigationDecision.Block("INVALID_URL", "Endereço inválido.");
        }

        if (TryCreateHostInput(input, out var hostUri))
            return ValidateExternalUri(hostUri, fromAddressBar: true);

        if (Uri.TryCreate(input, UriKind.Absolute, out var absolute))
            return ValidateExternalUri(absolute, fromAddressBar: true);

        var search = new Uri(SearchBaseUrl + Uri.EscapeDataString(input));
        return BrowserNavigationDecision.Allow(search, isSearch: true);
    }

    public BrowserNavigationDecision ValidateNavigation(string? rawUri, bool allowAboutBlank = false)
    {
        if (string.IsNullOrWhiteSpace(rawUri))
            return BrowserNavigationDecision.Block("INVALID_URL", "Endereço inválido.");
        if (rawUri.Length > MaxInputLength || ContainsControlCharacters(rawUri))
            return BrowserNavigationDecision.Block("INVALID_URL", "Endereço inválido.");
        if (!Uri.TryCreate(rawUri, UriKind.Absolute, out var uri))
            return BrowserNavigationDecision.Block("INVALID_URL", "Endereço inválido.");
        if (allowAboutBlank && uri.Scheme.Equals("about", StringComparison.OrdinalIgnoreCase) &&
            uri.OriginalString.Equals("about:blank", StringComparison.OrdinalIgnoreCase))
            return BrowserNavigationDecision.Allow(uri);
        return ValidateExternalUri(uri, fromAddressBar: false);
    }

    public bool IsBlockedRequest(string? rawUri)
    {
        if (!Uri.TryCreate(rawUri, UriKind.Absolute, out var uri)) return true;
        if (uri.Scheme is "blob" or "data") return false;
        if (uri.Scheme.Equals("about", StringComparison.OrdinalIgnoreCase) &&
            uri.OriginalString.Equals("about:blank", StringComparison.OrdinalIgnoreCase)) return false;
        return !ValidateExternalUri(uri, fromAddressBar: false).Allowed;
    }

    public string DisplayUri(Uri uri)
    {
        if (!uri.IsAbsoluteUri || uri.Scheme is not ("http" or "https")) return uri.OriginalString;
        var normalizedHost = NormalizeHost(uri);
        if (normalizedHost is null) return uri.AbsoluteUri;
        var builder = new UriBuilder(uri) { Host = normalizedHost };
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

        var asciiHost = NormalizeHost(uri);
        if (string.IsNullOrWhiteSpace(asciiHost))
            return BrowserNavigationDecision.Block("INVALID_IDN", "O domínio não pôde ser normalizado com segurança.");

        Uri normalized;
        try
        {
            normalized = new UriBuilder(uri) { Host = asciiHost }.Uri;
        }
        catch (UriFormatException)
        {
            return BrowserNavigationDecision.Block("INVALID_URL", "Endereço inválido.");
        }

        if (_blockedOrigins.Contains(Origin(normalized)))
            return BrowserNavigationDecision.Block("CLOUDOS_ORIGIN_BLOCKED", "Este endereço pertence à infraestrutura privada do CloudOS.");
        return BrowserNavigationDecision.Allow(normalized);
    }

    private static string? NormalizeHost(Uri uri)
    {
        var rawHost = uri.Host.Trim().TrimEnd('.');
        if (rawHost.StartsWith("[", StringComparison.Ordinal) && rawHost.EndsWith("]", StringComparison.Ordinal))
            rawHost = rawHost[1..^1];
        if (IPAddress.TryParse(rawHost, out var ip)) return ip.ToString().ToLowerInvariant();
        try
        {
            return new IdnMapping().GetAscii(uri.IdnHost.TrimEnd('.')).ToLowerInvariant();
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    private static bool TryCreateHostInput(string input, out Uri uri)
    {
        uri = null!;
        if (input.Any(char.IsWhiteSpace)) return false;

        if (IPAddress.TryParse(input.Trim('[', ']'), out var bareIp))
        {
            var scheme = IPAddress.IsLoopback(bareIp) ? "http" : "https";
            var builder = new UriBuilder(scheme, bareIp.ToString());
            uri = builder.Uri;
            return true;
        }

        foreach (var scheme in new[] { "https", "http" })
        {
            if (!Uri.TryCreate($"{scheme}://{input}", UriKind.Absolute, out var candidate)) continue;
            var host = candidate.Host.Trim('[', ']');
            var isLocalHost = host.Equals("localhost", StringComparison.OrdinalIgnoreCase);
            var isIp = IPAddress.TryParse(host, out var parsedIp);
            var isDomain = host.Contains(".", StringComparison.Ordinal) &&
                           !host.StartsWith(".", StringComparison.Ordinal) &&
                           !host.EndsWith(".", StringComparison.Ordinal);
            if (!isLocalHost && !isIp && !isDomain) continue;

            var desiredScheme = isLocalHost || isIp && parsedIp is not null && IPAddress.IsLoopback(parsedIp)
                ? "http"
                : "https";
            var builder = new UriBuilder(candidate) { Scheme = desiredScheme };
            if ((desiredScheme == "https" && candidate.Port == 80) || (desiredScheme == "http" && candidate.Port == 443))
                builder.Port = -1;
            uri = builder.Uri;
            return true;
        }
        return false;
    }

    private void AddBackendLoopbackOrigins(Uri backendOrigin)
    {
        AddBlockedOrigin(backendOrigin);
        var host = backendOrigin.Host.Trim('[', ']');
        var isLoopback = host.Equals("localhost", StringComparison.OrdinalIgnoreCase) ||
                         IPAddress.TryParse(host, out var ip) && IPAddress.IsLoopback(ip);
        if (!isLoopback) return;

        foreach (var alias in new[] { "127.0.0.1", "localhost", "::1" })
        {
            try
            {
                var builder = new UriBuilder(backendOrigin) { Host = alias };
                AddBlockedOrigin(builder.Uri);
            }
            catch (UriFormatException)
            {
                // Ignore only an alias the platform cannot represent; the canonical backend origin remains blocked.
            }
        }
    }

    private void AddBlockedOrigin(Uri uri)
    {
        if (uri.IsAbsoluteUri) _blockedOrigins.Add(Origin(uri));
    }

    private static string Origin(Uri uri)
    {
        var host = NormalizeHost(uri) ?? uri.IdnHost.ToLowerInvariant();
        return $"{uri.Scheme.ToLowerInvariant()}://{host}:{uri.Port}";
    }

    private static bool ContainsControlCharacters(string value) => value.Any(char.IsControl);
}
