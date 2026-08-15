using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
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
    private BrowserExtensionManager? _extensionManager;

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
        MenuDownloadsButton.IsEnabled = _webViewReady;
        MenuExtensionsButton.IsEnabled = ActiveProfile is not null;
        MenuSettingsButton.IsEnabled = _webViewReady;
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
    private async void ModernExtensions_Click(object sender, RoutedEventArgs e) => await ShowExtensionsHubAsync();
    private void MenuSettings_Click(object sender, RoutedEventArgs e) { CloseModernMenu(); ShowSettingsHub(); }
    private void MenuPrint_Click(object sender, RoutedEventArgs e) { CloseModernMenu(); TryUiAction(() => _activeTab?.Print()); }
    private async void MenuSave_Click(object sender, RoutedEventArgs e) { CloseModernMenu(); await SaveActivePageAsync(); }
    private async void MenuClearData_Click(object sender, RoutedEventArgs e) { CloseModernMenu(); await ClearBrowserDataAsync(); }

    private void ShowHub(string kind, string title, string subtitle, string glyph)
    {
        _activeHub = kind;
        BrowserMenuPopup.IsOpen = false;
        LibraryPanel.Visibility = Visibility.Collapsed;
        HubGlyph.Text = glyph;
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
        ShowHub(
            "downloads",
            "Downloads",
            "Acompanhe arquivos iniciados nesta sessão do CloudOS Browser.",
            "↓");
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
        HubSubtitle.Text = items.Count == 0
            ? "Nenhum download nesta sessão."
            : $"{items.Count} download(s) nesta sessão.";

        if (items.Count == 0)
        {
            var empty = EmptyState(
                "Downloads aparecem aqui",
                "Ao iniciar um download, o Browser pede um destino local e mostra progresso, conclusão ou interrupção neste painel.",
                "DownloadsEmptyState");
            HubContent.Children.Add(empty);
            return;
        }

        foreach (var item in items)
        {
            var status = item.Status;
            var progress = status.TotalBytes is > 0
                ? Math.Clamp(status.BytesReceived * 100d / status.TotalBytes.Value, 0d, 100d)
                : status.State.Equals("Completed", StringComparison.OrdinalIgnoreCase) ? 100d : 0d;
            var detail = status.TotalBytes is > 0
                ? $"{DownloadStateLabel(status.State)} · {FormatBytes(status.BytesReceived)} de {FormatBytes(status.TotalBytes.Value)}"
                : $"{DownloadStateLabel(status.State)} · {FormatBytes(status.BytesReceived)}";
            if (!string.IsNullOrWhiteSpace(status.InterruptReason))
                detail += " · " + SanitizeUiValue(status.InterruptReason, 48);

            var stack = new StackPanel();
            var title = new TextBlock
            {
                Text = status.FileName,
                FontSize = 13,
                FontWeight = FontWeights.SemiBold,
                TextTrimming = TextTrimming.CharacterEllipsis
            };
            stack.Children.Add(title);
            stack.Children.Add(MutedText(detail));
            var progressBar = new ProgressBar
            {
                Height = 5,
                Margin = new Thickness(0, 9, 0, 0),
                Minimum = 0,
                Maximum = 100,
                Value = progress
            };
            progressBar.SetResourceReference(Control.ForegroundProperty, "BrowserAccentBrush");
            stack.Children.Add(progressBar);
            HubContent.Children.Add(Card(stack));
        }

        if (_downloads.HasActiveDownloads)
        {
            var cancel = SecondaryButton("Cancelar downloads ativos");
            cancel.Margin = new Thickness(0, 10, 0, 0);
            cancel.Click += CancelDownloads_Click;
            HubContent.Children.Add(cancel);
        }
    }

    private static string DownloadStateLabel(string state) => state switch
    {
        "InProgress" => "Em andamento",
        "Completed" => "Concluído",
        "Interrupted" => "Interrompido",
        "CancelFailed" => "Cancelamento falhou",
        "Unavailable" => "Estado indisponível",
        _ => SanitizeUiValue(state, 32)
    };

    private static string FormatBytes(long value)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        var size = Math.Max(0, (double)value);
        var index = 0;
        while (size >= 1024 && index < units.Length - 1) { size /= 1024; index++; }
        return $"{size:0.#} {units[index]}";
    }

    private CoreWebView2Profile? ActiveProfile => _activeTab?.View.CoreWebView2?.Profile;

    private BrowserExtensionManager GetExtensionManager()
    {
        if (_extensionManager is not null) return _extensionManager;
        var userDataFolder = _environment?.UserDataFolder;
        if (string.IsNullOrWhiteSpace(userDataFolder))
            throw new BrowserExtensionPackageException("EXTENSION_PROFILE_NOT_READY");
        _extensionManager = new BrowserExtensionManager(userDataFolder);
        return _extensionManager;
    }

    private async Task ShowExtensionsHubAsync()
    {
        ShowHub(
            "extensions",
            "Extensões",
            "Gerencie extensões WebView2 locais e descompactadas no perfil isolado do Browser.",
            "◇");
        await RefreshExtensionsViewAsync();
    }

    private async Task RefreshExtensionsViewAsync()
    {
        HubContent.Children.Clear();

        var intro = new StackPanel();
        intro.Children.Add(new TextBlock
        {
            Text = "Extensões locais",
            FontSize = 15,
            FontWeight = FontWeights.SemiBold
        });
        intro.Children.Add(MutedText(
            "O CloudOS Browser aceita pacotes locais descompactados com manifest.json. " +
            "Esta área não promete compatibilidade universal com extensões da Chrome Web Store."));
        HubContent.Children.Add(Card(intro));

        var install = SecondaryButton("Carregar extensão local…");
        install.Name = "ExtensionLoadButton";
        install.Margin = new Thickness(0, 10, 0, 4);
        AutomationProperties.SetName(install, "Carregar extensão local");
        install.Click += InstallExtension_Click;
        HubContent.Children.Add(install);

        var profile = ActiveProfile;
        if (profile is null)
        {
            HubSubtitle.Text = "O perfil WebView2 ainda não está pronto.";
            HubContent.Children.Add(EmptyState(
                "Perfil ainda inicializando",
                "Abra esta área novamente depois que a primeira aba estiver pronta.",
                "ExtensionsProfileUnavailable"));
            return;
        }

        try
        {
            var extensions = await profile.GetBrowserExtensionsAsync();
            var manager = GetExtensionManager();
            manager.ReconcileManagedPackages(extensions.Select(extension => extension.Id));

            HubSubtitle.Text = extensions.Count == 0
                ? "Nenhuma extensão local carregada."
                : $"{extensions.Count} extensão(ões) disponível(is) neste perfil.";

            if (extensions.Count == 0)
            {
                HubContent.Children.Add(EmptyState(
                    "Nenhuma extensão carregada",
                    "Use “Carregar extensão local…” e selecione uma pasta descompactada válida.",
                    "ExtensionsEmptyState"));
                return;
            }

            foreach (var extension in extensions.OrderBy(x => x.Name, StringComparer.CurrentCultureIgnoreCase))
            {
                var stack = new StackPanel();
                stack.Children.Add(new TextBlock
                {
                    Text = SanitizeUiValue(extension.Name, 80),
                    FontSize = 13,
                    FontWeight = FontWeights.SemiBold,
                    TextTrimming = TextTrimming.CharacterEllipsis
                });

                var state = extension.IsEnabled ? "Ativa" : "Desativada";
                var stateText = MutedText(state);
                stateText.SetResourceReference(
                    TextBlock.ForegroundProperty,
                    extension.IsEnabled ? "BrowserSuccessBrush" : "BrowserTextMutedBrush");
                stack.Children.Add(stateText);

                var actions = new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    Margin = new Thickness(0, 8, 0, 0)
                };
                var toggle = SecondaryButton(extension.IsEnabled ? "Desativar" : "Ativar");
                toggle.Tag = extension.Id;
                toggle.Click += ToggleExtension_Click;
                var remove = SecondaryButton("Remover");
                remove.Tag = extension.Id;
                remove.Margin = new Thickness(8, 0, 0, 0);
                remove.Click += RemoveExtension_Click;
                actions.Children.Add(toggle);
                actions.Children.Add(remove);
                stack.Children.Add(actions);
                HubContent.Children.Add(Card(stack));
            }
        }
        catch (BrowserExtensionPackageException error)
        {
            ShowExtensionError(error.Code);
        }
        catch (Exception error) when (error is InvalidOperationException or COMException or NotSupportedException)
        {
            ShowExtensionError("EXTENSION_WEBVIEW_UNAVAILABLE");
        }
    }

    private async void InstallExtension_Click(object sender, RoutedEventArgs e)
    {
        var profile = ActiveProfile;
        if (profile is null)
        {
            ShowExtensionError("EXTENSION_PROFILE_NOT_READY");
            return;
        }

        var dialog = new OpenFolderDialog
        {
            Title = "Selecionar extensão WebView2 local descompactada",
            Multiselect = false
        };
        if (dialog.ShowDialog(this) != true) return;

        try
        {
            var package = BrowserExtensionManager.ValidatePackage(dialog.FolderName);
            HubSubtitle.Text = $"Validando {SanitizeUiValue(package.Name, 60)} {SanitizeUiValue(package.Version, 24)}…";
            var manager = GetExtensionManager();
            await manager.InstallAsync(profile, dialog.FolderName);
            await RefreshExtensionsViewAsync();
        }
        catch (BrowserExtensionPackageException error)
        {
            ShowExtensionError(error.Code);
        }
        catch (OperationCanceledException)
        {
            ShowExtensionError("EXTENSION_OPERATION_CANCELLED");
        }
    }

    private async void ToggleExtension_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string id }) return;
        var extension = await FindExtensionAsync(id);
        if (extension is null) return;
        try
        {
            await extension.EnableAsync(!extension.IsEnabled);
            await RefreshExtensionsViewAsync();
        }
        catch (Exception error) when (error is InvalidOperationException or COMException)
        {
            ShowExtensionError("EXTENSION_WEBVIEW_TOGGLE_FAILED");
        }
    }

    private async void RemoveExtension_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string id }) return;
        var extension = await FindExtensionAsync(id);
        if (extension is null) return;

        var displayName = SanitizeUiValue(extension.Name, 60);
        if (MessageBox.Show(
                this,
                $"Remover “{displayName}” deste perfil?",
                "Extensões",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) != MessageBoxResult.Yes)
            return;

        try
        {
            await GetExtensionManager().RemoveAsync(extension);
            await RefreshExtensionsViewAsync();
        }
        catch (BrowserExtensionPackageException error)
        {
            ShowExtensionError(error.Code);
        }
    }

    private async Task<CoreWebView2BrowserExtension?> FindExtensionAsync(string id)
    {
        try
        {
            return ActiveProfile is { } profile
                ? (await profile.GetBrowserExtensionsAsync()).FirstOrDefault(x => x.Id.Equals(id, StringComparison.Ordinal))
                : null;
        }
        catch (Exception error) when (error is InvalidOperationException or COMException)
        {
            ShowExtensionError("EXTENSION_WEBVIEW_QUERY_FAILED");
            return null;
        }
    }

    private void ShowExtensionError(string code)
    {
        HubSubtitle.Text = code switch
        {
            "EXTENSION_PATH_EMPTY" or "EXTENSION_PATH_INVALID" or "EXTENSION_DIRECTORY_NOT_FOUND" =>
                "A pasta selecionada não é um diretório local válido.",
            "EXTENSION_MANIFEST_MISSING" =>
                "A pasta selecionada precisa conter manifest.json na raiz.",
            "EXTENSION_MANIFEST_SIZE_INVALID" or "EXTENSION_MANIFEST_UNREADABLE" or
            "EXTENSION_MANIFEST_INVALID" or "EXTENSION_MANIFEST_NAME_INVALID" or
            "EXTENSION_MANIFEST_VERSION_INVALID" =>
                "O manifest.json não pôde ser validado.",
            "EXTENSION_MANIFEST_VERSION_UNSUPPORTED" =>
                "O manifest_version deste pacote não é aceito pelo carregador local.",
            "EXTENSION_REPARSE_POINT_BLOCKED" or "EXTENSION_PATH_ESCAPE" =>
                "O pacote contém redirecionamento de caminho não permitido.",
            "EXTENSION_TOO_MANY_FILES" or "EXTENSION_PACKAGE_TOO_LARGE" =>
                "O pacote excede os limites locais do CloudOS Browser.",
            "EXTENSION_PACKAGE_EMPTY" or "EXTENSION_TREE_UNREADABLE" =>
                "O conteúdo da extensão não pôde ser lido com segurança.",
            "EXTENSION_SOURCE_ALREADY_MANAGED" =>
                "Escolha a pasta original da extensão, não a cópia gerenciada pelo Browser.",
            "EXTENSION_PROFILE_NOT_READY" =>
                "O perfil WebView2 ainda não está pronto.",
            "EXTENSION_WEBVIEW_INSTALL_FAILED" =>
                "O WebView2 recusou a instalação deste pacote local.",
            "EXTENSION_WEBVIEW_REMOVE_FAILED" =>
                "O WebView2 não conseguiu remover a extensão.",
            "EXTENSION_WEBVIEW_TOGGLE_FAILED" =>
                "O WebView2 não conseguiu alterar o estado da extensão.",
            "EXTENSION_WEBVIEW_QUERY_FAILED" or "EXTENSION_WEBVIEW_UNAVAILABLE" =>
                "A API de extensões WebView2 não está disponível neste contexto.",
            "EXTENSION_STATE_WRITE_FAILED" or "EXTENSION_MANAGED_COPY_FAILED" =>
                "O pacote não pôde ser armazenado no diretório isolado do Browser.",
            "EXTENSION_OPERATION_CANCELLED" =>
                "A operação de extensão foi cancelada.",
            _ => "A operação de extensão não pôde ser concluída."
        };
    }

    private void ShowSettingsHub()
    {
        ShowHub(
            "settings",
            "Configurações",
            "Preferências do Browser e do perfil WebView2 isolado.",
            "⚙");
        BuildSettingsView();
    }

    private void BuildSettingsView()
    {
        HubContent.Children.Clear();
        HubContent.Children.Add(SectionTitle("Aparência"));
        var themes = new WrapPanel { Margin = new Thickness(0, 8, 0, 16) };
        foreach (var item in new[]
        {
            ("Seguir Windows", BrowserThemeMode.System),
            ("Claro", BrowserThemeMode.Light),
            ("Escuro", BrowserThemeMode.Dark)
        })
        {
            var button = SecondaryButton(item.Item1);
            button.Margin = new Thickness(0, 0, 7, 7);
            var mode = item.Item2;
            button.Click += (_, _) => { SetChromeTheme(mode); BuildSettingsView(); };
            themes.Children.Add(button);
        }
        HubContent.Children.Add(themes);

        HubContent.Children.Add(SectionTitle("Inicialização"));
        var restore = new CheckBox
        {
            Content = "Restaurar a última sessão ao abrir",
            IsChecked = _stateStore.RestoreLastSession,
            Margin = new Thickness(0, 9, 0, 16),
            Foreground = FindBrush("BrowserTextPrimaryBrush")
        };
        restore.Click += (_, _) => TryPersist(() => _stateStore.SetRestoreLastSession(restore.IsChecked == true));
        HubContent.Children.Add(restore);

        HubContent.Children.Add(SectionTitle("Perfil e privacidade"));
        var profile = ActiveProfile;
        if (profile is null)
        {
            HubContent.Children.Add(MutedText("Perfil WebView2 ainda não disponível."));
            return;
        }

        try
        {
            var passwords = new CheckBox
            {
                Content = "Permitir salvamento de senhas",
                IsChecked = profile.IsPasswordAutosaveEnabled,
                Margin = new Thickness(0, 9, 0, 0),
                Foreground = FindBrush("BrowserTextPrimaryBrush")
            };
            passwords.Click += (_, _) => TryProfileSetting(() => profile.IsPasswordAutosaveEnabled = passwords.IsChecked == true);
            var autofill = new CheckBox
            {
                Content = "Permitir preenchimento automático",
                IsChecked = profile.IsGeneralAutofillEnabled,
                Margin = new Thickness(0, 9, 0, 14),
                Foreground = FindBrush("BrowserTextPrimaryBrush")
            };
            autofill.Click += (_, _) => TryProfileSetting(() => profile.IsGeneralAutofillEnabled = autofill.IsChecked == true);
            HubContent.Children.Add(passwords);
            HubContent.Children.Add(autofill);
            HubContent.Children.Add(MutedText($"Prevenção de rastreamento: {TrackingLabel(profile.PreferredTrackingPreventionLevel)}"));

            var tracking = new WrapPanel { Margin = new Thickness(0, 8, 0, 16) };
            foreach (var item in new[]
            {
                ("Básica", CoreWebView2TrackingPreventionLevel.Basic),
                ("Equilibrada", CoreWebView2TrackingPreventionLevel.Balanced),
                ("Estrita", CoreWebView2TrackingPreventionLevel.Strict)
            })
            {
                var button = SecondaryButton(item.Item1);
                button.Margin = new Thickness(0, 0, 7, 7);
                var level = item.Item2;
                button.Click += (_, _) =>
                {
                    TryProfileSetting(() => profile.PreferredTrackingPreventionLevel = level);
                    BuildSettingsView();
                };
                tracking.Children.Add(button);
            }
            HubContent.Children.Add(tracking);
        }
        catch (Exception error) when (error is InvalidOperationException or COMException)
        {
            HubContent.Children.Add(MutedText("Configurações do perfil temporariamente indisponíveis."));
        }

        HubContent.Children.Add(MutedText(
            _developerMode ? "Modo de desenvolvimento do Host: ativo." : "Modo de desenvolvimento do Host: desativado."));
        var clear = SecondaryButton("Limpar dados do navegador…");
        clear.Margin = new Thickness(0, 12, 0, 0);
        clear.Click += async (_, _) => await ClearBrowserDataAsync();
        HubContent.Children.Add(clear);
    }

    private void TryProfileSetting(Action action)
    {
        try { action(); }
        catch (Exception error) when (error is InvalidOperationException or COMException)
        {
            HubSubtitle.Text = "A configuração do perfil não pôde ser salva.";
        }
    }

    private static string TrackingLabel(CoreWebView2TrackingPreventionLevel level) => level switch
    {
        CoreWebView2TrackingPreventionLevel.Basic => "básica",
        CoreWebView2TrackingPreventionLevel.Strict => "estrita",
        _ => "equilibrada"
    };

    private TextBlock SectionTitle(string text) => new()
    {
        Text = text,
        FontSize = 15,
        FontWeight = FontWeights.SemiBold,
        Margin = new Thickness(0, 8, 0, 0),
        Foreground = FindBrush("BrowserTextPrimaryBrush")
    };

    private TextBlock MutedText(string text) => new()
    {
        Text = text,
        FontSize = 11,
        Margin = new Thickness(0, 5, 0, 6),
        TextWrapping = TextWrapping.Wrap,
        Foreground = FindBrush("BrowserTextMutedBrush")
    };

    private Button SecondaryButton(string text) => new()
    {
        Content = text,
        Style = (Style)FindResource("SecondaryButton")
    };

    private Border Card(UIElement child) => new()
    {
        Child = child,
        Padding = new Thickness(13),
        Margin = new Thickness(0, 7, 0, 0),
        CornerRadius = new CornerRadius(10),
        BorderThickness = new Thickness(1),
        BorderBrush = FindBrush("BrowserBorderBrush"),
        Background = FindBrush("BrowserSurfaceBrush")
    };

    private Border EmptyState(string title, string detail, string name)
    {
        var stack = new StackPanel();
        stack.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 14,
            FontWeight = FontWeights.SemiBold
        });
        stack.Children.Add(MutedText(detail));
        var card = Card(stack);
        card.Name = name;
        AutomationProperties.SetName(card, title);
        return card;
    }

    private static string SanitizeUiValue(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value)) return string.Empty;
        var clean = new string(value.Where(ch => !char.IsControl(ch)).ToArray()).Trim();
        return clean.Length <= maxLength ? clean : clean[..maxLength] + "…";
    }

    private sealed record DownloadUiSnapshot(BrowserDownloadStatus Status, DateTimeOffset UpdatedAt);
}
