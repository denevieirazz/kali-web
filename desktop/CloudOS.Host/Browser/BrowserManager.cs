using System.IO;
using System.Text.Json.Serialization;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Host.Browser;

public sealed record BrowserOpenResult(
    [property: JsonPropertyName("opened")] bool Opened,
    [property: JsonPropertyName("reused")] bool Reused);

public sealed class BrowserManager : IDisposable
{
    private readonly Dispatcher _dispatcher;
    private readonly bool _developerMode;
    private readonly BrowserPolicy _policy;
    private readonly string _browserRoot;
    private readonly string _userDataFolder;
    private readonly BrowserStateStore _stateStore;
    private readonly SemaphoreSlim _openGate = new(1, 1);
    private CoreWebView2Environment? _environment;
    private BrowserWindow? _window;
    private bool _shutdownRequested;
    private bool _disposed;

    public BrowserManager(Dispatcher dispatcher, Uri shellOrigin, Uri backendOrigin, bool developerMode)
    {
        _dispatcher = dispatcher;
        _developerMode = developerMode;
        _policy = new BrowserPolicy(shellOrigin, backendOrigin);
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
            return await _dispatcher.InvokeAsync(() => OpenAsync(initialUrl)).Task.Unwrap();

        await _openGate.WaitAsync();
        try
        {
            ThrowIfDisposed();
            ThrowIfShuttingDown();

            if (_window is not null)
            {
                if (_window.WindowState == WindowState.Minimized) _window.WindowState = WindowState.Normal;
                _window.Show();
                _window.Activate();
                if (!string.IsNullOrWhiteSpace(initialUrl)) await _window.NavigateActiveAsync(initialUrl);
                return new BrowserOpenResult(true, true);
            }

            Directory.CreateDirectory(_userDataFolder);
            _environment ??= await CoreWebView2Environment.CreateAsync(userDataFolder: _userDataFolder);
            ThrowIfDisposed();
            ThrowIfShuttingDown();

            var shellFolder = BrowserStorageLayout.ShellUserDataFolder(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
            if (!BrowserStorageLayout.AreIsolated(_environment.UserDataFolder, shellFolder))
                throw new InvalidOperationException("BROWSER_UDF_ISOLATION_FAILED");

            var actual = Path.GetFullPath(_environment.UserDataFolder).TrimEnd(Path.DirectorySeparatorChar);
            var expected = Path.GetFullPath(_userDataFolder).TrimEnd(Path.DirectorySeparatorChar);
            if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("BROWSER_UDF_ISOLATION_FAILED");

            var window = new BrowserWindow(_environment, _policy, _stateStore, _developerMode);
            window.Closed += OnWindowClosed;
            _window = window;
            try
            {
                await window.InitializeAsync(initialUrl);
                ThrowIfDisposed();
                ThrowIfShuttingDown();
                window.Show();
                window.Activate();
                return new BrowserOpenResult(true, false);
            }
            catch
            {
                window.Closed -= OnWindowClosed;
                if (ReferenceEquals(_window, window)) _window = null;
                window.CloseForHostShutdown();
                throw;
            }
        }
        finally
        {
            _openGate.Release();
        }
    }

    public void CloseForHostShutdown()
    {
        if (_disposed) return;
        if (!_dispatcher.CheckAccess())
        {
            _dispatcher.Invoke(CloseForHostShutdown);
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

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(BrowserManager));
    }

    private void ThrowIfShuttingDown()
    {
        if (_shutdownRequested) throw new OperationCanceledException("O host está encerrando o Navegador CloudOS.");
    }

    public void Dispose()
    {
        if (_disposed) return;
        if (!_dispatcher.CheckAccess())
        {
            _dispatcher.Invoke(Dispose);
            return;
        }

        _shutdownRequested = true;
        CloseWindowCore();
        _disposed = true;
    }
}
