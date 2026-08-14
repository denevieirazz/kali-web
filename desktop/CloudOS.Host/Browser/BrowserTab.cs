using System.Windows;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace CloudOS.Host.Browser;

public sealed class BrowserTab : IDisposable
{
    private readonly CoreWebView2Environment _environment;
    private readonly BrowserPolicy _policy;
    private readonly bool _developerMode;
    private readonly Window _promptOwner;
    private readonly BrowserPermissionController _permissions;
    private readonly BrowserDownloadManager _downloads;
    private readonly BrowserCredentialController _credentials = new();
    private bool _disposed;

    public BrowserTab(
        CoreWebView2Environment environment,
        BrowserPolicy policy,
        bool developerMode,
        Window promptOwner,
        BrowserPermissionController permissions,
        BrowserDownloadManager downloads,
        Guid? logicalId = null)
    {
        _environment = environment;
        _policy = policy;
        _developerMode = developerMode;
        _promptOwner = promptOwner;
        _permissions = permissions;
        _downloads = downloads;
        Id = Guid.NewGuid();
        LogicalId = logicalId ?? Id;
        View = new WebView2CompositionControl();
    }

    public Guid Id { get; }
    public Guid LogicalId { get; }
    public WebView2CompositionControl View { get; }
    public string Title { get; private set; } = "Nova aba";
    public Uri? CurrentUri { get; private set; }
    public bool IsLoading { get; private set; }
    public bool CanGoBack => View.CoreWebView2?.CanGoBack == true;
    public bool CanGoForward => View.CoreWebView2?.CanGoForward == true;
    public BrowserError? Error { get; private set; }

    public event EventHandler? StateChanged;
    public event EventHandler? RendererFailed;
    public Func<string?, Task<CoreWebView2?>>? NewWindowFactory { get; set; }

    public async Task InitializeAsync()
    {
        ThrowIfDisposed();
        await View.EnsureCoreWebView2Async(_environment);
        ThrowIfDisposed();

        var core = View.CoreWebView2;
        var settings = core.Settings;
        settings.AreHostObjectsAllowed = false;
        settings.IsWebMessageEnabled = false;
        settings.AreDevToolsEnabled = _developerMode;
        settings.AreDefaultContextMenusEnabled = false;
        settings.IsStatusBarEnabled = false;
        settings.IsBuiltInErrorPageEnabled = false;
        core.Profile.IsPasswordAutosaveEnabled = false;
        core.Profile.IsGeneralAutofillEnabled = false;

        core.NavigationStarting += OnNavigationStarting;
        core.NavigationCompleted += OnNavigationCompleted;
        core.SourceChanged += OnSourceChanged;
        core.DocumentTitleChanged += OnDocumentTitleChanged;
        core.HistoryChanged += OnHistoryChanged;
        core.NewWindowRequested += OnNewWindowRequested;
        core.LaunchingExternalUriScheme += OnLaunchingExternalUriScheme;
        core.ServerCertificateErrorDetected += OnServerCertificateErrorDetected;
        core.PermissionRequested += OnPermissionRequested;
        core.DownloadStarting += OnDownloadStarting;
        core.ClientCertificateRequested += OnClientCertificateRequested;
        core.BasicAuthenticationRequested += OnBasicAuthenticationRequested;
        core.ProcessFailed += OnProcessFailed;
        core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += OnWebResourceRequested;
    }

    public BrowserNavigationDecision Navigate(string rawInput)
    {
        ThrowIfDisposed();
        var decision = _policy.ParseAddressInput(rawInput);
        if (!decision.Allowed || decision.Uri is null)
        {
            SetError(BrowserError.Blocked(
                decision.ErrorCode ?? "NAVIGATION_BLOCKED",
                decision.Message ?? "Navegação bloqueada.",
                rawInput));
            return decision;
        }

        ClearError();
        View.CoreWebView2.Navigate(decision.Uri.AbsoluteUri);
        return decision;
    }

    public void GoBack() { if (!_disposed && CanGoBack) View.CoreWebView2.GoBack(); }
    public void GoForward() { if (!_disposed && CanGoForward) View.CoreWebView2.GoForward(); }
    public void Stop() { if (!_disposed && IsLoading) View.CoreWebView2.Stop(); }
    public void Reload() { if (!_disposed && View.CoreWebView2 is not null) View.CoreWebView2.Reload(); }

    public void SetError(BrowserError error)
    {
        if (_disposed) return;
        Error = error;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void ClearError()
    {
        if (_disposed || Error is null) return;
        Error = null;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void OnNavigationStarting(object? sender, CoreWebView2NavigationStartingEventArgs e)
    {
        if (_disposed)
        {
            e.Cancel = true;
            return;
        }

        var decision = _policy.ValidateNavigation(e.Uri, allowAboutBlank: true);
        if (!decision.Allowed)
        {
            e.Cancel = true;
            SetError(BrowserError.Blocked(
                decision.ErrorCode ?? "NAVIGATION_BLOCKED",
                decision.Message ?? "Navegação bloqueada.",
                e.Uri));
            return;
        }
        Error = null;
        IsLoading = true;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void OnNavigationCompleted(object? sender, CoreWebView2NavigationCompletedEventArgs e)
    {
        if (_disposed) return;
        IsLoading = false;
        if (!e.IsSuccess)
            SetError(BrowserError.Navigation(
                e.WebErrorStatus.ToString().ToUpperInvariant(),
                FriendlyNavigationError(e.WebErrorStatus),
                CurrentUri?.AbsoluteUri));
        else
        {
            Error = null;
            StateChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnSourceChanged(object? sender, CoreWebView2SourceChangedEventArgs e)
    {
        if (_disposed) return;
        if (Uri.TryCreate(View.CoreWebView2.Source, UriKind.Absolute, out var uri)) CurrentUri = uri;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void OnDocumentTitleChanged(object? sender, object e)
    {
        if (_disposed) return;
        Title = string.IsNullOrWhiteSpace(View.CoreWebView2.DocumentTitle)
            ? CurrentUri?.Host ?? "Nova aba"
            : View.CoreWebView2.DocumentTitle;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void OnHistoryChanged(object? sender, object e)
    {
        if (!_disposed) StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private async void OnNewWindowRequested(object? sender, CoreWebView2NewWindowRequestedEventArgs e)
    {
        var deferral = e.GetDeferral();
        try
        {
            e.Handled = true;
            if (_disposed) return;
            var decision = _policy.ValidateNavigation(e.Uri, allowAboutBlank: true);
            if (NewWindowFactory is null || !decision.Allowed) return;
            var target = await NewWindowFactory(e.Uri);
            if (!_disposed && target is not null) e.NewWindow = target;
        }
        catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException or OperationCanceledException)
        {
            SetError(BrowserError.Blocked("POPUP_BLOCKED", "A nova aba não pôde ser criada com segurança.", e.Uri));
        }
        finally
        {
            deferral.Complete();
        }
    }

    private void OnLaunchingExternalUriScheme(object? sender, CoreWebView2LaunchingExternalUriSchemeEventArgs e)
    {
        e.Cancel = true;
        SetError(BrowserError.Blocked(
            "EXTERNAL_SCHEME_BLOCKED",
            "Protocolos externos ao navegador não são executados pelo CloudOS.",
            e.Uri));
    }

    private void OnServerCertificateErrorDetected(object? sender, CoreWebView2ServerCertificateErrorDetectedEventArgs e)
    {
        e.Action = CoreWebView2ServerCertificateErrorAction.Cancel;
        SetError(BrowserError.Blocked(
            "TLS_CERTIFICATE_ERROR",
            "A conexão foi bloqueada porque o certificado TLS não pôde ser validado.",
            e.RequestUri));
    }

    private async void OnPermissionRequested(object? sender, CoreWebView2PermissionRequestedEventArgs e)
    {
        try
        {
            await _permissions.HandleAsync(_promptOwner, e, () => _disposed ? null : View.CoreWebView2?.Source);
        }
        catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException)
        {
            e.SavesInProfile = false;
            e.State = CoreWebView2PermissionState.Deny;
        }
    }

    private void OnDownloadStarting(object? sender, CoreWebView2DownloadStartingEventArgs e)
    {
        if (_disposed)
        {
            e.Cancel = true;
            e.Handled = true;
            return;
        }
        _downloads.Handle(_promptOwner, e);
    }

    private async void OnClientCertificateRequested(object? sender, CoreWebView2ClientCertificateRequestedEventArgs e)
    {
        try
        {
            await _credentials.HandleClientCertificateAsync(_promptOwner, e, () => _disposed ? null : View.CoreWebView2?.Source);
        }
        catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException)
        {
            e.Handled = true;
            e.Cancel = true;
        }
    }

    private async void OnBasicAuthenticationRequested(object? sender, CoreWebView2BasicAuthenticationRequestedEventArgs e)
    {
        try
        {
            await _credentials.HandleBasicAuthenticationAsync(_promptOwner, e, () => _disposed ? null : View.CoreWebView2?.Source);
        }
        catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException)
        {
            e.Cancel = true;
        }
    }

    private void OnProcessFailed(object? sender, CoreWebView2ProcessFailedEventArgs e)
    {
        if (!_disposed) RendererFailed?.Invoke(this, EventArgs.Empty);
    }

    private void OnWebResourceRequested(object? sender, CoreWebView2WebResourceRequestedEventArgs e)
    {
        if (_disposed || !_policy.IsBlockedRequest(e.Request.Uri)) return;
        e.Response = _environment.CreateWebResourceResponse(
            null,
            403,
            "Blocked by CloudOS Browser",
            "Content-Type: text/plain; charset=utf-8");
    }

    private static string FriendlyNavigationError(CoreWebView2WebErrorStatus status) => status switch
    {
        CoreWebView2WebErrorStatus.HostNameNotResolved => "O endereço não pôde ser encontrado.",
        CoreWebView2WebErrorStatus.Disconnected => "Sem conexão com a rede.",
        CoreWebView2WebErrorStatus.Timeout => "A conexão excedeu o tempo limite.",
        CoreWebView2WebErrorStatus.ConnectionAborted => "A conexão foi encerrada.",
        CoreWebView2WebErrorStatus.ConnectionReset => "A conexão foi redefinida.",
        CoreWebView2WebErrorStatus.CannotConnect => "Não foi possível conectar ao servidor.",
        CoreWebView2WebErrorStatus.CertificateCommonNameIsIncorrect or
        CoreWebView2WebErrorStatus.CertificateExpired or
        CoreWebView2WebErrorStatus.ClientCertificateContainsErrors or
        CoreWebView2WebErrorStatus.CertificateRevoked or
        CoreWebView2WebErrorStatus.CertificateIsInvalid => "O certificado TLS não é confiável.",
        CoreWebView2WebErrorStatus.OperationCanceled => "A navegação foi cancelada.",
        _ => $"A página não pôde ser carregada ({status})."
    };

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(BrowserTab));
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _credentials.Dispose();
        var core = View.CoreWebView2;
        if (core is not null)
        {
            core.NavigationStarting -= OnNavigationStarting;
            core.NavigationCompleted -= OnNavigationCompleted;
            core.SourceChanged -= OnSourceChanged;
            core.DocumentTitleChanged -= OnDocumentTitleChanged;
            core.HistoryChanged -= OnHistoryChanged;
            core.NewWindowRequested -= OnNewWindowRequested;
            core.LaunchingExternalUriScheme -= OnLaunchingExternalUriScheme;
            core.ServerCertificateErrorDetected -= OnServerCertificateErrorDetected;
            core.PermissionRequested -= OnPermissionRequested;
            core.DownloadStarting -= OnDownloadStarting;
            core.ClientCertificateRequested -= OnClientCertificateRequested;
            core.BasicAuthenticationRequested -= OnBasicAuthenticationRequested;
            core.ProcessFailed -= OnProcessFailed;
            core.WebResourceRequested -= OnWebResourceRequested;
        }
        View.Dispose();
    }
}
