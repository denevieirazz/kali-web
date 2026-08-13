namespace CloudOS.Host.Security;

public static class NavigationPolicy
{
    public static bool IsTrustedDocument(Uri candidate, Uri trustedOrigin)
    {
        return candidate.IsAbsoluteUri
            && trustedOrigin.IsAbsoluteUri
            && candidate.Scheme.Equals(trustedOrigin.Scheme, StringComparison.OrdinalIgnoreCase)
            && candidate.IdnHost.Equals(trustedOrigin.IdnHost, StringComparison.OrdinalIgnoreCase)
            && candidate.Port == trustedOrigin.Port
            && string.IsNullOrEmpty(candidate.UserInfo);
    }

    public static bool IsTrustedSource(string source, Uri trustedOrigin)
    {
        return Uri.TryCreate(source, UriKind.Absolute, out var candidate)
            && IsTrustedDocument(candidate, trustedOrigin);
    }
}
