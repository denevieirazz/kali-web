namespace CloudOS.Host.Browser;

public enum BrowserPermissionDisposition
{
    Deny,
    Prompt
}

public static class BrowserSecurityPolicy
{
    private static readonly HashSet<string> PromptPermissions = new(StringComparer.Ordinal)
    {
        "Camera",
        "Microphone",
        "Geolocation",
        "Notifications",
        "MultipleAutomaticDownloads"
    };

    public static BrowserPermissionDisposition Permission(string permissionKind) =>
        PromptPermissions.Contains(permissionKind) ? BrowserPermissionDisposition.Prompt : BrowserPermissionDisposition.Deny;

    public static bool SavesPermissionInProfile => false;
    public static bool AllowsInvalidServerCertificate => false;

    public static bool IsSameOrigin(string requestedSource, string? currentSource)
    {
        if (!Uri.TryCreate(requestedSource, UriKind.Absolute, out var requested) ||
            !Uri.TryCreate(currentSource, UriKind.Absolute, out var current) ||
            !string.IsNullOrEmpty(requested.UserInfo) ||
            !string.IsNullOrEmpty(current.UserInfo))
            return false;

        return requested.Scheme.Equals(current.Scheme, StringComparison.OrdinalIgnoreCase) &&
               requested.IdnHost.Equals(current.IdnHost, StringComparison.OrdinalIgnoreCase) &&
               requested.Port == current.Port;
    }
}

public static class BrowserCrashPolicy
{
    public static readonly TimeSpan RecoveryWindow = TimeSpan.FromSeconds(30);

    public static bool ShouldRecover(DateTimeOffset? previousCrash, DateTimeOffset now) =>
        previousCrash is null || now - previousCrash.Value > RecoveryWindow;
}
