namespace CloudOS.Host.Security;

/// <summary>
/// Origins owned by the native shell. Keeping this value independent from the
/// agent's ephemeral port preserves WebView2 storage partitions across boots.
/// </summary>
public static class CloudOsOrigins
{
    // *.localhost is a potentially trustworthy origin in Chromium even over
    // HTTP. That keeps OPFS available without introducing HTTPS-to-HTTP mixed
    // content when the shell talks to the loopback-only agent.
    public const string ShellOrigin = "http://cloudos.localhost";

    public static Uri ShellBaseUri { get; } = new($"{ShellOrigin}/", UriKind.Absolute);
}
