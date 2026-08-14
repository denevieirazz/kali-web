using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Host.Browser;

public partial class BrowserWindow : Window
{
    private const int MaxTabs = 32;
    private static readonly TimeSpan CrashWindow = TimeSpan.FromSeconds(30);
    private readonly CoreWebView2Environment _environment;
    private readonly BrowserPolicy _policy;
    private readonly BrowserStateStore _stateStore;
    private readonly bool _developerMode;
    private readonly BrowserPermissionController _permissions = new();
    private readonly BrowserDownloadManager _downloads = new();
    private readonly List<BrowserTab> _tabs = [];
    private readonly Stack<string> _closedTabs = new();
    private readonly Dictionary<Guid, DateTimeOffset> _lastCrashByLogicalTab = [];
    private BrowserTab? _activeTab;
    private bool _hostShutdown;
    private bool _closing;

    public BrowserWindow(CoreWebView2Environment environment, BrowserPolicy policy, BrowserStateStore stateStore, bool developerMode)
    {
        _environment = environment;
        _policy = policy;
        _stateStore = stateStore;
        _developerMode = developerMode;
        InitializeComponent();
        _downloads.StatusChanged += Downloads_StatusChanged;
    }

    public async Task InitializeAsync(string? initialUrl)
    {
        var tab = await CreateTabAsync(initialUrl ?? BrowserPolicy.HomeUrl, activate: true);
        if (tab is null) throw new InvalidOperationException("Não foi possível criar a aba inicial do navegador.");
    }

    public Task NavigateActiveAsync(string raw)
    {
        _activeTab?.Navigate(raw);
        return Task.CompletedTask;
    }

    public void CloseForHostShutdown()
    {
        _hostShutdown = true;
        Close();
    }

    private async Task<BrowserTab?> CreateTabAsync(string? initialUrl = null, bool activate = true, Guid? logicalId = null)
    {
        if (_closing) return null;
        if (_tabs.Count >= MaxTabs)
        {
            StatusText.Text = "Limite de 32 abas atingido.";
            return null;
        }

        var tab = new BrowserTab(_environment, _policy, _developerMode, this, _permissions, _downloads, logicalId);
        WireTab(tab);
        try
        {
            await tab.InitializeAsync();
            if (_closing)
            {
                UnwireTab(tab);
                tab.Dispose();
                return null;
            }

            _tabs.Add(tab);
            WebViewHost.Children.Add(tab.View);
            tab.View.Visibility = Visibility.Collapsed;
            RenderTabs();
            if (activate) ActivateTab(tab);
            if (!string.IsNullOrWhiteSpace(initialUrl)) tab.Navigate(initialUrl);
            return tab;
        }
        catch
        {
            UnwireTab(tab);
            tab.Dispose();
            throw;
        }
    }

    private void WireTab(BrowserTab tab)
    {
        tab.StateChanged += Tab_StateChanged;
        tab.RendererFailed += Tab_RendererFailed;
        tab.NewWindowFactory = async uri =>
        {
            if (_closing) return null;
            return (await CreateTabAsync(uri, activate: true))?.View.CoreWebView2;
        };
    }

    private void UnwireTab(BrowserTab tab)
    {
        tab.StateChanged -= Tab_StateChanged;
        tab.RendererFailed -= Tab_RendererFailed;
        tab.NewWindowFactory = null;
    }

    private void ActivateTab(BrowserTab tab)
    {
        if (_closing || !_tabs.Contains(tab)) return;
        foreach (var item in _tabs)
            item.View.Visibility = ReferenceEquals(item, tab) ? Visibility.Visible : Visibility.Collapsed;
        _activeTab = tab;
        RenderTabs();
        RefreshChrome();
    }

    private void CloseTab(BrowserTab tab, bool remember = true)
    {
        var index = _tabs.IndexOf(tab);
        if (index < 0) return;
        var wasActive = ReferenceEquals(_activeTab, tab);
        if (remember && tab.CurrentUri is { Scheme: "http" or "https" } current)
        {
            if (_closedTabs.Count >= MaxTabs)
            {
                var keep = _closedTabs.Reverse().Take(MaxTabs - 1).Reverse().ToArray();
                _closedTabs.Clear();
                foreach (var item in keep) _closedTabs.Push(item);
            }
            _closedTabs.Push(current.AbsoluteUri);
        }

        UnwireTab(tab);
        WebViewHost.Children.Remove(tab.View);
        _tabs.RemoveAt(index);
        _lastCrashByLogicalTab.Remove(tab.LogicalId);
        tab.Dispose();
        if (_tabs.Count == 0)
        {
            _activeTab = null;
            Close();
            return;
        }
        if (wasActive) ActivateTab(_tabs[Math.Min(index, _tabs.Count - 1)]);
        else RenderTabs();
    }

    private void RenderTabs()
    {
        TabStrip.Children.Clear();
        foreach (var tab in _tabs)
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            var title = tab.Title.Length > 24 ? tab.Title[..24] + "…" : tab.Title;
            var select = new Button
            {
                Content = title,
                Tag = tab,
                MinWidth = 110,
                MaxWidth = 190,
                Padding = new Thickness(10, 4, 8, 4),
                Margin = new Thickness(1),
                FontWeight = ReferenceEquals(tab, _activeTab) ? FontWeights.SemiBold : FontWeights.Normal
            };
            select.Click += (_, _) => ActivateTab((BrowserTab)select.Tag);
            var close = new Button { Content = "×", Tag = tab, Width = 28, Margin = new Thickness(0, 1, 4, 1) };
            close.Click += (_, _) => CloseTab((BrowserTab)close.Tag);
            panel.Children.Add(select);
            panel.Children.Add(close);
            TabStrip.Children.Add(panel);
        }
    }

    private void RefreshChrome()
    {
        var tab = _activeTab;
        if (tab is null) return;
        BackButton.IsEnabled = tab.CanGoBack;
        ForwardButton.IsEnabled = tab.CanGoForward;
        ReloadStopButton.Content = tab.IsLoading ? "×" : "↻";
        ReloadStopButton.ToolTip = tab.IsLoading ? "Parar" : "Recarregar";
        if (!AddressBox.IsKeyboardFocusWithin)
            AddressBox.Text = tab.CurrentUri is null ? string.Empty : _policy.DisplayUri(tab.CurrentUri);
        FavoriteButton.Content = tab.CurrentUri is not null && _stateStore.IsFavorite(tab.CurrentUri) ? "★" : "☆";
        Title = string.IsNullOrWhiteSpace(tab.Title) ? "Navegador CloudOS" : $"{tab.Title} — Navegador CloudOS";
        CancelDownloadsButton.Visibility = _downloads.HasActiveDownloads ? Visibility.Visible : Visibility.Collapsed;

        if (tab.Error is null)
        {
            ErrorPanel.Visibility = Visibility.Collapsed;
            tab.View.Visibility = Visibility.Visible;
            if (!_downloads.HasActiveDownloads) StatusText.Text = tab.IsLoading ? "Carregando…" : "Pronto";
        }
        else
        {
            ErrorCodeText.Text = tab.Error.Code;
            ErrorMessageText.Text = tab.Error.Message + (string.IsNullOrWhiteSpace(tab.Error.Uri) ? string.Empty : $"\n{tab.Error.Uri}");
            RetryButton.Visibility = tab.Error.CanRetry ? Visibility.Visible : Visibility.Collapsed;
            ErrorPanel.Visibility = Visibility.Visible;
            tab.View.Visibility = Visibility.Collapsed;
            StatusText.Text = tab.Error.Message;
        }
    }

    private void Tab_StateChanged(object? sender, EventArgs e)
    {
        if (_closing || sender is not BrowserTab tab) return;
        if (ReferenceEquals(tab, _activeTab)) RefreshChrome();
        RenderTabs();
        if (!tab.IsLoading && tab.Error is null && tab.CurrentUri is { Scheme: "http" or "https" } uri)
        {
            var latest = _stateStore.History.LastOrDefault();
            if (latest is null ||
                !latest.Url.Equals(uri.AbsoluteUri, StringComparison.OrdinalIgnoreCase) ||
                DateTimeOffset.UtcNow - latest.VisitedAt > TimeSpan.FromSeconds(2))
                _stateStore.AddHistory(uri, tab.Title);
        }
    }

    private async void Tab_RendererFailed(object? sender, EventArgs e)
    {
        if (_closing || sender is not BrowserTab failed) return;
        try
        {
            var current = failed.CurrentUri?.AbsoluteUri;
            var index = _tabs.IndexOf(failed);
            if (index < 0) return;
            var now = DateTimeOffset.UtcNow;
            if (_lastCrashByLogicalTab.TryGetValue(failed.LogicalId, out var previous) && now - previous <= CrashWindow)
            {
                failed.SetError(BrowserError.Navigation(
                    "RENDERER_CRASHED",
                    "A aba falhou novamente em menos de 30 segundos e foi interrompida para evitar um loop de recuperação.",
                    current,
                    false));
                return;
            }

            _lastCrashByLogicalTab[failed.LogicalId] = now;
            var wasActive = ReferenceEquals(_activeTab, failed);
            UnwireTab(failed);
            WebViewHost.Children.Remove(failed.View);
            _tabs.RemoveAt(index);
            var logicalId = failed.LogicalId;
            failed.Dispose();

            var replacement = new BrowserTab(_environment, _policy, _developerMode, this, _permissions, _downloads, logicalId);
            WireTab(replacement);
            await replacement.InitializeAsync();
            if (_closing)
            {
                UnwireTab(replacement);
                replacement.Dispose();
                return;
            }
            _tabs.Insert(index, replacement);
            WebViewHost.Children.Add(replacement.View);
            replacement.View.Visibility = Visibility.Collapsed;
            if (wasActive) ActivateTab(replacement);
            RenderTabs();
            replacement.Navigate(string.IsNullOrWhiteSpace(current) ? BrowserPolicy.HomeUrl : current);
        }
        catch (Exception error)
        {
            if (!_closing)
                StatusText.Text = $"Falha ao recuperar aba: {error.GetType().Name}";
        }
    }

    private void Downloads_StatusChanged(object? sender, BrowserDownloadStatus status)
    {
        if (_closing) return;
        Dispatcher.Invoke(() =>
        {
            if (_closing) return;
            var progress = status.TotalBytes is > 0
                ? $" {Math.Min(100, status.BytesReceived * 100 / status.TotalBytes.Value)}%"
                : string.Empty;
            StatusText.Text = $"Download {status.State}: {status.FileName}{progress}";
            CancelDownloadsButton.Visibility = _downloads.HasActiveDownloads ? Visibility.Visible : Visibility.Collapsed;
        });
    }

    private async void NewTab_Click(object sender, RoutedEventArgs e)
    {
        try { await CreateTabAsync(BrowserPolicy.HomeUrl, true); }
        catch (Exception error) { StatusText.Text = $"Não foi possível criar a aba: {error.GetType().Name}"; }
    }

    private void Back_Click(object sender, RoutedEventArgs e) => _activeTab?.GoBack();
    private void Forward_Click(object sender, RoutedEventArgs e) => _activeTab?.GoForward();
    private void ReloadStop_Click(object sender, RoutedEventArgs e)
    {
        if (_activeTab?.IsLoading == true) _activeTab.Stop();
        else _activeTab?.Reload();
    }
    private void Home_Click(object sender, RoutedEventArgs e) => _activeTab?.Navigate(BrowserPolicy.HomeUrl);
    private void AddressBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter || _activeTab is null) return;
        _activeTab.Navigate(AddressBox.Text);
        Keyboard.ClearFocus();
        e.Handled = true;
    }
    private void AddressBox_GotKeyboardFocus(object sender, KeyboardFocusChangedEventArgs e) => AddressBox.SelectAll();

    private void Favorite_Click(object sender, RoutedEventArgs e)
    {
        if (_activeTab?.CurrentUri is not { Scheme: "http" or "https" } uri) return;
        _stateStore.ToggleFavorite(uri, _activeTab.Title);
        RefreshChrome();
        if (LibraryPanel.Visibility == Visibility.Visible && LibraryTitle.Text == "Favoritos") PopulateFavorites();
    }

    private void Favorites_Click(object sender, RoutedEventArgs e)
    {
        LibraryPanel.Visibility = Visibility.Visible;
        LibraryTitle.Text = "Favoritos";
        ClearHistoryButton.Visibility = Visibility.Collapsed;
        PopulateFavorites();
    }

    private void History_Click(object sender, RoutedEventArgs e)
    {
        LibraryPanel.Visibility = Visibility.Visible;
        LibraryTitle.Text = "Histórico";
        ClearHistoryButton.Visibility = Visibility.Visible;
        LibraryList.ItemsSource = _stateStore.History.Reverse().Take(500).Select(x => new LibraryItem(x.Title, x.Url)).ToList();
    }

    private void PopulateFavorites() =>
        LibraryList.ItemsSource = _stateStore.Favorites.Select(x => new LibraryItem(x.Title, x.Url)).ToList();

    private void LibraryList_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (LibraryList.SelectedItem is not LibraryItem item || _activeTab is null) return;
        _activeTab.Navigate(item.Url);
        LibraryPanel.Visibility = Visibility.Collapsed;
    }

    private void CloseLibrary_Click(object sender, RoutedEventArgs e) => LibraryPanel.Visibility = Visibility.Collapsed;
    private void ClearHistory_Click(object sender, RoutedEventArgs e) { _stateStore.ClearHistory(); History_Click(sender, e); }
    private void Retry_Click(object sender, RoutedEventArgs e) => _activeTab?.Reload();
    private void ErrorBack_Click(object sender, RoutedEventArgs e)
    {
        if (_activeTab?.CanGoBack == true) _activeTab.GoBack();
        else _activeTab?.Navigate(BrowserPolicy.HomeUrl);
    }

    private void CancelDownloads_Click(object sender, RoutedEventArgs e)
    {
        var count = _downloads.CancelAll();
        StatusText.Text = count > 0 ? $"Cancelando {count} download(s)…" : "Nenhum download ativo.";
        CancelDownloadsButton.Visibility = _downloads.HasActiveDownloads ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (_closing) return;
        var control = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        var shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        var alt = Keyboard.Modifiers.HasFlag(ModifierKeys.Alt);

        if (control && e.Key == Key.L)
        {
            AddressBox.Focus();
            AddressBox.SelectAll();
            e.Handled = true;
        }
        else if (control && e.Key == Key.T && !shift)
        {
            try { await CreateTabAsync(BrowserPolicy.HomeUrl, true); }
            catch (Exception error) { StatusText.Text = $"Não foi possível criar a aba: {error.GetType().Name}"; }
            e.Handled = true;
        }
        else if (control && shift && e.Key == Key.T && _closedTabs.TryPop(out var closedUrl))
        {
            try { await CreateTabAsync(closedUrl, true); }
            catch (Exception error) { StatusText.Text = $"Não foi possível reabrir a aba: {error.GetType().Name}"; }
            e.Handled = true;
        }
        else if (control && e.Key == Key.W && _activeTab is not null)
        {
            CloseTab(_activeTab);
            e.Handled = true;
        }
        else if (control && e.Key == Key.Tab && _tabs.Count > 1)
        {
            var current = Math.Max(0, _tabs.IndexOf(_activeTab!));
            var direction = shift ? -1 : 1;
            var next = (current + direction + _tabs.Count) % _tabs.Count;
            ActivateTab(_tabs[next]);
            e.Handled = true;
        }
        else if (alt && e.Key == Key.Left)
        {
            _activeTab?.GoBack();
            e.Handled = true;
        }
        else if (alt && e.Key == Key.Right)
        {
            _activeTab?.GoForward();
            e.Handled = true;
        }
        else if (control && e.Key == Key.R)
        {
            _activeTab?.Reload();
            e.Handled = true;
        }
        else if (e.Key == Key.Escape && _activeTab?.IsLoading == true)
        {
            _activeTab.Stop();
            e.Handled = true;
        }
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (_closing) return;
        if (!_hostShutdown && _downloads.HasActiveDownloads)
        {
            var choice = MessageBox.Show(
                this,
                $"Existem {_downloads.ActiveCount} download(s) em andamento. Cancelar downloads e fechar?",
                "Navegador CloudOS",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            if (choice != MessageBoxResult.Yes)
            {
                e.Cancel = true;
                return;
            }
        }

        _closing = true;
        _permissions.CancelAll();
        _downloads.CancelAll();
        foreach (var tab in _tabs.ToArray())
        {
            UnwireTab(tab);
            WebViewHost.Children.Remove(tab.View);
            tab.Dispose();
        }
        _tabs.Clear();
        _activeTab = null;
        _lastCrashByLogicalTab.Clear();
        _downloads.StatusChanged -= Downloads_StatusChanged;
        _downloads.Dispose();
        _permissions.Dispose();
    }

    private sealed record LibraryItem(string Title, string Url)
    {
        public override string ToString() => $"{Title}\n{Url}";
    }
}
