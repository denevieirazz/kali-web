using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Windows.Threading;
using CloudOS.Host.Native;
using CloudOS.Host.Security;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace CloudOS.Host.Bridge;

public sealed class WebMessageBridge : IDisposable
{
    private const int MaxMessageLength = 32 * 1024;
    private static readonly Regex AppIdPattern = new("^native-[a-f0-9]{24}$", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private static readonly HashSet<string> BrokerProcessNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "explorer", "wsl", "wslhost", "wslservice", "msrdc", "mstsc", "dwm"
    };

    private readonly WebView2 _webView;
    private readonly Uri _trustedDocumentOrigin;
    private readonly Uri _backendOrigin;
    private readonly NativeWindowManager _windows;
    private readonly Dispatcher _dispatcher;
    private readonly Action<bool> _setFullscreen;
    private readonly Action _requestClose;
    private readonly Func<object> _getHostState;
    private readonly Func<Task>? _onHandshake;
    private readonly HttpClient _http = new(new HttpClientHandler { UseProxy = false, Proxy = null })
    {
        Timeout = TimeSpan.FromSeconds(35)
    };
    private readonly Dictionary<long, string> _sessionIdsByHandle = new();
    private readonly Dictionary<string, long> _handlesBySessionId = new(StringComparer.Ordinal);
    private readonly HashSet<Guid> _inFlight = new();
    private readonly Queue<DateTime> _recentMessages = new();
    private readonly DispatcherTimer _refreshTimer;
    private readonly string _nonce = Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
    private bool _handshakeComplete;
    private bool _disposed;
    private string? _injectedScriptId;

    public WebMessageBridge(
        WebView2 webView,
        Uri trustedDocumentOrigin,
        Uri backendOrigin,
        NativeWindowManager windows,
        Dispatcher dispatcher,
        Action<bool> setFullscreen,
        Action requestClose,
        Func<object> getHostState,
        Func<Task>? onHandshake = null)
    {
        _webView = webView;
        _trustedDocumentOrigin = trustedDocumentOrigin;
        _backendOrigin = backendOrigin;
        _windows = windows;
        _dispatcher = dispatcher;
        _setFullscreen = setFullscreen;
        _requestClose = requestClose;
        _getHostState = getHostState;
        _onHandshake = onHandshake;
        _windows.WindowChanged += OnNativeWindowChanged;
        _refreshTimer = new DispatcherTimer(TimeSpan.FromMilliseconds(1200), DispatcherPriority.Background, (_, _) =>
        {
            try { _windows.Refresh(); } catch (ObjectDisposedException) { }
        }, dispatcher);
    }

    public async Task AttachAsync()
    {
        var trustedOriginJson = JsonSerializer.Serialize(_trustedDocumentOrigin.GetLeftPart(UriPartial.Authority));
        var nonceJson = JsonSerializer.Serialize(_nonce);
        var script = $$"""
            (() => {
              if (globalThis.location.origin !== {{trustedOriginJson}}) return;
              Object.defineProperty(window, '__cloudosNativeNonce', {
                value: {{nonceJson}}, configurable: false, enumerable: false, writable: false
              });
            })();
            """;
        _injectedScriptId = await _webView.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(script);
        _webView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;
        _refreshTimer.Start();
    }

    public void ResetDocument() => _handshakeComplete = false;

    private async void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs eventArgs)
    {
        string? idText = null;
        Guid requestId = default;
        var registered = false;
        try
        {
            var raw = eventArgs.WebMessageAsJson;
            if (raw.Length > MaxMessageLength) throw new BridgeException("MESSAGE_TOO_LARGE", "Mensagem nativa excede o limite.");
            if (!NavigationPolicy.IsTrustedSource(eventArgs.Source, _trustedDocumentOrigin) ||
                _webView.Source is null || !NavigationPolicy.IsTrustedDocument(_webView.Source, _trustedDocumentOrigin))
                throw new BridgeException("UNTRUSTED_SOURCE", "Origem não confiável.");
            EnforceRateLimit();

            using var document = JsonDocument.Parse(raw, new JsonDocumentOptions { MaxDepth = 16 });
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw new BridgeException("INVALID_MESSAGE", "Envelope inválido.");
            RejectUnknownProperties(root, "v", "id", "type", "method", "nonce", "params");
            if (ReadInt(root, "v") != 1 || ReadString(root, "type") != "request")
                throw new BridgeException("UNSUPPORTED_PROTOCOL", "Versão de ponte não suportada.");
            idText = ReadString(root, "id");
            if (!Guid.TryParse(idText, out requestId) || idText.Length > 64)
                throw new BridgeException("INVALID_ID", "ID de requisição inválido.");
            if (!_inFlight.Add(requestId)) throw new BridgeException("DUPLICATE_ID", "ID de requisição duplicado.");
            registered = true;
            if (ReadString(root, "nonce") != _nonce) throw new BridgeException("STALE_DOCUMENT", "Documento expirado.");
            var method = ReadString(root, "method");
            var parameters = root.TryGetProperty("params", out var value) ? value : default;

            if (!_handshakeComplete && method != "bridge.handshake")
                throw new BridgeException("HANDSHAKE_REQUIRED", "A ponte ainda não foi inicializada.");

            var result = await DispatchAsync(method, parameters);
            PostResponse(idText, true, result, null);
        }
        catch (BridgeException error)
        {
            if (idText is not null) PostResponse(idText, false, null, new { code = error.Code, message = error.Message });
        }
        catch
        {
            if (idText is not null) PostResponse(idText, false, null, new { code = "INTERNAL_ERROR", message = "A operação nativa não pôde ser concluída." });
        }
        finally
        {
            if (registered) _inFlight.Remove(requestId);
        }
    }

    private async Task<object?> DispatchAsync(string method, JsonElement parameters)
    {
        switch (method)
        {
            case "bridge.handshake":
                _handshakeComplete = true;
                if (_onHandshake is not null) await _onHandshake();
                return new { protocol = 1, host = _getHostState(), sessions = GetPublicSessions() };
            case "host.getState":
                return _getHostState();
            case "host.setFullscreen":
                _setFullscreen(ReadBooleanParameter(parameters, "enabled"));
                return _getHostState();
            case "host.requestClose":
                _ = _dispatcher.BeginInvoke(_requestClose);
                return new { closing = true };
            case "native.launchApp":
                return await LaunchAppAsync(parameters);
            case "native.sessions.list":
                return new { sessions = GetPublicSessions() };
            case "native.session.focus":
                return Operate(parameters, _windows.TryFocus);
            case "native.session.minimize":
                return Operate(parameters, _windows.TryMinimize);
            case "native.session.maximize":
                return Operate(parameters, _windows.TryMaximize);
            case "native.session.restore":
                return Operate(parameters, _windows.TryRestore);
            case "native.session.close":
                return Operate(parameters, _windows.TryClose);
            case "host.requestLegacyRecoveryToken":
                return await RequestLegacyRecoveryTokenAsync();
            default:
                throw new BridgeException("METHOD_NOT_ALLOWED", "Método não permitido.");
        }
    }

    private async Task<object> RequestLegacyRecoveryTokenAsync()
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_backendOrigin, "/api/auth/legacy-recovery/issue-token"));
        var supervisorToken = Environment.GetEnvironmentVariable("CLOUDOS_SUPERVISOR_TOKEN");
        if (!string.IsNullOrEmpty(supervisorToken))
        {
            request.Headers.Add("X-CloudOS-Supervisor-Token", supervisorToken);
        }
        var leaseToken = Environment.GetEnvironmentVariable("CLOUDOS_HOST_LEASE_TOKEN");
        if (!string.IsNullOrEmpty(leaseToken))
        {
            request.Headers.Add("X-CloudOS-Host-Token", leaseToken);
        }
        request.Content = new StringContent("{}", Encoding.UTF8, "application/json");
        using var response = await _http.SendAsync(request);
        if (!response.IsSuccessStatusCode)
        {
            throw new BridgeException("LEGACY_RECOVERY_DENIED", "O host nativo não pôde autorizar a recuperação local.");
        }
        await using var body = await response.Content.ReadAsStreamAsync();
        var result = await JsonSerializer.DeserializeAsync<JsonElement>(body);
        return result;
    }

    private async Task<object> LaunchAppAsync(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "appId", "token");
        var appId = ReadString(parameters, "appId");
        var token = ReadString(parameters, "token");
        if (!AppIdPattern.IsMatch(appId)) throw new BridgeException("INVALID_APP_ID", "Aplicativo inválido.");
        if (token.Length is < 16 or > 8192) throw new BridgeException("INVALID_AUTH", "Sessão inválida.");

        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_backendOrigin, $"/api/apps/{Uri.EscapeDataString(appId)}/launch"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = new StringContent("{}", Encoding.UTF8, "application/json");
        using var response = await _http.SendAsync(request);
        if (!response.IsSuccessStatusCode)
        {
            var message = response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden
                ? "Sessão expirada. Entre novamente no CloudOS."
                : "O aplicativo não pôde ser iniciado pelo agente local.";
            throw new BridgeException("APP_LAUNCH_FAILED", message);
        }

        await using var body = await response.Content.ReadAsStreamAsync();
        var launched = await JsonSerializer.DeserializeAsync<LaunchResponse>(body)
            ?? throw new BridgeException("APP_LAUNCH_FAILED", "Resposta de lançamento inválida.");
        var managed = false;
        string? managementReason = null;
        if (launched.Pid > 0)
        {
            try
            {
                using var process = Process.GetProcessById(launched.Pid);
                if (BrokerProcessNames.Contains(process.ProcessName))
                {
                    managementReason = "A janela usa um broker compartilhado do Windows/WSLg.";
                }
                else
                {
                    _windows.TrackLaunchedProcess(process);
                    managed = true;
                }
            }
            catch
            {
                managementReason = "O processo entregou a janela a outro componente do Windows.";
            }
        }

        return new
        {
            name = launched.Name,
            source = launched.Source,
            distribution = launched.Distribution,
            pid = launched.Pid,
            windowMode = managed ? "native-managed" : launched.WindowMode,
            managed,
            managementReason
        };
    }

    private object Operate(JsonElement parameters, NativeOperation operation)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId");
        var sessionId = ReadString(parameters, "sessionId");
        if (!_handlesBySessionId.TryGetValue(sessionId, out var handle))
            throw new BridgeException("SESSION_NOT_FOUND", "Janela não encontrada.");
        if (!operation(handle, out var error))
            throw new BridgeException("WINDOW_OPERATION_DENIED", error ?? "O Windows recusou a operação.");
        return new { sessionId, accepted = true };
    }

    private void OnNativeWindowChanged(object? sender, NativeWindowChangedEventArgs eventArgs)
    {
        _dispatcher.BeginInvoke(() =>
        {
            if (_disposed) return;
            var handle = eventArgs.Window.Handle;
            if (eventArgs.Kind == NativeWindowChangeKind.Removed)
            {
                if (_sessionIdsByHandle.Remove(handle, out var removed)) _handlesBySessionId.Remove(removed);
            }
            else if (!_sessionIdsByHandle.ContainsKey(handle))
            {
                var sessionId = $"window-{Guid.NewGuid():N}";
                _sessionIdsByHandle[handle] = sessionId;
                _handlesBySessionId[sessionId] = handle;
            }
            PostEvent("native.sessionsChanged", new { sessions = GetPublicSessions() });
        }, DispatcherPriority.Background);
    }

    private object[] GetPublicSessions()
    {
        var snapshots = _windows.GetWindows();
        var sessions = new List<object>();
        foreach (var window in snapshots.OrderBy(window => window.ProcessId).ThenBy(window => window.Title, StringComparer.OrdinalIgnoreCase))
        {
            if (!_sessionIdsByHandle.TryGetValue(window.Handle, out var sessionId))
            {
                sessionId = $"window-{Guid.NewGuid():N}";
                _sessionIdsByHandle[window.Handle] = sessionId;
                _handlesBySessionId[sessionId] = window.Handle;
            }
            sessions.Add(new
            {
                sessionId,
                title = string.IsNullOrWhiteSpace(window.Title) ? $"Aplicativo {window.ProcessId}" : window.Title,
                processId = window.ProcessId,
                minimized = window.IsMinimized,
                maximized = window.IsMaximized,
                bounds = new { x = window.Bounds.X, y = window.Bounds.Y, width = window.Bounds.Width, height = window.Bounds.Height }
            });
        }
        return sessions.ToArray();
    }

    private void PostResponse(string id, bool ok, object? result, object? error)
    {
        if (_disposed || _webView.CoreWebView2 is null) return;
        _webView.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { v = 1, id, type = "response", ok, result, error }));
    }

    private void PostEvent(string eventName, object data)
    {
        if (!_handshakeComplete || _disposed || _webView.CoreWebView2 is null) return;
        _webView.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { v = 1, type = "event", @event = eventName, data }));
    }

    private void EnforceRateLimit()
    {
        var now = DateTime.UtcNow;
        while (_recentMessages.Count > 0 && now - _recentMessages.Peek() > TimeSpan.FromSeconds(2)) _recentMessages.Dequeue();
        if (_recentMessages.Count >= 100) throw new BridgeException("RATE_LIMITED", "Muitas solicitações nativas.");
        _recentMessages.Enqueue(now);
    }

    private static void RequireObject(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object) throw new BridgeException("INVALID_PARAMS", "Parâmetros inválidos.");
    }

    private static string ReadString(JsonElement element, string property)
    {
        if (!element.TryGetProperty(property, out var value) || value.ValueKind != JsonValueKind.String)
            throw new BridgeException("INVALID_PARAMS", $"Campo {property} inválido.");
        return value.GetString()!;
    }

    private static int ReadInt(JsonElement element, string property)
    {
        if (!element.TryGetProperty(property, out var value) || !value.TryGetInt32(out var result))
            throw new BridgeException("INVALID_PARAMS", $"Campo {property} inválido.");
        return result;
    }

    private static bool ReadBooleanParameter(JsonElement parameters, string property)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, property);
        if (!parameters.TryGetProperty(property, out var value) || value.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            throw new BridgeException("INVALID_PARAMS", $"Campo {property} inválido.");
        return value.GetBoolean();
    }

    private static void RejectUnknownProperties(JsonElement element, params string[] allowed)
    {
        var names = new HashSet<string>(allowed, StringComparer.Ordinal);
        foreach (var property in element.EnumerateObject())
            if (!names.Contains(property.Name)) throw new BridgeException("INVALID_PARAMS", $"Campo desconhecido: {property.Name}.");
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _refreshTimer.Stop();
        _windows.WindowChanged -= OnNativeWindowChanged;
        try
        {
            var core = _webView.CoreWebView2;
            if (core is not null)
            {
                core.WebMessageReceived -= OnWebMessageReceived;
                if (_injectedScriptId is not null)
                    core.RemoveScriptToExecuteOnDocumentCreated(_injectedScriptId);
            }
        }
        catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException or System.Runtime.InteropServices.COMException)
        {
            // A failed WebView2 process may reject cleanup. The control itself is
            // recreated by a full host restart; disposal must remain non-throwing.
        }
        _injectedScriptId = null;
        _handshakeComplete = false;
        _inFlight.Clear();
        _recentMessages.Clear();
        _sessionIdsByHandle.Clear();
        _handlesBySessionId.Clear();
        _http.Dispose();
    }

    private delegate bool NativeOperation(long handle, out string error);

    private sealed class BridgeException(string code, string message) : Exception(message)
    {
        public string Code { get; } = code;
    }

    private sealed class LaunchResponse
    {
        [JsonPropertyName("name")] public string? Name { get; init; }
        [JsonPropertyName("source")] public string? Source { get; init; }
        [JsonPropertyName("distribution")] public string? Distribution { get; init; }
        [JsonPropertyName("pid")] public int Pid { get; init; }
        [JsonPropertyName("windowMode")] public string? WindowMode { get; init; }
    }
}
