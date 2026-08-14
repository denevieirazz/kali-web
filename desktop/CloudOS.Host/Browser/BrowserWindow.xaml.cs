using System.ComponentModel;
using System.Diagnostics;
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
    private readonly BrowserDownloadManager _downloads;
    private readonly List<BrowserTab> _tabs = [];
    private readonly Stack<ClosedTab> _closedTabs = new();
    private readonly Dictionary<Guid, DateTimeOffset> _lastCrashByLogicalTab = [];
    private BrowserTab? _activeTab;
    private bool _hostShutdown;
    private bool _closing;
    private bool _fullscreen;
    private WindowStyle _previousWindowStyle;
    private ResizeMode _previousResizeMode;
    private WindowState _previousWindowState;
    private bool _previousTopmost;

    public BrowserWindow(
        CoreWebView2Environment environment,
        BrowserPolicy policy,
        BrowserStateStore stateStore,
        bool developerMode,
        BrowserDownloadManager? downloadManager = null)
    {
        _environment = environment;
        _policy = policy;
        _stateStore = stateStore;
        _developerMode = developerMode;
        _downloads = downloadManager ?? new BrowserDownloadManager();
        InitializeComponent();
        _downloads.StatusChanged += Downloads_StatusChanged;
    }

    public int TabCount => _tabs.Count;
    public int ActiveDownloadCount => _downloads.ActiveCount;

    public async Task InitializeAsync(string? initialUrl)
    {
        if (!string.IsNullOrWhiteSpace(initialUrl))
        {
            var explicitTab = await CreateTabAsync(initialUrl, activate: true);
            if (explicitTab is null) throw new InvalidOperationException("Não foi possível criar a aba inicial do navegador.");
            return;
        }

        if (_stateStore.RestoreLastSession && _stateStore.Session is { Tabs.Count: > 0 } session)
        {
            var restored = new List<BrowserTab>();
            foreach (var saved in session.Tabs.Take(MaxTabs))
            {
                var tab = await CreateTabAsync(saved.Url, activate: false, isPinned: saved.Pinned);
                if (tab is not null) restored.Add(tab);
            }
            if (restored.Count > 0)
            {
                ActivateTab(restored[Math.Clamp(session.ActiveIndex, 0, restored.Count - 1)]);
                return;
            }
        }

        var tab = await CreateTabAsync(null, activate: true, isNewTabPage: true);
        if (tab is null) throw new InvalidOperationException("Não foi possível criar a aba inicial do navegador.");
    }

    public Task NavigateActiveAsync(string raw)
    {
        _activeTab?.Navigate(raw);
        return Task.CompletedTask;
    }

    public int CancelDownloads() => _downloads.CancelAll();

    public void CloseForHostShutdown()
    {
        _hostShutdown = true;
        Close();
    }

    private async Task<BrowserTab?> CreateTabAsync(
        string? initialUrl = null,
        bool activate = true,
        Guid? logicalId = null,
        bool isNewTabPage = false,
        bool isPinned = false,
        bool popupTarget = false)
    {
        if (_closing) return null;
        if (_tabs.Count >= MaxTabs)
        {
            StatusText.Text = "Limite de 32 abas atingido.";
            return null;
        }

        var tab = new BrowserTab(
            _environment,
            _policy,
            _developerMode,
            this,
            _permissions,
            _downloads,
            logicalId,
            isNewTabPage,
            isPinned);
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

            InsertTab(tab);
            WebViewHost.Children.Add(tab.View);
            tab.View.Visibility = Visibility.Collapsed;
            RenderTabs();
            if (activate) ActivateTab(tab);

            if (isNewTabPage)
                tab.ShowNewTabPage();
            else if (!popupTarget && !string.IsNullOrWhiteSpace(initialUrl))
                tab.Navigate(initialUrl);
            return tab;
        }
        catch
        {
            UnwireTab(tab);
            tab.Dispose();
            throw;
        }
    }

    private void InsertTab(BrowserTab tab)
    {
        if (!tab.IsPinned)
        {
            _tabs.Add(tab);
            return;
        }
        var firstUnpinned = _tabs.FindIndex(item => !item.IsPinned);
        if (firstUnpinned < 0) _tabs.Add(tab);
        else _tabs.Insert(firstUnpinned, tab);
    }

    private void WireTab(BrowserTab tab)
    {
        tab.StateChanged += Tab_StateChanged;
        tab.RendererFailed += Tab_RendererFailed;
        tab.NewWindowFactory = async () =>
        {
            if (_closing) return null;
            return (await CreateTabAsync(activate: true, popupTarget: true))?.View.CoreWebView2;
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
        if (remember) RememberClosedTab(tab);

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

    private void RememberClosedTab(BrowserTab tab)
    {
        var closed = tab.IsNewTabPage
            ? new ClosedTab(null, true, tab.IsPinned)
            : tab.CurrentUri is { Scheme: "http" or "https" } uri
                ? new ClosedTab(uri.AbsoluteUri, false, tab.IsPinned)
                : null;
        if (closed is null) return;

        if (_closedTabs.Count >= MaxTabs)
        {
            var keep = _closedTabs.Reverse().Take(MaxTabs - 1).Reverse().ToArray();
            _closedTabs.Clear();
            foreach (var item in keep) _closedTabs.Push(item);
        }
        _closedTabs.Push(closed);
    }

    private async Task ReopenClosedTabAsync()
    {
        if (!_closedTabs.TryPop(out var closed)) return;
        await CreateTabAsync(
            closed.Url,
            activate: true,
            isNewTabPage: closed.IsNewTabPage,
            isPinned: closed.WasPinned);
    }

    private async Task DuplicateTabAsync(BrowserTab tab)
    {
        if (tab.IsNewTabPage)
            await CreateTabAsync(activate: true, isNewTabPage: true);
        else if (tab.CurrentUri is { Scheme: "http" or "https" } uri)
            await CreateTabAsync(uri.AbsoluteUri, activate: true);
    }

    private void SetPinned(BrowserTab tab, bool pinned)
    {
        if (!_tabs.Contains(tab)) return;
        var wasActive = ReferenceEquals(tab, _activeTab);
        _tabs.Remove(tab);
        tab.SetPinned(pinned);
        InsertTab(tab);
        RenderTabs();
        if (wasActive) ActivateTab(tab);
    }

    private void RenderTabs()
    {
        TabStrip.Children.Clear();
        foreach (var tab in _tabs)
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            var prefix = tab.IsPinned ? "📌 " : string.Empty;
            prefix += tab.IsMuted ? "🔇 " : tab.IsPlayingAudio ? "🔊 " : string.Empty;
            var rawTitle = string.IsNullOrWhiteSpace(tab.Title) ? "Nova aba" : tab.Title;
            var title = rawTitle.Length > 22 ? rawTitle[..22] + "…" : rawTitle;
            var select = new Button
            {
                Content = prefix + title,
                Tag = tab,
                MinWidth = tab.IsPinned ? 90 : 115,
                MaxWidth = 210,
                Padding = new Thickness(10, 4, 8, 4),
                Margin = new Thickness(1),
                FontWeight = ReferenceEquals(tab, _activeTab) ? FontWeights.SemiBold : FontWeights.Normal,
                ContextMenu = CreateTabContextMenu(tab)
            };
            select.Click += (_, _) => ActivateTab((BrowserTab)select.Tag);
            var close = new Button { Content = "×", Tag = tab, Width = 28, Margin = new Thickness(0, 1, 4, 1) };
            close.Click += (_, _) => CloseTab((BrowserTab)close.Tag);
            panel.Children.Add(select);
            panel.Children.Add(close);
            TabStrip.Children.Add(panel);
        }
    }

    private ContextMenu CreateTabContextMenu(BrowserTab tab)
    {
        var menu = new ContextMenu();
        var duplicate = new MenuItem { Header = "Duplicar aba" };
        duplicate.Click += async (_, _) => await RunUiActionAsync(() => DuplicateTabAsync(tab));
        var pin = new MenuItem { Header = tab.IsPinned ? "Desafixar aba" : "Fixar aba" };
        pin.Click += (_, _) => SetPinned(tab, !tab.IsPinned);
        var mute = new MenuItem { Header = tab.IsMuted ? "Ativar áudio" : "Silenciar aba" };
        mute.Click += (_, _) => tab.ToggleMuted();
        var close = new MenuItem { Header = "Fechar aba" };
        close.Click += (_, _) => CloseTab(tab);
        menu.Items.Add(duplicate);
        menu.Items.Add(pin);
        menu.Items.Add(mute);
        menu.Items.Add(new Separator());
        menu.Items.Add(close);
        return menu;
    }

    private void RefreshChrome()
    {
        var tab = _activeTab;
        if (tab is null) return;
        BackButton.IsEnabled = tab.CanGoBack;
        ForwardButton.IsEnabled = tab.CanGoForward;
        ReloadStopButton.Content = tab.IsLoading ? "×" : "↻";
        ReloadStopButton.ToolTip = tab.IsLoading ? "Parar (Esc)" : "Recarregar (Ctrl+R)";
        LoadProgress.Visibility = tab.IsLoading ? Visibility.Visible : Visibility.Collapsed;
        ZoomStatusText.Text = $"{Math.Round(tab.ZoomFactor * 100):0}%";
        if (!AddressBox.IsKeyboardFocusWithin)
            AddressBox.Text = tab.IsNewTabPage || tab.CurrentUri is null ? string.Empty : _policy.DisplayUri(tab.CurrentUri);
        FavoriteButton.IsEnabled = tab.CurrentUri is { Scheme: "http" or "https" } && !tab.IsNewTabPage;
        FavoriteButton.Content = tab.CurrentUri is not null && _stateStore.IsFavorite(tab.CurrentUri) ? "★" : "☆";
        Title = tab.IsNewTabPage || string.IsNullOrWhiteSpace(tab.Title)
            ? "Navegador CloudOS"
            : $"{tab.Title} — Navegador CloudOS";
        CancelDownloadsButton.Visibility = _downloads.HasActiveDownloads ? Visibility.Visible : Visibility.Collapsed;
        SecurityIndicator.Text = tab.IsNewTabPage
            ? "CloudOS"
            : tab.CurrentUri?.Scheme switch
            {
                "https" => "🔒 HTTPS",
                "http" => "HTTP",
                _ => "—"
            };
        SecurityIndicator.Foreground = tab.CurrentUri?.Scheme == "https"
            ? System.Windows.Media.Brushes.LightGreen
            : System.Windows.Media.Brushes.LightGray;

        NewTabPanel.Visibility = Visibility.Collapsed;
        ErrorPanel.Visibility = Visibility.Collapsed;
        if (tab.IsNewTabPage)
        {
            tab.View.Visibility = Visibility.Collapsed;
            NewTabPanel.Visibility = Visibility.Visible;
            if (!NewTabSearchBox.IsKeyboardFocusWithin) NewTabSearchBox.Text = string.Empty;
            StatusText.Text = "Nova aba";
            return;
        }

        if (tab.Error is null)
        {
            tab.View.Visibility = Visibility.Visible;
            if (!_downloads.HasActiveDownloads) StatusText.Text = tab.IsLoading ? "Carregando…" : "Pronto";
        }
        else
        {
            ErrorCodeText.Text = tab.Error.Code;
            ErrorMessageText.Text = tab.Error.Message +
                (string.IsNullOrWhiteSpace(tab.Error.Uri) ? string.Empty : $"\n{tab.Error.Uri}");
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
        if (!tab.IsNewTabPage && !tab.IsLoading && tab.Error is null &&
            tab.CurrentUri is { Scheme: "http" or "https" } uri)
        {
            var latest = _stateStore.History.LastOrDefault();
            if (latest is null ||
                !latest.Url.Equals(BrowserStateStore.SanitizePersistedUri(uri), StringComparison.OrdinalIgnoreCase) ||
                DateTimeOffset.UtcNow - latest.VisitedAt > TimeSpan.FromSeconds(2))
                TryPersist(() => _stateStore.AddHistory(uri, tab.Title));
        }
    }

    private async void Tab_RendererFailed(object? sender, EventArgs e)
    {
        if (_closing || sender is not BrowserTab failed) return;
        try
        {
            var current = failed.IsNewTabPage ? null : failed.CurrentUri?.AbsoluteUri;
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
            var wasNewTab = failed.IsNewTabPage;
            var wasPinned = failed.IsPinned;
            var wasMuted = failed.IsMuted;
            var zoom = failed.ZoomFactor;
            UnwireTab(failed);
            WebViewHost.Children.Remove(failed.View);
            _tabs.RemoveAt(index);
            var logicalId = failed.LogicalId;
            failed.Dispose();

            var replacement = new BrowserTab(
                _environment,
                _policy,
                _developerMode,
                this,
                _permissions,
                _downloads,
                logicalId,
                wasNewTab,
                wasPinned);
            WireTab(replacement);
            await replacement.InitializeAsync();
            if (_closing)
            {
                UnwireTab(replacement);
                replacement.Dispose();
                return;
            }
            replacement.SetZoom(zoom);
            if (wasMuted) replacement.ToggleMuted();
            _tabs.Insert(Math.Min(index, _tabs.Count), replacement);
            WebViewHost.Children.Add(replacement.View);
            replacement.View.Visibility = Visibility.Collapsed;
            if (wasActive) ActivateTab(replacement);
            RenderTabs();
            if (wasNewTab) replacement.ShowNewTabPage();
            else replacement.Navigate(string.IsNullOrWhiteSpace(current) ? BrowserPolicy.HomeUrl : current);
        }
        catch (Exception error)
        {
            if (!_closing) StatusText.Text = $"Falha ao recuperar aba: {error.GetType().Name}";
        }
    }

    private void Downloads_StatusChanged(object? sender, BrowserDownloadStatus status)
    {
        if (_closing) return;
        Dispatcher.BeginInvoke(() =>
        {
            if (_closing) return;
            var progress = status.TotalBytes is > 0
                ? $" {Math.Min(100, status.BytesReceived * 100 / status.TotalBytes.Value)}%"
                : string.Empty;
            StatusText.Text = $"Download {status.State}: {status.FileName}{progress}";
            CancelDownloadsButton.Visibility = _downloads.HasActiveDownloads ? Visibility.Visible : Visibility.Collapsed;
        });
    }

    private async void NewTab_Click(object sender, RoutedEventArgs e) =>
        await RunUiActionAsync(() => CreateTabAsync(activate: true, isNewTabPage: true));

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

    private void NewTabSearchBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return;
        NavigateFromNewTab();
        e.Handled = true;
    }
    private void NewTabGo_Click(object sender, RoutedEventArgs e) => NavigateFromNewTab();
    private void NewTabDuck_Click(object sender, RoutedEventArgs e) => _activeTab?.Navigate(BrowserPolicy.HomeUrl);

    private void NavigateFromNewTab()
    {
        if (_activeTab is null) return;
        _activeTab.Navigate(NewTabSearchBox.Text);
        Keyboard.ClearFocus();
    }

    private void Favorite_Click(object sender, RoutedEventArgs e)
    {
        if (_activeTab?.CurrentUri is not { Scheme: "http" or "https" } uri || _activeTab.IsNewTabPage) return;
        TryPersist(() => _stateStore.ToggleFavorite(uri, _activeTab.Title));
        RefreshChrome();
        if (LibraryPanel.Visibility == Visibility.Visible && LibraryTitle.Text == "Favoritos") PopulateFavorites();
    }

    private void Favorites_Click(object sender, RoutedEventArgs e)
    {
        LibraryPanel.Visibility = Visibility.Visible;
        LibraryTitle.Text = "Favoritos";
        ClearHistoryButton.Visibility = Visibility.Collapsed;
        LibrarySearchBox.Text = string.Empty;
        PopulateFavorites();
    }

    private void History_Click(object sender, RoutedEventArgs e)
    {
        LibraryPanel.Visibility = Visibility.Visible;
        LibraryTitle.Text = "Histórico";
        ClearHistoryButton.Visibility = Visibility.Visible;
        LibrarySearchBox.Text = string.Empty;
        PopulateHistory();
    }

    private void PopulateFavorites() =>
        LibraryList.ItemsSource = _stateStore.SearchFavorites(LibrarySearchBox.Text)
            .Select(x => new LibraryItem(x.Title, x.Url)).ToList();

    private void PopulateHistory() =>
        LibraryList.ItemsSource = _stateStore.SearchHistory(LibrarySearchBox.Text)
            .Select(x => new LibraryItem(x.Title, x.Url)).ToList();

    private void LibrarySearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (LibraryPanel.Visibility != Visibility.Visible) return;
        if (LibraryTitle.Text == "Histórico") PopulateHistory();
        else PopulateFavorites();
    }

    private void LibraryList_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (LibraryList.SelectedItem is not LibraryItem item || _activeTab is null) return;
        _activeTab.Navigate(item.Url);
        LibraryPanel.Visibility = Visibility.Collapsed;
    }

    private void CloseLibrary_Click(object sender, RoutedEventArgs e) => LibraryPanel.Visibility = Visibility.Collapsed;

    private void ClearHistory_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(this, "Limpar todo o histórico do Navegador CloudOS?", "Histórico", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes)
            return;
        TryPersist(_stateStore.ClearHistory);
        PopulateHistory();
    }

    private void Retry_Click(object sender, RoutedEventArgs e) => _activeTab?.Reload();
    private void ErrorBack_Click(object sender, RoutedEventArgs e)
    {
        if (_activeTab?.CanGoBack == true) _activeTab.GoBack();
        else _activeTab?.ShowNewTabPage();
    }

    private void CancelDownloads_Click(object sender, RoutedEventArgs e)
    {
        var count = _downloads.CancelAll();
        StatusText.Text = count > 0 ? $"Cancelando {count} download(s)…" : "Nenhum download ativo.";
        CancelDownloadsButton.Visibility = _downloads.HasActiveDownloads ? Visibility.Visible : Visibility.Collapsed;
    }

    private void BrowserMenu_Click(object sender, RoutedEventArgs e)
    {
        var menu = BuildBrowserMenu();
        menu.PlacementTarget = sender as Button;
        menu.IsOpen = true;
    }

    private ContextMenu BuildBrowserMenu()
    {
        var menu = new ContextMenu();
        var newTab = new MenuItem { Header = "Nova aba\tCtrl+T" };
        newTab.Click += async (_, _) => await RunUiActionAsync(() => CreateTabAsync(activate: true, isNewTabPage: true));
        var reopen = new MenuItem { Header = "Reabrir aba fechada\tCtrl+Shift+T", IsEnabled = _closedTabs.Count > 0 };
        reopen.Click += async (_, _) => await RunUiActionAsync(ReopenClosedTabAsync);
        var duplicate = new MenuItem { Header = "Duplicar aba", IsEnabled = _activeTab is not null };
        duplicate.Click += async (_, _) => await RunUiActionAsync(() => _activeTab is null ? Task.CompletedTask : DuplicateTabAsync(_activeTab));
        menu.Items.Add(newTab);
        menu.Items.Add(reopen);
        menu.Items.Add(duplicate);
        menu.Items.Add(new Separator());

        var mute = new MenuItem { Header = _activeTab?.IsMuted == true ? "Ativar áudio da aba" : "Silenciar aba", IsEnabled = _activeTab is not null };
        mute.Click += (_, _) => _activeTab?.ToggleMuted();
        var pin = new MenuItem { Header = _activeTab?.IsPinned == true ? "Desafixar aba" : "Fixar aba", IsEnabled = _activeTab is not null };
        pin.Click += (_, _) => { if (_activeTab is not null) SetPinned(_activeTab, !_activeTab.IsPinned); };
        menu.Items.Add(pin);
        menu.Items.Add(mute);
        menu.Items.Add(new Separator());

        var zoomOut = new MenuItem { Header = "Diminuir zoom" };
        zoomOut.Click += (_, _) => _activeTab?.AdjustZoom(-0.1);
        var zoomReset = new MenuItem { Header = "Zoom 100%" };
        zoomReset.Click += (_, _) => _activeTab?.ResetZoom();
        var zoomIn = new MenuItem { Header = "Aumentar zoom" };
        zoomIn.Click += (_, _) => _activeTab?.AdjustZoom(0.1);
        menu.Items.Add(zoomOut);
        menu.Items.Add(zoomReset);
        menu.Items.Add(zoomIn);

        var fullscreen = new MenuItem { Header = _fullscreen ? "Sair da tela cheia\tF11" : "Tela cheia\tF11" };
        fullscreen.Click += (_, _) => SetFullscreen(!_fullscreen);
        menu.Items.Add(fullscreen);
        menu.Items.Add(new Separator());

        var print = new MenuItem { Header = "Imprimir", IsEnabled = _activeTab is { IsNewTabPage: false } };
        print.Click += (_, _) => TryUiAction(() => _activeTab?.Print());
        var save = new MenuItem { Header = "Salvar página", IsEnabled = _activeTab is { IsNewTabPage: false } };
        save.Click += async (_, _) => await SaveActivePageAsync();
        menu.Items.Add(print);
        menu.Items.Add(save);
        menu.Items.Add(new Separator());

        var restore = new MenuItem
        {
            Header = "Restaurar última sessão ao abrir",
            IsCheckable = true,
            IsChecked = _stateStore.RestoreLastSession
        };
        restore.Click += (_, _) => TryPersist(() => _stateStore.SetRestoreLastSession(restore.IsChecked));
        var clearData = new MenuItem { Header = "Limpar dados do navegador…" };
        clearData.Click += async (_, _) => await ClearBrowserDataAsync();
        menu.Items.Add(restore);
        menu.Items.Add(clearData);
        return menu;
    }

    private async Task SaveActivePageAsync()
    {
        if (_activeTab is null) return;
        try
        {
            var result = await _activeTab.SavePageAsync();
            if (result is not null) StatusText.Text = $"Salvar página: {result}";
        }
        catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException or System.Runtime.InteropServices.COMException)
        {
            StatusText.Text = $"Não foi possível salvar a página: {error.GetType().Name}";
        }
    }

    private async Task ClearBrowserDataAsync()
    {
        if (_activeTab?.View.CoreWebView2?.Profile is not { } profile) return;
        if (MessageBox.Show(
                this,
                "Isso apagará cookies, cache, armazenamento de sites, histórico, favoritos e sessão do Navegador CloudOS. Continuar?",
                "Limpar dados do navegador",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;

        try
        {
            _permissions.CancelAll();
            _downloads.CancelAll();
            await profile.ClearBrowsingDataAsync(CoreWebView2BrowsingDataKinds.AllProfile);
            _stateStore.ClearUserState();

            foreach (var tab in _tabs.Where(tab => !ReferenceEquals(tab, _activeTab)).ToArray())
                CloseTab(tab, remember: false);
            _closedTabs.Clear();
            _activeTab?.ShowNewTabPage();
            LibraryPanel.Visibility = Visibility.Collapsed;
            StatusText.Text = "Dados do navegador limpos.";
        }
        catch (Exception error) when (error is InvalidOperationException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException or IOException)
        {
            StatusText.Text = $"Falha ao limpar dados: {error.GetType().Name}";
        }
    }

    private void SetFullscreen(bool enabled)
    {
        if (enabled == _fullscreen) return;
        if (enabled)
        {
            _previousWindowStyle = WindowStyle;
            _previousResizeMode = ResizeMode;
            _previousWindowState = WindowState;
            _previousTopmost = Topmost;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            WindowState = WindowState.Maximized;
            Topmost = false;
        }
        else
        {
            Topmost = _previousTopmost;
            WindowStyle = _previousWindowStyle;
            ResizeMode = _previousResizeMode;
            WindowState = _previousWindowState == WindowState.Minimized ? WindowState.Normal : _previousWindowState;
        }
        _fullscreen = enabled;
    }

    private async void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (_closing) return;
        var control = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        var shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        var alt = Keyboard.Modifiers.HasFlag(ModifierKeys.Alt);

        if (e.Key == Key.F11)
        {
            SetFullscreen(!_fullscreen);
            e.Handled = true;
        }
        else if (control && e.Key == Key.L)
        {
            AddressBox.Focus();
            AddressBox.SelectAll();
            e.Handled = true;
        }
        else if (control && e.Key == Key.T && !shift)
        {
            await RunUiActionAsync(() => CreateTabAsync(activate: true, isNewTabPage: true));
            e.Handled = true;
        }
        else if (control && shift && e.Key == Key.T)
        {
            await RunUiActionAsync(ReopenClosedTabAsync);
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
        else if (control && (e.Key == Key.Add || e.Key == Key.OemPlus))
        {
            _activeTab?.AdjustZoom(0.1);
            e.Handled = true;
        }
        else if (control && (e.Key == Key.Subtract || e.Key == Key.OemMinus))
        {
            _activeTab?.AdjustZoom(-0.1);
            e.Handled = true;
        }
        else if (control && e.Key == Key.D0)
        {
            _activeTab?.ResetZoom();
            e.Handled = true;
        }
        else if (e.Key == Key.Escape && _activeTab?.IsLoading == true)
        {
            _activeTab.Stop();
            e.Handled = true;
        }
    }

    private void SaveSessionForExit()
    {
        try
        {
            if (!_stateStore.RestoreLastSession)
            {
                _stateStore.ClearSession();
                return;
            }

            var activeIndex = _activeTab is null ? 0 : Math.Max(0, _tabs.IndexOf(_activeTab));
            var sessionTabs = _tabs.Select(tab =>
            {
                var url = tab.IsNewTabPage ? string.Empty : tab.CurrentUri?.AbsoluteUri ?? string.Empty;
                return new BrowserSessionTab(url, tab.IsPinned);
            }).Where(tab => tab.Url.Length > 0).ToList();
            _stateStore.SaveSession(sessionTabs, activeIndex);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            Trace.TraceWarning("Browser session persistence failed: {0}", error.GetType().Name);
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
        SaveSessionForExit();
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

    private void TryPersist(Action action)
    {
        try { action(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            StatusText.Text = $"Estado não pôde ser salvo: {error.GetType().Name}";
        }
    }

    private void TryUiAction(Action action)
    {
        try { action(); }
        catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException or System.Runtime.InteropServices.COMException)
        {
            StatusText.Text = $"Operação indisponível: {error.GetType().Name}";
        }
    }

    private async Task RunUiActionAsync(Func<Task> action)
    {
        try { await action(); }
        catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException or OperationCanceledException or System.Runtime.InteropServices.COMException)
        {
            StatusText.Text = $"Operação indisponível: {error.GetType().Name}";
        }
    }

    private sealed record LibraryItem(string Title, string Url)
    {
        public override string ToString() => $"{Title}\n{Url}";
    }

    private sealed record ClosedTab(string? Url, bool IsNewTabPage, bool WasPinned);
}
