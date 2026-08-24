using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Windows.Threading;
using System.Windows.Media;
using CloudOS.Host.Browser;
using CloudOS.Host.Native;
using CloudOS.Host.Security;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace CloudOS.Host.Bridge;

public sealed class WebMessageBridge : IDisposable
{
    private const int MaxMessageLength = 32 * 1024;
    private const int IdleRefreshMilliseconds = 1_200;
    private const int ActiveContainmentRefreshMilliseconds = 100;
    private static readonly Regex AppIdPattern = new("^native-[a-f0-9]{24}$", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private readonly WebView2 _webView;
    private readonly Uri _trustedDocumentOrigin;
    private readonly Uri _backendOrigin;
    private readonly string? _supervisorToken;
    private readonly string? _hostLeaseToken;
    private readonly long _ownerWindowHandle;
    private readonly NativeWindowManager _windows;
    private readonly BrowserManager _browserManager;
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
    private readonly Dictionary<string, int> _processIdsBySessionId = new(StringComparer.Ordinal);
    private readonly Dictionary<int, NativeContainedProcessLease> _launchLeasesByProcessId = new();
    private readonly Dictionary<int, int> _launchRootByMemberProcessId = new();
    private readonly Dictionary<int, (DateTimeOffset Deadline, NativeContainmentFailure Failure)> _terminationRetriesByRoot = new();
    private readonly Dictionary<long, AttachedSurfaceRequest> _surfacesByHandle = new();
    private readonly Dictionary<long, DateTimeOffset> _pendingAttachDeadlinesByHandle = new();
    private readonly HashSet<Guid> _inFlight = new();
    private readonly Queue<DateTime> _recentMessages = new();
    private readonly DispatcherTimer _refreshTimer;
    private readonly string _nonce = Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
    private bool _handshakeComplete;
    private bool _disposed;
    private bool _relayoutPending;
    private string? _injectedScriptId;

    public WebMessageBridge(
        WebView2 webView,
        Uri trustedDocumentOrigin,
        Uri backendOrigin,
        string? supervisorToken,
        string? hostLeaseToken,
        long ownerWindowHandle,
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
        _supervisorToken = supervisorToken;
        _hostLeaseToken = hostLeaseToken;
        _ownerWindowHandle = ownerWindowHandle;
        _windows = windows;
        _dispatcher = dispatcher;
        _setFullscreen = setFullscreen;
        _requestClose = requestClose;
        _getHostState = getHostState;
        _onHandshake = onHandshake;
        var browserDevTools = string.Equals(Environment.GetEnvironmentVariable("CLOUDOS_BROWSER_DEVTOOLS"), "1", StringComparison.Ordinal);
        _browserManager = new BrowserManager(dispatcher, trustedDocumentOrigin, backendOrigin, browserDevTools, BrowserDiagnostics.Write);
        _windows.WindowChanged += OnNativeWindowChanged;
        _refreshTimer = new DispatcherTimer(TimeSpan.FromMilliseconds(IdleRefreshMilliseconds), DispatcherPriority.Background, (_, _) =>
        {
            try
            {
                SynchronizeAllTrackedJobs();
                _windows.Refresh();
                SweepContainmentDeadlines();
            }
            catch (ObjectDisposedException error)
            {
                BrowserDiagnostics.Write("bridge_refresh_stopped", $"type={error.GetType().Name}");
            }
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

    public void ResetDocument()
    {
        _handshakeComplete = false;
        TerminateAllManagedProcesses(NativeContainmentFailure.DocumentReset);
    }

    private async void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs eventArgs)
    {
        string? idText = null;
        string? method = null;
        Guid requestId = default;
        var registered = false;
        try
        {
            var raw = eventArgs.WebMessageAsJson;
            if (raw.Length > MaxMessageLength) throw new BridgeException("MESSAGE_TOO_LARGE", "Mensagem nativa excede o limite.");
            var docUri = _webView.Source ?? (Uri.TryCreate(_webView.CoreWebView2?.Source, UriKind.Absolute, out var u) ? u : null);
            if (!NavigationPolicy.IsTrustedSource(eventArgs.Source, _trustedDocumentOrigin) ||
                docUri is null || !NavigationPolicy.IsTrustedDocument(docUri, _trustedDocumentOrigin))
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
            method = ReadString(root, "method");
            var parameters = root.TryGetProperty("params", out var value) ? value : default;

            if (!_handshakeComplete && method != "bridge.handshake")
                throw new BridgeException("HANDSHAKE_REQUIRED", "A ponte ainda não foi inicializada.");

            if (method == "browser.open") BrowserDiagnostics.Write("bridge_received", null);
            var result = await DispatchAsync(method, parameters);
            PostResponse(idText, true, result, null);
            if (method == "browser.open") BrowserDiagnostics.Write("bridge_replied", "ok=true");
        }
        catch (BridgeException error)
        {
            if (idText is not null) PostResponse(idText, false, null, new { code = error.Code, message = error.Message });
            if (method == "browser.open") BrowserDiagnostics.Write("bridge_replied", $"ok=false code={error.Code}");
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            BrowserDiagnostics.Write("bridge_failed", $"type={error.GetType().Name}");
            if (idText is not null) PostResponse(idText, false, null, new { code = "INTERNAL_ERROR", message = "A operação nativa não pôde ser concluída." });
            if (method == "browser.open") BrowserDiagnostics.Write("bridge_replied", "ok=false code=INTERNAL_ERROR");
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
            case "browser.open":
                return await OpenBrowserAsync(parameters);
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
                return await CloseSessionAsync(parameters);
            case "native.session.attach":
                return Attach(parameters);
            case "native.session.layout":
                return Layout(parameters);
            case "native.session.detach":
                return Detach(parameters);
            case "host.requestLegacyRecoveryToken":
                return await RequestLegacyRecoveryTokenAsync();
            default:
                throw new BridgeException("METHOD_NOT_ALLOWED", "Método não permitido.");
        }
    }

    private async Task<BrowserOpenResult> OpenBrowserAsync(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "url");
        string? url = null;
        if (parameters.TryGetProperty("url", out var value))
        {
            if (value.ValueKind != JsonValueKind.String) throw new BridgeException("INVALID_PARAMS", "URL inválida.");
            url = value.GetString();
            if (url is not null && url.Length > BrowserPolicy.MaxInputLength)
                throw new BridgeException("INVALID_PARAMS", "URL excede o limite permitido.");
        }
        return await _browserManager.OpenAsync(url);
    }

    private async Task<object> RequestLegacyRecoveryTokenAsync()
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_backendOrigin, "/api/auth/legacy-recovery/issue-token"));
        if (!string.IsNullOrEmpty(_supervisorToken)) request.Headers.Add("X-CloudOS-Supervisor-Token", _supervisorToken);
        if (!string.IsNullOrEmpty(_hostLeaseToken)) request.Headers.Add("X-CloudOS-Host-Token", _hostLeaseToken);
        request.Content = new StringContent("{}", Encoding.UTF8, "application/json");
        using var response = await _http.SendAsync(request);
        if (!response.IsSuccessStatusCode)
            throw new BridgeException("LEGACY_RECOVERY_DENIED", "O host nativo não pôde autorizar a recuperação local.");
        await using var body = await response.Content.ReadAsStreamAsync();
        return await JsonSerializer.DeserializeAsync<JsonElement>(body);
    }

    private async Task<object> LaunchAppAsync(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "appId", "token");
        var appId = ReadString(parameters, "appId");
        var token = ReadString(parameters, "token");
        if (!AppIdPattern.IsMatch(appId)) throw new BridgeException("INVALID_APP_ID", "Aplicativo inválido.");
        if (token.Length is < 16 or > 8192) throw new BridgeException("INVALID_AUTH", "Sessão inválida.");

        if (string.IsNullOrWhiteSpace(_hostLeaseToken))
            throw new BridgeException("HOST_CONTAINMENT_UNAVAILABLE", "O Host não possui uma credencial válida para solicitar o descritor de lançamento.");
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_backendOrigin, $"/api/apps/{Uri.EscapeDataString(appId)}/launch"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.Add("X-CloudOS-Host-Token", _hostLeaseToken);
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

        var admission = NativeLaunchContainmentPolicy.EvaluateLaunchKind(launched.LaunchKind);
        if (!admission.Allowed)
            throw new BridgeException(admission.ErrorCode!, admission.Message!);
        if (launched.LaunchSpec is null)
            throw new BridgeException("APP_LAUNCH_SPEC_INVALID", "O agente local não retornou um descritor de lançamento.");
        if (!NativeLaunchContainmentPolicy.AllowsArgumentVector(
            launched.LaunchKind,
            launched.LaunchSpec.Arguments?.Length ?? -1))
            throw new BridgeException("APP_LAUNCH_SPEC_INVALID", "O descritor de atalho contém argumentos que não podem ser preservados com segurança.");

        NativeProcessLaunchSpec launchSpec;
        try
        {
            launchSpec = launched.LaunchSpec.Validate();
        }
        catch (Exception error) when (error is ArgumentException or IOException or NotSupportedException or UnauthorizedAccessException)
        {
            BrowserDiagnostics.Write("native_launch_spec_rejected", $"type={error.GetType().Name}");
            throw new BridgeException("APP_LAUNCH_SPEC_INVALID", "O descritor de lançamento do aplicativo é inválido.");
        }

        NativeContainedProcessLease? launchLease = null;
        var registered = false;
        try
        {
            launchLease = NativeContainedProcessLauncher.StartSuspended(launchSpec);
            var launchedProcess = launchLease.Process;
            if (NativeLaunchContainmentPolicy.IsSharedBroker(launchedProcess.ProcessName))
                throw new BridgeException("BROKERED_WINDOW_UNSUPPORTED", "Um broker compartilhado não pode ser iniciado como aplicativo contido.");

            // The process has not executed a single application instruction yet. Install the
            // exact PID/start-time capability and only then release its primary thread.
            _windows.TrackLaunchedProcess(launchedProcess);
            registered = true;
            _launchLeasesByProcessId.Add(launchLease.ProcessId, launchLease);
            _launchRootByMemberProcessId.Add(launchLease.ProcessId, launchLease.ProcessId);
            _refreshTimer.Interval = TimeSpan.FromMilliseconds(ActiveContainmentRefreshMilliseconds);
            launchLease.Resume();

            var window = await WaitForQuarantinedWindowAsync(launchLease);
            if (window is null)
            {
                TerminateProcessAndForget(launchLease.ProcessId, NativeContainmentFailure.WindowCorrelationTimeout);
                throw new BridgeException(
                    "NATIVE_WINDOW_NOT_FOUND",
                    "Nenhuma janela rastreável apareceu sob quarentena antes do limite de contenção.");
            }

            var processTracked = _windows.IsTrackedProcess(window.ProcessId);
            var hasTrackableWindow = _windows.GetWindows(window.ProcessId)
                .Any(item => item.Handle == window.Handle && !item.IsAttached && !item.IsVisible);
            var sharedBroker = IsSharedBrokerProcess(window.ProcessId);
            if (!NativeLaunchContainmentPolicy.CanReportManaged(processTracked, hasTrackableWindow, sharedBroker))
            {
                TerminateProcessAndForget(launchLease.ProcessId, NativeContainmentFailure.QuarantineFailed);
                throw new BridgeException("WINDOW_CONTAINMENT_DENIED", "A janela não pôde ser marcada como gerenciada.");
            }

            var sessionId = GetOrCreateSession(window);
            _pendingAttachDeadlinesByHandle[window.Handle] = DateTimeOffset.UtcNow.AddMilliseconds(
                NativeLaunchContainmentPolicy.PendingAttachTimeoutMilliseconds);

            return new
            {
                name = launched.Name,
                source = launched.Source,
                distribution = launched.Distribution,
                pid = launchLease.ProcessId,
                windowMode = "native-managed",
                managed = true,
                managementReason = (string?)null,
                sessionId,
                contained = false,
                containmentMode = "hidden-quarantine"
            };
        }
        catch (BridgeException)
        {
            AbortContainedLaunch(launchLease, registered);
            throw;
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException or Win32Exception
            or IOException or NotSupportedException or UnauthorizedAccessException)
        {
            BrowserDiagnostics.Write("native_process_tracking_failed", $"type={error.GetType().Name}");
            AbortContainedLaunch(launchLease, registered);
            throw new BridgeException("APP_PROCESS_NOT_TRACKABLE", "O processo lançado não pôde ser rastreado com segurança.");
        }
    }

    private object Attach(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId", "bounds", "visible");
        var sessionId = ReadString(parameters, "sessionId");
        var handle = GetHandle(sessionId);
        var surface = ReadSurfaceRequest(parameters);
        var bounds = ConvertBounds(surface);
        var visible = ReadOptionalBoolean(parameters, "visible", true);
        if (!_windows.TryAttach(handle, _ownerWindowHandle, bounds, visible, out var error))
        {
            TerminateSessionAndForget(sessionId, NativeContainmentFailure.AttachFailed);
            throw new BridgeException("WINDOW_CONTAINMENT_DENIED", error ?? "O aplicativo não aceita contenção visual.");
        }
        _pendingAttachDeadlinesByHandle.Remove(handle);
        _surfacesByHandle[handle] = surface with { Visible = visible, LastNativeBounds = bounds };
        return new { sessionId, accepted = true, contained = true, containmentMode = "anchored-overlay" };
    }

    private object Layout(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId", "bounds", "visible");
        var sessionId = ReadString(parameters, "sessionId");
        var handle = GetHandle(sessionId);
        var surface = ReadSurfaceRequest(parameters);
        var bounds = ConvertBounds(surface);
        var visible = ReadOptionalBoolean(parameters, "visible", true);
        if (!_windows.TryUpdateAttachedLayout(handle, bounds, visible, out var error))
        {
            _surfacesByHandle.Remove(handle);
            TerminateSessionAndForget(sessionId, NativeContainmentFailure.LayoutFailed);
            throw new BridgeException("WINDOW_LAYOUT_DENIED", error ?? "O Windows recusou a posição da janela.");
        }
        _surfacesByHandle[handle] = surface with { Visible = visible, LastNativeBounds = bounds };
        return new { sessionId, accepted = true, contained = true, containmentMode = "anchored-overlay" };
    }

    private object Detach(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId");
        var sessionId = ReadString(parameters, "sessionId");
        GetHandle(sessionId);
        TerminateSessionAndForget(sessionId, NativeContainmentFailure.DetachRequested);
        return new { sessionId, accepted = true, contained = false, containmentMode = "terminated", closed = true };
    }

    public void RelayoutAttachedWindows()
    {
        if (_disposed || _relayoutPending || _surfacesByHandle.Count == 0) return;
        _relayoutPending = true;
        _ = _dispatcher.BeginInvoke(() =>
        {
            _relayoutPending = false;
            if (_disposed) return;
            foreach (var pair in _surfacesByHandle.ToArray())
            {
                if (!_windows.IsAttached(pair.Key))
                {
                    TerminateHandleAndForget(pair.Key, NativeContainmentFailure.AttachmentLost);
                    continue;
                }
                try
                {
                    var bounds = ConvertBounds(pair.Value);
                    if (_windows.TryUpdateAttachedLayout(pair.Key, bounds, pair.Value.Visible, out _))
                        _surfacesByHandle[pair.Key] = pair.Value with { LastNativeBounds = bounds };
                    else TerminateHandleAndForget(pair.Key, NativeContainmentFailure.LayoutFailed);
                }
                catch (Exception error) when (error is BridgeException or InvalidOperationException or OverflowException or ArithmeticException)
                {
                    BrowserDiagnostics.Write("native_relayout_failed", $"type={error.GetType().Name}");
                    TerminateHandleAndForget(pair.Key, NativeContainmentFailure.LayoutFailed);
                }
            }
        }, DispatcherPriority.Render);
    }

    private long GetHandle(string sessionId)
    {
        if (!_handlesBySessionId.TryGetValue(sessionId, out var handle)) throw new BridgeException("SESSION_NOT_FOUND", "Janela não encontrada.");
        return handle;
    }

    private async Task<NativeWindowSnapshot?> WaitForQuarantinedWindowAsync(NativeContainedProcessLease lease)
    {
        var deadline = DateTimeOffset.UtcNow.AddMilliseconds(
            NativeLaunchContainmentPolicy.WindowCorrelationTimeoutMilliseconds);
        while (!_disposed && DateTimeOffset.UtcNow < deadline)
        {
            var processIds = SynchronizeTrackedJob(lease);
            _windows.Refresh();

            foreach (var processId in processIds)
            {
                if (!_windows.TryGetContainmentFailure(processId, out var quarantineError)) continue;
                TerminateProcessAndForget(lease.ProcessId, NativeContainmentFailure.QuarantineFailed);
                throw new BridgeException("WINDOW_QUARANTINE_FAILED",
                    quarantineError ?? "A janela não aceitou a quarentena preventiva do CloudOS.");
            }

            var memberSet = processIds.ToHashSet();
            var candidates = _windows.GetWindows()
                .Where(item => memberSet.Contains(item.ProcessId))
                .Where(item => !item.IsAttached && !item.IsVisible)
                .OrderBy(item => item.ObservedAtUtc)
                .ToArray();
            if (candidates.Length > 0)
            {
                var rootMainHandle = IntPtr.Zero;
                try
                {
                    lease.Process.Refresh();
                    rootMainHandle = lease.Process.MainWindowHandle;
                }
                catch (InvalidOperationException) { }
                return candidates.FirstOrDefault(item => item.Handle == rootMainHandle.ToInt64()) ?? candidates[0];
            }

            await Task.Delay(25);
        }
        return null;
    }

    private IReadOnlyList<int> SynchronizeTrackedJob(NativeContainedProcessLease lease)
    {
        var processIds = NativeContainedJobTracker.Synchronize(lease, _windows);
        foreach (var processId in processIds)
        {
            if (_launchRootByMemberProcessId.TryGetValue(processId, out var existingRoot)
                && existingRoot != lease.ProcessId)
                throw new InvalidOperationException("A process cannot belong to multiple CloudOS launch capabilities.");
            _launchRootByMemberProcessId[processId] = lease.ProcessId;
        }
        return processIds;
    }

    private void SynchronizeAllTrackedJobs()
    {
        foreach (var pair in _launchLeasesByProcessId.ToArray())
        {
            try
            {
                SynchronizeTrackedJob(pair.Value);
            }
            catch (Exception error) when (error is ArgumentException or InvalidOperationException
                or Win32Exception or NotSupportedException)
            {
                BrowserDiagnostics.Write("native_job_tracking_failed", $"pid={pair.Key} type={error.GetType().Name}");
                TerminateProcessAndForget(pair.Key, NativeContainmentFailure.QuarantineFailed);
            }
        }
    }

    private static bool IsSharedBrokerProcess(int processId)
    {
        try
        {
            using var process = Process.GetProcessById(processId);
            return NativeLaunchContainmentPolicy.IsSharedBroker(process.ProcessName);
        }
        catch (ArgumentException)
        {
            return true;
        }
    }

    private string GetOrCreateSession(NativeWindowSnapshot window)
    {
        if (!_sessionIdsByHandle.TryGetValue(window.Handle, out var sessionId))
        {
            sessionId = $"window-{Guid.NewGuid():N}";
            _sessionIdsByHandle[window.Handle] = sessionId;
            _handlesBySessionId[sessionId] = window.Handle;
        }
        _processIdsBySessionId[sessionId] = window.ProcessId;
        return sessionId;
    }

    private void AbortContainedLaunch(NativeContainedProcessLease? lease, bool registered)
    {
        if (lease is null) return;
        if (registered || _launchLeasesByProcessId.ContainsKey(lease.ProcessId))
        {
            _launchLeasesByProcessId.TryAdd(lease.ProcessId, lease);
            _launchRootByMemberProcessId.TryAdd(lease.ProcessId, lease.ProcessId);
            _refreshTimer.Interval = TimeSpan.FromMilliseconds(ActiveContainmentRefreshMilliseconds);
            TerminateProcessAndForget(lease.ProcessId, NativeContainmentFailure.QuarantineFailed);
            return;
        }
        lease.Dispose();
    }

    private void SweepContainmentDeadlines()
    {
        if (_disposed) return;
        foreach (var pair in _launchLeasesByProcessId.ToArray())
        {
            try
            {
                if (pair.Value.GetMemberProcessIds().Count == 0)
                    CompleteExitedLaunch(pair.Key);
            }
            catch (Exception error) when (error is InvalidOperationException or Win32Exception)
            {
                BrowserDiagnostics.Write("native_job_query_failed", $"pid={pair.Key} type={error.GetType().Name}");
                TerminateProcessAndForget(pair.Key, NativeContainmentFailure.QuarantineFailed);
            }
        }

        var now = DateTimeOffset.UtcNow;
        foreach (var retry in _terminationRetriesByRoot
            .Where(pair => pair.Value.Deadline <= now)
            .ToArray())
        {
            _terminationRetriesByRoot.Remove(retry.Key);
            TerminateProcessAndForget(retry.Key, retry.Value.Failure);
        }

        foreach (var handle in _pendingAttachDeadlinesByHandle
            .Where(pair => pair.Value <= now)
            .Select(pair => pair.Key)
            .ToArray())
        {
            TerminateHandleAndForget(handle, NativeContainmentFailure.PendingAttachExpired);
        }

        foreach (var processId in _processIdsBySessionId.Values
            .Concat(_launchRootByMemberProcessId.Keys)
            .Distinct()
            .ToArray())
        {
            if (_windows.TryGetContainmentFailure(processId, out _))
                TerminateProcessAndForget(processId, NativeContainmentFailure.QuarantineFailed);
        }
    }

    private void TerminateSessionAndForget(string sessionId, NativeContainmentFailure failure)
    {
        if (!_processIdsBySessionId.TryGetValue(sessionId, out var processId))
            throw new BridgeException("SESSION_NOT_FOUND", "Janela não encontrada.");
        TerminateProcessAndForget(processId, failure);
    }

    private void TerminateHandleAndForget(long handle, NativeContainmentFailure failure)
    {
        if (_sessionIdsByHandle.TryGetValue(handle, out var sessionId)
            && _processIdsBySessionId.TryGetValue(sessionId, out var processId))
        {
            TerminateProcessAndForget(processId, failure);
            return;
        }
        if (_windows.TryGetProcessId(handle, out var trackedProcessId))
            TerminateProcessAndForget(trackedProcessId, failure);
    }

    private void TerminateProcessAndForget(int processId, NativeContainmentFailure failure)
    {
        if (!NativeLaunchContainmentPolicy.RequiresTermination(failure))
            throw new InvalidOperationException("The containment policy did not authorize process termination.");
        var rootProcessId = ResolveLaunchRoot(processId);
        var memberProcessIds = GetKnownLaunchMembers(rootProcessId);
        BrowserDiagnostics.Write("native_containment_terminated", $"pid={rootProcessId} reason={failure}");
        foreach (var memberProcessId in memberProcessIds)
            _windows.TryQuarantineTrackedProcess(memberProcessId, out _);

        _launchLeasesByProcessId.TryGetValue(rootProcessId, out var lease);
        if (lease is not null)
        {
            try
            {
                foreach (var memberProcessId in NativeContainedJobTracker.Synchronize(lease, _windows))
                {
                    if (!memberProcessIds.Contains(memberProcessId)) memberProcessIds.Add(memberProcessId);
                    _launchRootByMemberProcessId[memberProcessId] = rootProcessId;
                    _windows.TryQuarantineTrackedProcess(memberProcessId, out _);
                }
            }
            catch (Exception error) when (error is InvalidOperationException or Win32Exception)
            {
                BrowserDiagnostics.Write("native_job_query_failed", $"pid={rootProcessId} type={error.GetType().Name}");
            }
        }

        string? jobError = null;
        var jobTerminated = lease is null || lease.TryTerminate(3_000, out jobError);
        var processTerminated = true;
        var processErrors = new List<string>();
        foreach (var memberProcessId in memberProcessIds)
        {
            if (_windows.TryTerminateTrackedProcess(memberProcessId, out var memberError)) continue;
            processTerminated = false;
            if (!string.IsNullOrWhiteSpace(memberError)) processErrors.Add($"{memberProcessId}:{memberError}");
        }

        if (!processTerminated || !jobTerminated)
        {
            BrowserDiagnostics.Write(
                "native_containment_termination_failed",
                $"pid={rootProcessId} reason={failure} jobError={jobError} processError={string.Join(";", processErrors)}");
            foreach (var pair in _processIdsBySessionId
                .Where(pair => memberProcessIds.Contains(pair.Value))
                .ToArray())
            {
                if (_handlesBySessionId.TryGetValue(pair.Key, out var retryHandle))
                    _pendingAttachDeadlinesByHandle[retryHandle] = DateTimeOffset.UtcNow.AddSeconds(1);
            }
            _terminationRetriesByRoot[rootProcessId] = (
                DateTimeOffset.UtcNow.AddMilliseconds(500),
                failure);
            return;
        }

        CompleteExitedLaunch(rootProcessId);
    }

    private int ResolveLaunchRoot(int processId) =>
        _launchRootByMemberProcessId.TryGetValue(processId, out var rootProcessId)
            ? rootProcessId
            : processId;

    private List<int> GetKnownLaunchMembers(int rootProcessId)
    {
        var members = _launchRootByMemberProcessId
            .Where(pair => pair.Value == rootProcessId)
            .Select(pair => pair.Key)
            .ToList();
        if (!members.Contains(rootProcessId)) members.Add(rootProcessId);
        return members;
    }

    private void CompleteExitedLaunch(int rootProcessId)
    {
        _terminationRetriesByRoot.Remove(rootProcessId);
        var members = GetKnownLaunchMembers(rootProcessId);
        foreach (var memberProcessId in members)
        {
            _windows.TryTerminateTrackedProcess(memberProcessId, out _);
            ForgetProcessMappings(memberProcessId);
            _launchRootByMemberProcessId.Remove(memberProcessId);
        }
        if (_launchLeasesByProcessId.Remove(rootProcessId, out var completedLease)) completedLease.Dispose();
        if (_launchLeasesByProcessId.Count == 0)
            _refreshTimer.Interval = TimeSpan.FromMilliseconds(IdleRefreshMilliseconds);
    }

    private void ForgetProcessMappings(int processId)
    {
        foreach (var pair in _processIdsBySessionId.Where(pair => pair.Value == processId).ToArray())
        {
            _processIdsBySessionId.Remove(pair.Key);
            if (_handlesBySessionId.Remove(pair.Key, out var handle))
            {
                _sessionIdsByHandle.Remove(handle);
                _surfacesByHandle.Remove(handle);
                _pendingAttachDeadlinesByHandle.Remove(handle);
            }
        }
    }

    private void TerminateAllManagedProcesses(NativeContainmentFailure failure)
    {
        foreach (var processId in _processIdsBySessionId.Values
            .Concat(_windows.GetWindows().Select(window => window.ProcessId))
            .Concat(_launchLeasesByProcessId.Keys)
            .Concat(_launchRootByMemberProcessId.Keys)
            .Select(ResolveLaunchRoot)
            .Distinct()
            .ToArray())
        {
            TerminateProcessAndForget(processId, failure);
        }
        _surfacesByHandle.Clear();
        _pendingAttachDeadlinesByHandle.Clear();
    }

    private static AttachedSurfaceRequest ReadSurfaceRequest(JsonElement parameters)
    {
        if (!parameters.TryGetProperty("bounds", out var bounds) || bounds.ValueKind != JsonValueKind.Object)
            throw new BridgeException("INVALID_PARAMS", "Área da janela inválida.");
        RejectUnknownProperties(bounds, "x", "y", "width", "height");
        var x = ReadFiniteDouble(bounds, "x");
        var y = ReadFiniteDouble(bounds, "y");
        var width = ReadFiniteDouble(bounds, "width");
        var height = ReadFiniteDouble(bounds, "height");
        if (width < 32 || height < 32 || width > 32768 || height > 32768 || x < -131072 || x > 131072 || y < -131072 || y > 131072)
            throw new BridgeException("INVALID_PARAMS", "A área do aplicativo é inválida.");
        return new AttachedSurfaceRequest(x, y, width, height, true, default);
    }

    private NativeWindowBounds ConvertBounds(AttachedSurfaceRequest surface)
    {
        var dpiScale = VisualTreeHelper.GetDpi(_webView);
        var topLeft = _webView.PointToScreen(new System.Windows.Point(surface.X, surface.Y));
        var bottomRight = _webView.PointToScreen(new System.Windows.Point(surface.X + surface.Width, surface.Y + surface.Height));
        var webTopLeft = _webView.PointToScreen(new System.Windows.Point(0, 0));
        var webBottomRight = _webView.PointToScreen(new System.Windows.Point(_webView.ActualWidth, _webView.ActualHeight));
        var left = Math.Max(topLeft.X, webTopLeft.X);
        var top = Math.Max(topLeft.Y, webTopLeft.Y);
        var right = Math.Min(bottomRight.X, webBottomRight.X);
        var bottom = Math.Min(bottomRight.Y, webBottomRight.Y);
        if (right - left < 32 || bottom - top < 32) throw new BridgeException("INVALID_PARAMS", "A área do aplicativo está fora do Hub.");
        if (dpiScale.DpiScaleX <= 0 || dpiScale.DpiScaleY <= 0) throw new BridgeException("HOST_NOT_READY", "A janela do CloudOS ainda não está pronta.");
        return new NativeWindowBounds(checked((int)Math.Round(left)), checked((int)Math.Round(top)), checked((int)Math.Round(right - left)), checked((int)Math.Round(bottom - top)));
    }

    private object Operate(JsonElement parameters, NativeOperation operation)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId");
        var sessionId = ReadString(parameters, "sessionId");
        if (!_handlesBySessionId.TryGetValue(sessionId, out var handle)) throw new BridgeException("SESSION_NOT_FOUND", "Janela não encontrada.");
        if (!operation(handle, out var error)) throw new BridgeException("WINDOW_OPERATION_DENIED", error ?? "O Windows recusou a operação.");
        return new { sessionId, accepted = true };
    }

    private async Task<object> CloseSessionAsync(JsonElement parameters)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, "sessionId");
        var sessionId = ReadString(parameters, "sessionId");
        var handle = GetHandle(sessionId);
        if (!_processIdsBySessionId.TryGetValue(sessionId, out var processId))
            throw new BridgeException("SESSION_NOT_FOUND", "Janela não encontrada.");

        var rootProcessId = ResolveLaunchRoot(processId);
        if (!_windows.TryClose(handle, out var error))
        {
            foreach (var memberProcessId in GetKnownLaunchMembers(rootProcessId))
                _windows.TryQuarantineTrackedProcess(memberProcessId, out _);
            TerminateProcessAndForget(rootProcessId, NativeContainmentFailure.GracefulCloseFailed);
            return new { sessionId, accepted = true, closed = true, forced = true };
        }

        foreach (var memberProcessId in GetKnownLaunchMembers(rootProcessId))
            _windows.TryQuarantineTrackedProcess(memberProcessId, out _);

        if (_launchLeasesByProcessId.TryGetValue(rootProcessId, out var lease))
        {
            var deadline = DateTimeOffset.UtcNow.AddMilliseconds(
                NativeLaunchContainmentPolicy.GracefulCloseTimeoutMilliseconds);
            while (!_disposed && DateTimeOffset.UtcNow < deadline)
            {
                IReadOnlyList<int> members;
                try { members = SynchronizeTrackedJob(lease); }
                catch (Exception closeError) when (closeError is ArgumentException or InvalidOperationException
                    or Win32Exception or NotSupportedException)
                {
                    BrowserDiagnostics.Write("native_close_tracking_failed", $"pid={rootProcessId} type={closeError.GetType().Name}");
                    break;
                }
                if (members.Count == 0)
                {
                    CompleteExitedLaunch(rootProcessId);
                    return new { sessionId, accepted = true, closed = true, forced = false };
                }
                await Task.Delay(50);
            }
        }

        // WM_CLOSE merely being delivered is not proof of closure. Tray behavior, a save
        // prompt, or an ignored message must end in Job termination, never a latent HWND.
        TerminateProcessAndForget(rootProcessId, NativeContainmentFailure.GracefulCloseFailed);
        return new { sessionId, accepted = true, closed = true, forced = true };
    }

    private void OnNativeWindowChanged(object? sender, NativeWindowChangedEventArgs eventArgs)
    {
        _dispatcher.BeginInvoke(() =>
        {
            if (_disposed) return;
            var handle = eventArgs.Window.Handle;
            if (eventArgs.Kind == NativeWindowChangeKind.Removed)
            {
                _surfacesByHandle.Remove(handle);
                _pendingAttachDeadlinesByHandle.Remove(handle);
                if (_sessionIdsByHandle.Remove(handle, out var removed))
                {
                    _handlesBySessionId.Remove(removed);
                    _processIdsBySessionId.Remove(removed);
                }
            }
            else
            {
                GetOrCreateSession(eventArgs.Window);
                if (!eventArgs.Window.IsAttached && !_pendingAttachDeadlinesByHandle.ContainsKey(handle))
                {
                    _pendingAttachDeadlinesByHandle[handle] = DateTimeOffset.UtcNow.AddMilliseconds(
                        NativeLaunchContainmentPolicy.PendingAttachTimeoutMilliseconds);
                }
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
            var sessionId = GetOrCreateSession(window);
            sessions.Add(new
            {
                sessionId,
                title = string.IsNullOrWhiteSpace(window.Title) ? $"Aplicativo {window.ProcessId}" : window.Title,
                processId = window.ProcessId,
                minimized = window.IsMinimized,
                maximized = window.IsMaximized,
                contained = window.IsAttached,
                containmentMode = window.IsAttached ? "anchored-overlay" : "hidden-quarantine",
                visible = window.IsVisible,
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
        if (!element.TryGetProperty(property, out var value) || value.ValueKind != JsonValueKind.String) throw new BridgeException("INVALID_PARAMS", $"Campo {property} inválido.");
        return value.GetString()!;
    }

    private static int ReadInt(JsonElement element, string property)
    {
        if (!element.TryGetProperty(property, out var value) || !value.TryGetInt32(out var result)) throw new BridgeException("INVALID_PARAMS", $"Campo {property} inválido.");
        return result;
    }

    private static bool ReadBooleanParameter(JsonElement parameters, string property)
    {
        RequireObject(parameters);
        RejectUnknownProperties(parameters, property);
        if (!parameters.TryGetProperty(property, out var value) || value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new BridgeException("INVALID_PARAMS", $"Campo {property} inválido.");
        return value.GetBoolean();
    }

    private static bool ReadOptionalBoolean(JsonElement parameters, string property, bool fallback)
    {
        if (!parameters.TryGetProperty(property, out var value)) return fallback;
        if (value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new BridgeException("INVALID_PARAMS", $"Campo {property} inválido.");
        return value.GetBoolean();
    }

    private static double ReadFiniteDouble(JsonElement element, string property)
    {
        if (!element.TryGetProperty(property, out var value) || !value.TryGetDouble(out var result) || double.IsNaN(result) || double.IsInfinity(result))
            throw new BridgeException("INVALID_PARAMS", $"Campo {property} inválido.");
        return result;
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
        TerminateAllManagedProcesses(NativeContainmentFailure.HostDisposed);
        _disposed = true;
        _refreshTimer.Stop();
        _browserManager.Dispose();
        _windows.WindowChanged -= OnNativeWindowChanged;
        try
        {
            var core = _webView.CoreWebView2;
            if (core is not null)
            {
                core.WebMessageReceived -= OnWebMessageReceived;
                if (_injectedScriptId is not null) core.RemoveScriptToExecuteOnDocumentCreated(_injectedScriptId);
            }
        }
        catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException or System.Runtime.InteropServices.COMException)
        {
            BrowserDiagnostics.Write("bridge_cleanup_failed", $"type={error.GetType().Name}");
        }
        _injectedScriptId = null;
        _handshakeComplete = false;
        _inFlight.Clear();
        _recentMessages.Clear();
        _sessionIdsByHandle.Clear();
        _handlesBySessionId.Clear();
        _processIdsBySessionId.Clear();
        foreach (var lease in _launchLeasesByProcessId.Values) lease.Dispose();
        _launchLeasesByProcessId.Clear();
        _launchRootByMemberProcessId.Clear();
        _terminationRetriesByRoot.Clear();
        _surfacesByHandle.Clear();
        _pendingAttachDeadlinesByHandle.Clear();
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
        [JsonPropertyName("windowMode")] public string? WindowMode { get; init; }
        [JsonPropertyName("launchKind")] public string? LaunchKind { get; init; }
        [JsonPropertyName("launchSpec")] public NativeProcessLaunchDescriptor? LaunchSpec { get; init; }
    }

    private sealed record AttachedSurfaceRequest(double X, double Y, double Width, double Height, bool Visible, NativeWindowBounds LastNativeBounds);
}
