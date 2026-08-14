using System.IO;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Host.Browser;

public sealed record BrowserOpenResult(bool Opened, bool Reused);

public sealed class BrowserManager : IDisposable
{
    private readonly Dispatcher _dispatcher;
    private readonly bool _developerMode;
    private readonly BrowserPolicy _policy;
    private readonly string _browserRoot;
    private readonly string _userDataFolder;
    private readonly BrowserStateStore _stateStore;
    private CoreWebView2Environment? _environment;
    private BrowserWindow? _window;
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

    public async Task<BrowserOpenResult> OpenAsync(string? initialUrl = null)
    {
        ThrowIfDisposed();
        if (!_dispatcher.CheckAccess())
            return await _dispatcher.InvokeAsync(() => OpenAsync(initialUrl)).Task.Unwrap();

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
        if (!BrowserStorageLayout.AreIsolated(_environment.UserDataFolder, BrowserStorageLayout.ShellUserDataFolder(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData))))
            throw new InvalidOperationException("BROWSER_UDF_ISOLATION_FAILED");
        var actual = Path.GetFullPath(_environment.UserDataFolder).TrimEnd(Path.DirectorySeparatorChar);
        var expected = Path.GetFullPath(_userDataFolder).TrimEnd(Path.DirectorySeparatorChar);
        if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("BROWSER_UDF_ISOLATION_FAILED");

        var window = new BrowserWindow(_environment, _policy, _stateStore, _developerMode);
        window.Closed += OnWindowClosed;
        _window = window;
        window.Show();
        await window.InitializeAsync(initialUrl);
        window.Activate();
        return new BrowserOpenResult(true, false);
    }

    public void CloseForHostShutdown()
    {
        if (_disposed) return;
        if (!_dispatcher.CheckAccess())
        {
            _dispatcher.Invoke(CloseForHostShutdown);
            return;
        }
        if (_window is not null)
        {
            _window.CloseForHostShutdown();
            _window = null;
        }
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

    public void Dispose()
    {
        if (_disposed) return;
        CloseForHostShutdown();
        _disposed = true;
    }
}
