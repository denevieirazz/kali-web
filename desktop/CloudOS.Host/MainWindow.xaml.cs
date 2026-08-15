using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using CloudOS.Host.Bridge;
using CloudOS.Host.Native;
using CloudOS.Host.Runtime;
using CloudOS.Host.Security;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Host;

public partial class MainWindow : Window
{
    private readonly HostOptions _options;
    private readonly CloudOsRuntimeSupervisor _supervisor = new();
    private readonly BootstrapReporter _bootstrapReporter;
    private CancellationTokenSource? _startupCancellation;
    private NativeWindowManager? _nativeWindows;
    private WebMessageBridge? _bridge;
    private readonly Uri _trustedDocumentOrigin = CloudOsOrigins.ShellBaseUri;
    private string? _runtimeBootstrapScriptId;
    private bool _shellMappingConfigured;
    private bool _fullscreen;
    private bool _allowClose;
    private bool _closing;
    private bool _retrying;
    private bool _sessionEnding;
    private bool _webViewInitialized;
    private WindowStyle _previousStyle;
    private ResizeMode _previousResizeMode;
    private WindowState _previousState;
    private bool _previousTopmost;

    public MainWindow(HostOptions options)
    {
        _options = options;
        _bootstrapReporter = new BootstrapReporter(options.BootstrapPipe);
        InitializeComponent();
        _supervisor.RuntimeExited += OnRuntimeExited;
        LocationChanged += (_, _) => _bridge?.RelayoutAttachedWindows();
        SizeChanged += (_, _) => _bridge?.RelayoutAttachedWindows();
        StateChanged += (_, _) => _bridge?.RelayoutAttachedWindows();
        DpiChanged += (_, _) => _bridge?.RelayoutAttachedWindows();
        ShellWebView.SizeChanged += (_, _) => _bridge?.RelayoutAttachedWindows();
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (_options.Fullscreen) SetFullscreen(true);
        await StartCloudOsAsync();
    }

    private async Task StartCloudOsAsync()
    {
        if (_startupCancellation is not null) return;
        _startupCancellation = new CancellationTokenSource();
        SetBootState("Iniciando o agente local...");

        try
        {
            var endpoint = await _supervisor.StartAsync(_options, _startupCancellation.Token);
            BootStatus.Text = "Preparando o ambiente gráfico WebView2...";
            await InitializeWebViewAsync();
            await ConfigureShellDocumentAsync(endpoint);
            _nativeWindows = new NativeWindowManager();
            _bridge = new WebMessageBridge(
                ShellWebView,
                _trustedDocumentOrigin,
                endpoint.BaseUri,
                endpoint.SupervisorToken,
                endpoint.HostLeaseToken,
                new WindowInteropHelper(this).Handle.ToInt64(),
                _nativeWindows,
                Dispatcher,
                SetFullscreen,
                Close,
                GetHostState,
                _bootstrapReporter.ReportReadyAsync);
            await _bridge.AttachAsync();

            // Always create a fresh document so the current agent endpoint and
            // bridge nonce are installed, while the storage origin stays fixed.
            var startUri = new Uri(_trustedDocumentOrigin, "index.html").AbsoluteUri;
            _supervisor.AppendLog("host", $"Navigating to {startUri}");
            ShellWebView.CoreWebView2.Navigate(startUri);
        }
        catch (WebView2RuntimeNotFoundException)
        {
            ShowError(
                "WebView2 necessário",
                "O Microsoft Edge WebView2 Runtime não está instalado. Instale o WebView2 Evergreen oficial e clique em Tentar novamente.");
        }
        catch (OperationCanceledException) when (_startupCancellation.IsCancellationRequested)
        {
        }
        catch (Exception error)
        {
            ShowError("O CloudOS não pôde iniciar", FriendlyStartupError(error));
        }
        finally
        {
            _startupCancellation?.Dispose();
            _startupCancellation = null;
        }
    }

    private async Task InitializeWebViewAsync()
    {
        if (_webViewInitialized) return;

        _ = CoreWebView2Environment.GetAvailableBrowserVersionString();
        var userData = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CloudOS",
            "WebView2");
        Directory.CreateDirectory(userData);
        var environment = await CoreWebView2Environment.CreateAsync(
            browserExecutableFolder: null,
            userDataFolder: userData,
            options: CreateDeveloperShellEnvironmentOptions());
        await ShellWebView.EnsureCoreWebView2Async(environment);

        var core = ShellWebView.CoreWebView2;
        var settings = core.Settings;
        settings.AreHostObjectsAllowed = false;
        settings.IsWebMessageEnabled = true;
        settings.AreDefaultContextMenusEnabled = _options.DeveloperMode && !_options.Kiosk;
        settings.IsStatusBarEnabled = false;
        settings.IsZoomControlEnabled = false;
        settings.AreDevToolsEnabled = _options.DeveloperMode && !_options.Kiosk;
        settings.AreBrowserAcceleratorKeysEnabled = !_options.Kiosk;
        settings.IsBuiltInErrorPageEnabled = false;

        core.NavigationStarting += (_, eventArgs) =>
        {
            _bridge?.ResetDocument();
            var trustedOrigin = _trustedDocumentOrigin;
            var isTrusted = Uri.TryCreate(eventArgs.Uri, UriKind.Absolute, out var candidate) &&
                NavigationPolicy.IsTrustedDocument(candidate, trustedOrigin);
            _supervisor.AppendLog("webview", $"NavigationStarting uri={eventArgs.Uri} trusted={isTrusted}");
            if (!isTrusted)
                eventArgs.Cancel = true;
        };
        core.WebResourceResponseReceived += (_, eventArgs) =>
        {
            _supervisor.AppendLog("webview", $"Response uri={eventArgs.Request.Uri} status={eventArgs.Response?.StatusCode}");
        };
        core.NavigationCompleted += (_, eventArgs) =>
        {
            var trustedOrigin = _trustedDocumentOrigin;
            var currentSource = Uri.TryCreate(core.Source, UriKind.Absolute, out var navUri) ? navUri : ShellWebView.Source;
            var isTrusted = currentSource is not null &&
                NavigationPolicy.IsTrustedDocument(currentSource, trustedOrigin);
            _supervisor.AppendLog("webview", $"NavigationCompleted isSuccess={eventArgs.IsSuccess} errorStatus={eventArgs.WebErrorStatus} httpStatus={eventArgs.HttpStatusCode} trusted={isTrusted} source={core.Source}");
            if (eventArgs.IsSuccess && isTrusted)
            {
                BootPanel.Visibility = Visibility.Collapsed;
                ErrorPanel.Visibility = Visibility.Collapsed;
                ShellWebView.Visibility = Visibility.Visible;
            }
            else if (!eventArgs.IsSuccess)
            {
                ShowError("Falha ao carregar a interface", $"O shell local não respondeu ({eventArgs.WebErrorStatus}).");
            }
        };
        core.NewWindowRequested += (_, eventArgs) => eventArgs.Handled = true;
        core.PermissionRequested += (_, eventArgs) => eventArgs.State = CoreWebView2PermissionState.Deny;
        core.DownloadStarting += (_, eventArgs) => eventArgs.Cancel = true;
        core.ProcessFailed += (_, _) => Dispatcher.Invoke(() =>
        {
            _bridge?.ResetDocument();
            ShellWebView.Visibility = Visibility.Collapsed;
            ShowError("A interface gráfica foi interrompida", "O processo do WebView2 falhou. Reinicie o CloudOS para recriar a interface.");
        });
        _webViewInitialized = true;
    }

    private CoreWebView2EnvironmentOptions? CreateDeveloperShellEnvironmentOptions()
    {
        if (!_options.DeveloperMode || _options.Kiosk) return null;

        var additionalArguments = Environment.GetEnvironmentVariable("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS");
        if (string.IsNullOrWhiteSpace(additionalArguments)) return null;

        var match = Regex.Match(
            additionalArguments,
            @"(?:^|\s)--remote-debugging-port=(?<port>\d{1,5})(?=\s|$)",
            RegexOptions.CultureInvariant);
        if (!match.Success ||
            !int.TryParse(match.Groups["port"].Value, out var remoteDebuggingPort) ||
            remoteDebuggingPort is < 1024 or > 65535)
            return null;

        return new CoreWebView2EnvironmentOptions($"--remote-debugging-port={remoteDebuggingPort}");
    }

    private async Task ConfigureShellDocumentAsync(RuntimeEndpoint endpoint)
    {
        var core = ShellWebView.CoreWebView2;
        RemoveRuntimeBootstrapScript();

        if (_shellMappingConfigured)
            core.ClearVirtualHostNameToFolderMapping(_trustedDocumentOrigin.Host);

        _supervisor.AppendLog("host", $"Mapping host={_trustedDocumentOrigin.Host} dir={endpoint.FrontendDirectory} indexExists={File.Exists(Path.Combine(endpoint.FrontendDirectory, "index.html"))}");

        core.SetVirtualHostNameToFolderMapping(
            _trustedDocumentOrigin.Host,
            endpoint.FrontendDirectory,
            CoreWebView2HostResourceAccessKind.Allow);
        _shellMappingConfigured = true;

        _runtimeBootstrapScriptId = await core.AddScriptToExecuteOnDocumentCreatedAsync(
            RuntimeBootstrapScript.Build(endpoint.BaseUri));
    }

    private object GetHostState() => new
    {
        nativeHost = true,
        fullscreen = _fullscreen,
        kiosk = _options.Kiosk,
        managedWindows = true,
        embeddedNativeWindows = true,
        nativeWindowContainment = "anchored-overlay",
        platform = "windows",
        version = typeof(MainWindow).Assembly.GetName().Version?.ToString() ?? "1.0.0"
    };

    private void SetFullscreen(bool enabled)
    {
        Dispatcher.Invoke(() =>
        {
            if (enabled == _fullscreen) return;
            if (enabled)
            {
                _previousStyle = WindowStyle;
                _previousResizeMode = ResizeMode;
                _previousState = WindowState;
                _previousTopmost = Topmost;
                WindowStyle = WindowStyle.None;
                ResizeMode = ResizeMode.NoResize;
                WindowState = WindowState.Maximized;
                Topmost = _options.Kiosk;
            }
            else
            {
                Topmost = _previousTopmost;
                WindowStyle = _previousStyle;
                ResizeMode = _previousResizeMode;
                WindowState = _previousState == WindowState.Minimized ? WindowState.Normal : _previousState;
            }
            _fullscreen = enabled;
        });
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (!_options.Kiosk && e.Key == Key.F11)
        {
            SetFullscreen(!_fullscreen);
            e.Handled = true;
        }
        else if (_options.Kiosk && e.Key == Key.F12 &&
                 Keyboard.Modifiers.HasFlag(ModifierKeys.Control) &&
                 Keyboard.Modifiers.HasFlag(ModifierKeys.Alt) &&
                 Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))
        {
            if (MessageBox.Show("Encerrar o modo kiosk do CloudOS?", "CloudOS", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes)
            {
                _allowClose = true;
                Close();
            }
            e.Handled = true;
        }
    }

    private async void OnClosing(object? sender, CancelEventArgs e)
    {
        if (_closing) return;
        if (_sessionEnding)
        {
            _closing = true;
            _startupCancellation?.Cancel();
            DisposeRuntimeBindings();
            ShellWebView.Dispose();
            _bootstrapReporter.Dispose();
            return;
        }
        if (_options.Kiosk && !_allowClose)
        {
            e.Cancel = true;
            return;
        }

        e.Cancel = true;
        _closing = true;
        ShellWebView.Visibility = Visibility.Collapsed;
        BootStatus.Text = "Encerrando o agente local...";
        BootPanel.Visibility = Visibility.Visible;
        _startupCancellation?.Cancel();
        DisposeRuntimeBindings();
        ShellWebView.Dispose();
        try { await _supervisor.StopAsync(CancellationToken.None); } catch { }
        await _supervisor.DisposeAsync();
        _bootstrapReporter.Dispose();
        _allowClose = true;
        _ = Dispatcher.BeginInvoke(Close);
    }

    private void OnRuntimeExited(object? sender, RuntimeExitedEventArgs eventArgs)
    {
        Dispatcher.Invoke(() =>
        {
            if (_closing) return;
            ShellWebView.Visibility = Visibility.Collapsed;
            ShowError("O agente local foi interrompido", $"O processo encerrou inesperadamente (código {eventArgs.ExitCode}). Clique em Tentar novamente.");
        });
    }

    private async void Retry_Click(object sender, RoutedEventArgs e)
    {
        if (_retrying || _closing) return;
        _retrying = true;
        ErrorPanel.Visibility = Visibility.Collapsed;
        try
        {
            DisposeRuntimeBindings();
            try { await _supervisor.StopAsync(CancellationToken.None); } catch { }
            await StartCloudOsAsync();
        }
        finally
        {
            _retrying = false;
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        _allowClose = true;
        Close();
    }

    internal void PrepareForSessionEnding()
    {
        _sessionEnding = true;
        _allowClose = true;
        _startupCancellation?.Cancel();
    }

    private void DisposeRuntimeBindings()
    {
        _bridge?.Dispose();
        _bridge = null;
        _nativeWindows?.Dispose();
        _nativeWindows = null;
        RemoveRuntimeBootstrapScript();
    }

    private void RemoveRuntimeBootstrapScript()
    {
        if (_runtimeBootstrapScriptId is null) return;
        try
        {
            ShellWebView.CoreWebView2?.RemoveScriptToExecuteOnDocumentCreated(_runtimeBootstrapScriptId);
        }
        catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException or COMException)
        {
            // A failed WebView process can reject cleanup during retry/shutdown.
        }
        _runtimeBootstrapScriptId = null;
    }

    private void SetBootState(string status)
    {
        ShellWebView.Visibility = Visibility.Collapsed;
        ErrorPanel.Visibility = Visibility.Collapsed;
        BootPanel.Visibility = Visibility.Visible;
        BootStatus.Text = status;
    }

    private void ShowError(string title, string message)
    {
        ShellWebView.Visibility = Visibility.Collapsed;
        BootPanel.Visibility = Visibility.Collapsed;
        ErrorTitle.Text = title;
        ErrorMessage.Text = message;
        ErrorPanel.Visibility = Visibility.Visible;
    }

    private static string FriendlyStartupError(Exception error)
    {
        return error switch
        {
            FileNotFoundException => error.Message,
            DirectoryNotFoundException => error.Message,
            BadImageFormatException => "A arquitetura do WebView2 ou do host não corresponde ao Windows.",
            COMException => "O WebView2 está indisponível ou corrompido. Repare o Microsoft Edge WebView2 Runtime.",
            _ => error.Message
        };
    }
}
