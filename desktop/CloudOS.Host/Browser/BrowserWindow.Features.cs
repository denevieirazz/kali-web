using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Host.Browser;

public partial class BrowserWindow
{
    private readonly Dictionary<string, DownloadUiSnapshot> _downloadUiHistory = new(StringComparer.Ordinal);
    private bool _featureSurfacesInitialized;
    private string? _activeHub;

    private void InitializeFeatureSurfaces()
    {
        if (_featureSurfacesInitialized) return;
        _featureSurfacesInitialized = true;
        _downloads.StatusChanged += FeatureDownloads_StatusChanged;
        Closed += BrowserWindowFeatures_Closed;
    }

    private void BrowserWindowFeatures_Closed(object? sender, EventArgs e)
    {
        _downloads.StatusChanged -= FeatureDownloads_StatusChanged;
        Closed -= BrowserWindowFeatures_Closed;
    }

    private void ModernBrowserMenu_Click(object sender, RoutedEventArgs e)
    {
        MenuReopenButton.IsEnabled = _webViewReady && _closedTabs.Count > 0;
        MenuDuplicateButton.IsEnabled = _webViewReady && _activeTab is not null;
        MenuPrintButton.IsEnabled = _activeTab is { IsNewTabPage: false };
        MenuSaveButton.IsEnabled = _activeTab is { IsNewTabPage: false };
        MenuZoomText.Text = _activeTab is null ? "100%" : $"{Math.Round(_activeTab.ZoomFactor * 100):0}%";
        MenuFullscreenText.Text = _fullscreen ? "Sair da tela cheia" : "Tela cheia";
        BrowserMenuPopup.IsOpen = true;
    }

    private void CloseModernMenu() => BrowserMenuPopup.IsOpen = false;

    private async void MenuNewTab_Click(object sender, RoutedEventArgs e)
    {
        CloseModernMenu();
        await RunUiActionAsync(() => CreateTabAsync(activate: true, isNewTabPage: true));
    }

    private async void MenuReopen_Click(object sender, RoutedEventArgs e)
    {
        CloseModernMenu();
        await RunUiActionAsync(ReopenClosedTabAsync);
    }

    private async void MenuDuplicate_Click(object sender, RoutedEventArgs e)
    {
        CloseModernMenu();
        if (_activeTab is not null)
            await RunUiActionAsync(() => DuplicateTabAsync(_activeTab));
    }

    private void MenuZoomOut_Click(object sender, RoutedEventArgs e) { _activeTab?.AdjustZoom(-0.1); NormalizeDynamicChrome(); }
    private void MenuZoomReset_Click(object sender, RoutedEventArgs e) { _activeTab?.ResetZoom(); NormalizeDynamicChrome(); }
    private void MenuZoomIn_Click(object sender, RoutedEventArgs e) { _activeTab?.AdjustZoom(0.1); NormalizeDynamicChrome(); }
    private void MenuFullscreen_Click(object sender, RoutedEventArgs e) { CloseModernMenu(); SetFullscreen(!_fullscreen); }
    private void MenuDownloads_Click(object sender, RoutedEventArgs e) { CloseModernMenu(); ShowDownloadsHub(); }
    private void ModernDownloads_Click(object sender, RoutedEventArgs e) => ShowDownloadsHub();
    private void MenuFavorites_Click(object sender, RoutedEventArgs e) { CloseModernMenu(); HideHubWithoutRefresh(); Favorites_Click(sender, e); }
    private void MenuHistory_Click(object sender, RoutedEventArgs e) { CloseModernMenu(); HideHubWithoutRefresh(); History_Click(sender, e); }
    private async void MenuExtensions_Click(object sender, RoutedEventArgs e) { CloseModernMenu(); await ShowExtensionsHubAsync(); }
    private void MenuSettings_Click(object sender, RoutedEventArgs e) { CloseModernMenu(); ShowSettingsHub(); }
    private void MenuPrint_Click(object sender, RoutedEventArgs e) { CloseModernMenu(); TryUiAction(() => _activeTab?.Print()); }
    private async void MenuSave_Click(object sender, RoutedEventArgs e) { CloseModernMenu(); await SaveActivePageAsync(); }
    private async void MenuClearData_Click(object sender, RoutedEventArgs e) { CloseModernMenu(); await ClearBrowserDataAsync(); }

    private void ShowHub(string kind, string title, string subtitle)
    {
        _activeHub = kind;
        BrowserMenuPopup.IsOpen = false;
        LibraryPanel.Visibility = Visibility.Collapsed;
        HubTitle.Text = title;
        HubSubtitle.Text = subtitle;
        HubContent.Children.Clear();
        if (_activeTab is not null) _activeTab.View.Visibility = Visibility.Collapsed;
        NewTabPanel.Visibility = Visibility.Collapsed;
        ErrorPanel.Visibility = Visibility.Collapsed;
        HubPanel.Visibility = Visibility.Visible;
    }

    private void HideHubWithoutRefresh()
    {
        _activeHub = null;
        HubPanel.Visibility = Visibility.Collapsed;
        HubContent.Children.Clear();
    }

    private void CloseHub_Click(object sender, RoutedEventArgs e)
    {
        HideHubWithoutRefresh();
        if (_activeTab is not null) RefreshChrome();
    }

    private void ShowDownloadsHub()
    {
        ShowHub("downloads", "Downloads", "Downloads iniciados nesta sessão do navegador.");
        RefreshDownloadsView();
    }

    private void FeatureDownloads_StatusChanged(object? sender, BrowserDownloadStatus status)
    {
        if (_closing) return;
        _ = Dispatcher.BeginInvoke(() =>
        {
            if (_closing) return;
            _downloadUiHistory[status.Id] = new DownloadUiSnapshot(status, DateTimeOffset.Now);
            DownloadActivityDot.Visibility = _downloads.HasActiveDownloads ? Visibility.Visible : Visibility.Collapsed;
            if (_activeHub == "downloads") RefreshDownloadsView();
        });
    }

    private void RefreshDownloadsView()
    {
        HubContent.Children.Clear();
        var items = _downloadUiHistory.Values.OrderByDescending(item => item.UpdatedAt).ToList();
        HubSubtitle.Text = items.Count == 0 ? "Nenhum download nesta sessão." : $"{items.Count} download(s) nesta sessão.";
        if (items.Count == 0)
        {
            HubContent.Children.Add(MutedText("Os downloads aparecerão aqui depois que você escolher um destino para salvar."));
            return;
        }

        foreach (var item in items)
        {
            var status = item.Status;
            var progress = status.TotalBytes is > 0
                ? Math.Clamp(status.BytesReceived * 100d / status.TotalBytes.Value, 0d, 100d)
                : status.State.Equals("Completed", StringComparison.OrdinalIgnoreCase) ? 100d : 0d;
            var detail = status.TotalBytes is > 0
                ? $"{status.State} · {FormatBytes(status.BytesReceived)} de {FormatBytes(status.TotalBytes.Value)}"
                : $"{status.State} · {FormatBytes(status.BytesReceived)}";
            if (!string.IsNullOrWhiteSpace(status.InterruptReason)) detail += $" · {status.InterruptReason}";

            var stack = new StackPanel();
            stack.Children.Add(new TextBlock { Text = status.FileName, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis });
            stack.Children.Add(MutedText(detail));
            stack.Children.Add(new ProgressBar { Height = 4, Margin = new Thickness(0, 8, 0, 0), Minimum = 0, Maximum = 100, Value = progress });
            HubContent.Children.Add(Card(stack));
        }

        if (_downloads.HasActiveDownloads)
        {
            var cancel = SecondaryButton("Cancelar downloads ativos");
            cancel.Margin = new Thickness(0, 8, 0, 0);
            cancel.Click += CancelDownloads_Click;
            HubContent.Children.Add(cancel);
        }
    }

    private static string FormatBytes(long value)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        var size = Math.Max(0, (double)value);
        var index = 0;
        while (size >= 1024 && index < units.Length - 1) { size /= 1024; index++; }
        return $"{size:0.#} {units[index]}";
    }

    private CoreWebView2Profile? ActiveProfile => _activeTab?.View.CoreWebView2?.Profile;

    private async Task ShowExtensionsHubAsync()
    {
        ShowHub("extensions", "Extensões", "Extensões locais descompactadas no perfil isolado do navegador.");
        await RefreshExtensionsViewAsync();
    }

    private async Task RefreshExtensionsViewAsync()
    {
        HubContent.Children.Clear();
        var install = SecondaryButton("Carregar extensão descompactada…");
        install.Click += InstallExtension_Click;
        HubContent.Children.Add(install);
        HubContent.Children.Add(MutedText("Escolha uma pasta local que contenha manifest.json. A extensão fica somente no perfil isolado do Browser."));

        var profile = ActiveProfile;
        if (profile is null) { HubSubtitle.Text = "O perfil WebView2 ainda não está pronto."; return; }
        try
        {
            var extensions = await profile.GetBrowserExtensionsAsync();
            HubSubtitle.Text = extensions.Count == 0 ? "Nenhuma extensão instalada." : $"{extensions.Count} extensão(ões) instalada(s).";
            foreach (var extension in extensions.OrderBy(x => x.Name, StringComparer.CurrentCultureIgnoreCase))
            {
                var stack = new StackPanel();
                stack.Children.Add(new TextBlock { Text = extension.Name, FontWeight = FontWeights.SemiBold });
                stack.Children.Add(MutedText(extension.IsEnabled ? "Ativa" : "Desativada"));
                var actions = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0) };
                var toggle = SecondaryButton(extension.IsEnabled ? "Desativar" : "Ativar");
                toggle.Tag = extension.Id;
                toggle.Click += ToggleExtension_Click;
                var remove = SecondaryButton("Remover");
                remove.Tag = extension.Id;
                remove.Margin = new Thickness(8, 0, 0, 0);
                remove.Click += RemoveExtension_Click;
                actions.Children.Add(toggle); actions.Children.Add(remove); stack.Children.Add(actions);
                HubContent.Children.Add(Card(stack));
            }
        }
        catch (Exception error) when (error is InvalidOperationException or COMException or NotSupportedException)
        {
            HubSubtitle.Text = $"Extensões indisponíveis: {error.GetType().Name}.";
        }
    }

    private async void InstallExtension_Click(object sender, RoutedEventArgs e)
    {
        var profile = ActiveProfile;
        if (profile is null) { HubSubtitle.Text = "O perfil WebView2 ainda não está pronto."; return; }
        var dialog = new OpenFolderDialog { Title = "Selecionar extensão descompactada", Multiselect = false };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var folder = Path.GetFullPath(dialog.FolderName);
            if (!Directory.Exists(folder) || !File.Exists(Path.Combine(folder, "manifest.json")))
            {
                MessageBox.Show(this, "A pasta precisa conter manifest.json.", "Extensões", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            await profile.AddBrowserExtensionAsync(folder);
            await RefreshExtensionsViewAsync();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException or InvalidOperationException or COMException)
        {
            HubSubtitle.Text = $"Não foi possível instalar: {error.GetType().Name}.";
        }
    }

    private async void ToggleExtension_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string id }) return;
        var extension = await FindExtensionAsync(id); if (extension is null) return;
        try { await extension.EnableAsync(!extension.IsEnabled); await RefreshExtensionsViewAsync(); }
        catch (Exception error) when (error is InvalidOperationException or COMException) { HubSubtitle.Text = $"Falha ao alterar extensão: {error.GetType().Name}."; }
    }

    private async void RemoveExtension_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string id }) return;
        var extension = await FindExtensionAsync(id); if (extension is null) return;
        if (MessageBox.Show(this, $"Remover “{extension.Name}” deste perfil?", "Extensões", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        try { await extension.RemoveAsync(); await RefreshExtensionsViewAsync(); }
        catch (Exception error) when (error is InvalidOperationException or COMException) { HubSubtitle.Text = $"Falha ao remover extensão: {error.GetType().Name}."; }
    }

    private async Task<CoreWebView2BrowserExtension?> FindExtensionAsync(string id)
    {
        try { return ActiveProfile is { } profile ? (await profile.GetBrowserExtensionsAsync()).FirstOrDefault(x => x.Id.Equals(id, StringComparison.Ordinal)) : null; }
        catch (Exception error) when (error is InvalidOperationException or COMException) { HubSubtitle.Text = $"Falha ao consultar extensões: {error.GetType().Name}."; return null; }
    }

    private void ShowSettingsHub()
    {
        ShowHub("settings", "Configurações", "Preferências do Browser e do perfil WebView2 isolado.");
        BuildSettingsView();
    }

    private void BuildSettingsView()
    {
        HubContent.Children.Clear();
        HubContent.Children.Add(SectionTitle("Aparência"));
        var themes = new WrapPanel { Margin = new Thickness(0, 8, 0, 16) };
        foreach (var item in new[] { ("Seguir Windows", BrowserThemeMode.System), ("Claro", BrowserThemeMode.Light), ("Escuro", BrowserThemeMode.Dark) })
        {
            var button = SecondaryButton(item.Item1); button.Margin = new Thickness(0, 0, 7, 7);
            var mode = item.Item2; button.Click += (_, _) => { SetChromeTheme(mode); BuildSettingsView(); };
            themes.Children.Add(button);
        }
        HubContent.Children.Add(themes);

        HubContent.Children.Add(SectionTitle("Inicialização"));
        var restore = new CheckBox { Content = "Restaurar a última sessão ao abrir", IsChecked = _stateStore.RestoreLastSession, Margin = new Thickness(0, 9, 0, 16), Foreground = FindBrush("BrowserTextPrimaryBrush") };
        restore.Click += (_, _) => TryPersist(() => _stateStore.SetRestoreLastSession(restore.IsChecked == true));
        HubContent.Children.Add(restore);

        HubContent.Children.Add(SectionTitle("Perfil e privacidade"));
        var profile = ActiveProfile;
        if (profile is null) { HubContent.Children.Add(MutedText("Perfil WebView2 ainda não disponível.")); return; }
        try
        {
            var passwords = new CheckBox { Content = "Permitir salvamento de senhas", IsChecked = profile.IsPasswordAutosaveEnabled, Margin = new Thickness(0, 9, 0, 0), Foreground = FindBrush("BrowserTextPrimaryBrush") };
            passwords.Click += (_, _) => TryProfileSetting(() => profile.IsPasswordAutosaveEnabled = passwords.IsChecked == true);
            var autofill = new CheckBox { Content = "Permitir preenchimento automático", IsChecked = profile.IsGeneralAutofillEnabled, Margin = new Thickness(0, 9, 0, 14), Foreground = FindBrush("BrowserTextPrimaryBrush") };
            autofill.Click += (_, _) => TryProfileSetting(() => profile.IsGeneralAutofillEnabled = autofill.IsChecked == true);
            HubContent.Children.Add(passwords); HubContent.Children.Add(autofill);
            HubContent.Children.Add(MutedText($"Prevenção de rastreamento: {TrackingLabel(profile.PreferredTrackingPreventionLevel)}"));
            var tracking = new WrapPanel { Margin = new Thickness(0, 8, 0, 16) };
            foreach (var item in new[] { ("Básica", CoreWebView2TrackingPreventionLevel.Basic), ("Equilibrada", CoreWebView2TrackingPreventionLevel.Balanced), ("Estrita", CoreWebView2TrackingPreventionLevel.Strict) })
            {
                var b = SecondaryButton(item.Item1); b.Margin = new Thickness(0, 0, 7, 7); var level = item.Item2;
                b.Click += (_, _) => { TryProfileSetting(() => profile.PreferredTrackingPreventionLevel = level); BuildSettingsView(); };
                tracking.Children.Add(b);
            }
            HubContent.Children.Add(tracking);
        }
        catch (Exception error) when (error is InvalidOperationException or COMException) { HubContent.Children.Add(MutedText($"Configurações indisponíveis: {error.GetType().Name}.")); }

        HubContent.Children.Add(MutedText(_developerMode ? "Modo de desenvolvimento do Host: ativo." : "Modo de desenvolvimento do Host: desativado."));
        var clear = SecondaryButton("Limpar dados do navegador…"); clear.Margin = new Thickness(0, 12, 0, 0); clear.Click += async (_, _) => await ClearBrowserDataAsync(); HubContent.Children.Add(clear);
    }

    private void TryProfileSetting(Action action)
    {
        try { action(); }
        catch (Exception error) when (error is InvalidOperationException or COMException) { HubSubtitle.Text = $"Falha ao salvar configuração: {error.GetType().Name}."; }
    }

    private static string TrackingLabel(CoreWebView2TrackingPreventionLevel level) => level switch
    {
        CoreWebView2TrackingPreventionLevel.Basic => "básica",
        CoreWebView2TrackingPreventionLevel.Strict => "estrita",
        _ => "equilibrada"
    };

    private TextBlock SectionTitle(string text) => new() { Text = text, FontSize = 15, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 0), Foreground = FindBrush("BrowserTextPrimaryBrush") };
    private TextBlock MutedText(string text) => new() { Text = text, FontSize = 11, Margin = new Thickness(0, 5, 0, 6), TextWrapping = TextWrapping.Wrap, Foreground = FindBrush("BrowserTextMutedBrush") };
    private Button SecondaryButton(string text) => new() { Content = text, Style = (Style)FindResource("SecondaryButton") };
    private Border Card(UIElement child) => new() { Child = child, Padding = new Thickness(12), Margin = new Thickness(0, 6, 0, 0), CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(1), BorderBrush = FindBrush("BrowserBorderBrush"), Background = FindBrush("BrowserSurfaceBrush") };

    private sealed record DownloadUiSnapshot(BrowserDownloadStatus Status, DateTimeOffset UpdatedAt);
}
