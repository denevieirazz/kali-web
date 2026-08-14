using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;

namespace CloudOS.Host.Browser;

public static class BrowserDiagnostics
{
    private static readonly object Sync = new();
    private static readonly Regex Sensitive = new(
        "(?i)(authorization|bearer|jwt|token|password|passwd|secret|recovery[_-]?code|api[_-]?key)(\\s*[:=]\\s*|\\s+)[^\\s,;]+",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public static void Write(string eventName, string? detail = null)
    {
        var safeEvent = SanitizeEvent(eventName);
        var safeDetail = SanitizeDetail(detail);
        var line = $"{DateTimeOffset.Now:O} {safeEvent}{(safeDetail.Length == 0 ? string.Empty : " " + safeDetail)}{Environment.NewLine}";
        try
        {
            var logDirectory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "CloudOS",
                "logs");
            Directory.CreateDirectory(logDirectory);
            var path = Path.Combine(logDirectory, $"browser-{DateTime.UtcNow:yyyyMMdd}.log");
            lock (Sync) File.AppendAllText(path, line);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            Trace.TraceWarning("CloudOS Browser diagnostic log failed: {0}", error.GetType().Name);
        }
    }

    private static string SanitizeEvent(string value)
    {
        var safe = new string(value.Where(character =>
            char.IsAsciiLetterOrDigit(character) || character is '_' or '-').ToArray());
        return string.IsNullOrWhiteSpace(safe) ? "browser_event" : safe[..Math.Min(safe.Length, 64)];
    }

    private static string SanitizeDetail(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return string.Empty;
        var safe = Sensitive.Replace(value.Replace('\r', ' ').Replace('\n', ' '), "$1=<redacted>");
        return safe[..Math.Min(safe.Length, 512)];
    }
}
