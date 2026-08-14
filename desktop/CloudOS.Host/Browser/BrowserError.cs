namespace CloudOS.Host.Browser;

public sealed record BrowserError(string Code, string Message, string? Uri, bool CanRetry)
{
    public static BrowserError Blocked(string code, string message, string? uri) => new(code, message, uri, false);
    public static BrowserError Navigation(string code, string message, string? uri, bool retry = true) => new(code, message, uri, retry);
}
