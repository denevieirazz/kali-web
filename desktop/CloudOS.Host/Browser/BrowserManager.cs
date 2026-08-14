using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Host.Browser;

public sealed class BrowserManager : IDisposable
{
    private readonly Dispatcher _dispatcher;
    private readonly bool _developerMode;
    private readonly BrowserPolicy _policy;
    private readonly string _browserRoot;
    private readonly string _userDataFolder;
    private readonly BrowserStateStore _stateStore;
    private readonly SemaphoreSlim _openGate = new(1, 1);
    private readonly Action<string, string?> _diagnostics;
    private Task<CoreWebView2Environment>? _environmentTask;
    private CoreWebView2Environment? _environment;
    private BrowserWindow? _window;
    private Task? _windowInitializationTask;
    private bool _shutdownRequested;
    private bool _disposed;

    public BrowserManager(
        Dispatcher dispatcher,
        Uri shellOrigin,
        Uri backendOrigin,
        bool developerMode,
        Action<string, string?>? diagnostics = null)
    {
        _dispatcher = dispatcher;
        _developerMode = developerMode;
        _policy = new BrowserPolicy(shellOrigin, backendOrigin);
        _diagnostics = diagnostics ?? BrowserDiagnostics.Write;
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        _browserRoot = BrowserStorageLayout.BrowserRoot(local);
        _userDataFolder = BrowserStorageLayout.BrowserUserDataFolder(local);
        var shellFolder = BrowserStorageLayout.ShellUserDataFolder(local);
        if (!BrowserStorageLayout.AreIsolated(_userDataFolder, shellFolder))
            throw new InvalidOperationException("BROWSER_UDF_ISOLATION_FAILED");
        _stateStore = new BrowserStateStore(BrowserStorageLayout.BrowserStatePath(local));
    }

    public string UserDataFolder => _userDataFolder;
    public string BrowserRoot => _browserRoot;
    public bool IsOpen => _window is not null;

    public async Task<BrowserOpenResult> OpenAsync(string? initialUrl = null)
    {
        ThrowIfDisposed();
        if (!_dispatcher.CheckAccess())
            return await _dispatcher.InvokeAsync(() => OpenAsync(initialUrl), DispatcherPriority.Normal).Task.Unwrap();

        _diagnostics("dispatcher_entered", null);
        await _openGate.WaitAsync();
        try
        {
            _diagnostics("manager_started", null);
            ThrowIfDisposed();
            if (_shutdownRequested)
                return BrowserOpenResult.Failure("BROWSER_SHUTTING_DOWN", "O CloudOS está encerrando o Navegador.");

            if (_window is not null)
            {
                RestoreAndFocus(_window);
                _window.RequestOpen(initialUrl);
                return BrowserOpenResult.Success(reused: true, windowVisible: _window.IsVisible);
            }

            BrowserWindow? window = null;
            try
            {
                window = new BrowserWindow(
                    GetEnvironmentAsync,
                    _policy,
                    _stateStore,
                    _developerMode,
                    diagnostics: _diagnostics);
                _diagnostics("window_created", null);
                window.Closed += OnWindowClosed;
                _window = window;

                window.Show();
                window.Activate();
                window.Focus();
                if (!window.IsVisible)
                    throw new InvalidOperationException("BROWSER_WINDOW_NOT_VISIBLE");

                _diagnostics("window_shown", "visible=true");
                _windowInitializationTask = ObserveInitializationAsync(window, initialUrl);
                return BrowserOpenResult.Success(reused: false, windowVisible: true);
            }
            catch (Exception error) when (error is not OutOfMemoryException)
            {
                _diagnostics("window_create_failed", $"type={error.GetType().Name}");
                if (window is not null)
                {
                    window.Closed -= OnWindowClosed;
                    if (ReferenceEquals(_window, window)) _window = null;
                    try
                    {
                        window.CloseForHostShutdown();
                    }
                    catch (Exception closeError) when (closeError is InvalidOperationException or ObjectDisposedException)
                    {
                        _diagnostics("window_cleanup_failed", $"type={closeError.GetType().Name}");
                    }
                }

                return BrowserOpenResult.Failure(
                    "BROWSER_WINDOW_CREATE_FAILED",
                    FriendlyWindowCreationError(error));
            }
        }
        finally
        {
            _openGate.Release();
        }
    }

    private async Task ObserveInitializationAsync(BrowserWindow window, string? initialUrl)
    {
        try
        {
            await window.StartInitializationAsync(initialUrl);
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            _diagnostics("webview_failed", $"type={error.GetType().Name}");
            if (!_shutdownRequested && ReferenceEquals(_window, window) && !window.IsClosing)
                window.ShowInitializationFailure(
                    "BROWSER_WEBVIEW_INITIALIZATION_FAILED",
                    "O WebView2 do Navegador não pôde ser inicializado.");
        }
    }

    private void RestoreAndFocus(BrowserWindow window)
    {
        if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
        if (!window.IsVisible) window.Show();
        window.Activate();
        window.Focus();
        _diagnostics("window_shown", $"visible={window.IsVisible.ToString().ToLowerInvariant()} reused=true");
    }

    private async Task<CoreWebView2Environment> GetEnvironmentAsync(CancellationToken cancellationToken)
    {
        if (!_dispatcher.CheckAccess())
            return await _dispatcher.InvokeAsync(() => GetEnvironmentAsync(cancellationToken), DispatcherPriority.Normal).Task.Unwrap();

        ThrowIfDisposed();
        if (_shutdownRequested) throw new OperationCanceledException(cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();
        if (_environment is not null) return _environment;

        var task = _environmentTask ??= CreateEnvironmentCoreAsync();
        try
        {
            var environment = await task;
            cancellationToken.ThrowIfCancellationRequested();
            if (_shutdownRequested) throw new OperationCanceledException(cancellationToken);
            return environment;
        }
        catch
        {
            if (task.IsFaulted && ReferenceEquals(_environmentTask, task)) _environmentTask = null;
            throw;
        }
    }

    private async Task<CoreWebView2Environment> CreateEnvironmentCoreAsync()
    {
        Directory.CreateDirectory(_userDataFolder);
        var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: _userDataFolder);

        var shellFolder = BrowserStorageLayout.ShellUserDataFolder(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
        if (!BrowserStorageLayout.AreIsolated(environment.UserDataFolder, shellFolder))
            throw new InvalidOperationException("BROWSER_UDF_ISOLATION_FAILED");

        var actual = Path.GetFullPath(environment.UserDataFolder).TrimEnd(Path.DirectorySeparatorChar);
        var expected = Path.GetFullPath(_userDataFolder).TrimEnd(Path.DirectorySeparatorChar);
        if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("BROWSER_UDF_ISOLATION_FAILED");

        _environment = environment;
        return environment;
    }

    public void CloseForHostShutdown()
    {
        if (_disposed) return;
        if (!_dispatcher.CheckAccess())
        {
            if (!_dispatcher.HasShutdownStarted)
                _ = _dispatcher.BeginInvoke(CloseForHostShutdown, DispatcherPriority.Send);
            return;
        }

        _shutdownRequested = true;
        CloseWindowCore();
    }

    private void CloseWindowCore()
    {
        var window = _window;
        if (window is null) return;
        window.Closed -= OnWindowClosed;
        _window = null;
        window.CloseForHostShutdown();
    }

    private void OnWindowClosed(object? sender, EventArgs e)
    {
        if (sender is BrowserWindow window) window.Closed -= OnWindowClosed;
        if (ReferenceEquals(_window, sender)) _window = null;
    }

    private static string FriendlyWindowCreationError(Exception error) => error switch
    {
        WebView2RuntimeNotFoundException => "O Microsoft Edge WebView2 Runtime não está disponível.",
        UnauthorizedAccessException => "A janela nativa do Navegador não pôde acessar o perfil isolado.",
        COMException => "O Windows não conseguiu criar a janela nativa do Navegador.",
        InvalidOperationException when error.Message.Contains("BROWSER_UDF_ISOLATION_FAILED", StringComparison.Ordinal) =>
            "O perfil do Navegador não pôde ser isolado com segurança.",
        _ => "A janela nativa do Navegador não pôde ser criada."
    };

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(BrowserManager));
    }

    public void Dispose()
    {
        if (_disposed) return;
        if (!_dispatcher.CheckAccess())
        {
            if (!_dispatcher.HasShutdownStarted)
                _ = _dispatcher.BeginInvoke(Dispose, DispatcherPriority.Send);
            return;
        }

        _shutdownRequested = true;
        CloseWindowCore();
        _disposed = true;
    }
}
