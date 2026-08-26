using System.Text.Json;

namespace CloudOS.Host.Security;

public static class RuntimeBootstrapScript
{
    public static string Build(Uri backendOrigin)
    {
        ValidateBackendOrigin(backendOrigin);

        var apiBase = backendOrigin.GetLeftPart(UriPartial.Authority);
        var websocket = new UriBuilder(backendOrigin)
        {
            Scheme = "ws",
            Path = string.Empty,
            Query = string.Empty,
            Fragment = string.Empty
        }.Uri.GetLeftPart(UriPartial.Authority);

        var runtimeJson = JsonSerializer.Serialize(new
        {
            apiBase,
            webSocketBase = websocket
        });
        var shellOriginJson = JsonSerializer.Serialize(CloudOsOrigins.ShellOrigin);
        var policyJson = JsonSerializer.Serialize(BuildContentSecurityPolicy(apiBase, websocket));

        // AddScriptToExecuteOnDocumentCreatedAsync also runs in child frames.
        // The exact-origin guard prevents external Browser-app frames from
        // receiving the agent endpoint or the shell policy.
        return $$"""
            (() => {
              'use strict';
              if (globalThis.location.origin !== {{shellOriginJson}}) return;

              const runtime = Object.freeze({{runtimeJson}});
              Object.defineProperty(globalThis, '__CLOUDOS_RUNTIME__', {
                value: runtime,
                configurable: false,
                enumerable: false,
                writable: false
              });

              const installPolicy = () => {
                if (document.querySelector('meta[data-cloudos-host-csp="v1"]')) return true;
                const parent = document.head || document.documentElement;
                if (!parent) return false;
                const policy = document.createElement('meta');
                policy.httpEquiv = 'Content-Security-Policy';
                policy.content = {{policyJson}};
                policy.dataset.cloudosHostCsp = 'v1';
                parent.prepend(policy);
                return true;
              };

              if (!installPolicy()) {
                const observer = new MutationObserver(() => {
                  if (installPolicy()) observer.disconnect();
                });
                observer.observe(document, { childList: true, subtree: true });
              }
            })();
            """;
    }

    private static string BuildContentSecurityPolicy(string apiBase, string websocketBase)
    {
        // The shell currently executes locally installed OSL/SDK programs via
        // Function and renders extensive React inline styles, hence the two
        // narrowly documented allowances. Network access is otherwise bounded
        // to the authenticated agent, HTTPS sync endpoints and framed HTTPS
        // pages opened by the built-in Browser app.
        return string.Join("; ", new[]
        {
            "default-src 'self'",
            "base-uri 'none'",
            "object-src 'none'",
            "script-src 'self' 'unsafe-eval'",
            "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data: blob: https:",
            "font-src 'self' data:",
            "media-src 'self' data: blob:",
            "worker-src 'self' blob:",
            $"connect-src 'self' {apiBase} {websocketBase} https:",
            "frame-src https: http://localhost:* http://127.0.0.1:*",
            "form-action 'self'",
            "manifest-src 'self'"
        });
    }

    private static void ValidateBackendOrigin(Uri origin)
    {
        if (!origin.IsAbsoluteUri ||
            origin.Scheme != Uri.UriSchemeHttp ||
            !origin.Host.Equals("127.0.0.1", StringComparison.Ordinal) ||
            origin.Port is < 1 or > 65535 ||
            !string.IsNullOrEmpty(origin.UserInfo) ||
            origin.AbsolutePath != "/" ||
            !string.IsNullOrEmpty(origin.Query) ||
            !string.IsNullOrEmpty(origin.Fragment))
        {
            throw new ArgumentException("O endpoint do agente deve ser uma origem HTTP loopback sem credenciais ou caminho.", nameof(origin));
        }
    }
}
