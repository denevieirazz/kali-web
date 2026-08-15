using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;

namespace CloudOS.Host.Browser;

internal static class BrowserSideHubCompositionBootstrap
{
    [ModuleInitializer]
    internal static void Register()
    {
        EventManager.RegisterClassHandler(
            typeof(Button),
            Button.ClickEvent,
            new RoutedEventHandler(OnButtonClick),
            handledEventsToo: true);
    }

    private static void OnButtonClick(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || Window.GetWindow(button) is not BrowserWindow window)
            return;
        window.RouteCorrectedSideHubClick(button, e);
    }
}

public partial class BrowserWindow
{
    private void RouteCorrectedSideHubClick(Button button, RoutedEventArgs e)
    {
        switch (button.Name)
        {
            case "DownloadsButton":
            case "MenuDownloadsButton":
                e.Handled = true;
                OpenDownloadsHubPreservingActiveSurface();
                break;
            case "ExtensionsButton":
            case "MenuExtensionsButton":
                e.Handled = true;
                _ = OpenExtensionsHubPreservingActiveSurfaceAsync();
                break;
            case "MenuSettingsButton":
                e.Handled = true;
                OpenSettingsHubPreservingActiveSurface();
                break;
        }
    }

    private void OpenDownloadsHubPreservingActiveSurface()
    {
        OpenSideHubPreservingActiveSurface(
            "downloads",
            "Downloads",
            "Acompanhe arquivos iniciados nesta sessão do CloudOS Browser.",
            "↓");
        RefreshDownloadsView();
        QueueHubVisualNormalization();
    }

    private async Task OpenExtensionsHubPreservingActiveSurfaceAsync()
    {
        OpenSideHubPreservingActiveSurface(
            "extensions",
            "Extensões",
            "Gerencie extensões WebView2 locais e descompactadas no perfil isolado do Browser.",
            "◇");
        await RefreshExtensionsViewAsync();
        QueueHubVisualNormalization();
    }

    private void OpenSettingsHubPreservingActiveSurface()
    {
        OpenSideHubPreservingActiveSurface(
            "settings",
            "Configurações",
            "Preferências do Browser e do perfil WebView2 isolado.",
            "⚙");
        BuildSettingsView();
        QueueHubVisualNormalization();
    }

    private void OpenSideHubPreservingActiveSurface(string kind, string title, string subtitle, string glyph)
    {
        _activeHub = kind;
        BrowserMenuPopup.IsOpen = false;
        LibraryPanel.Visibility = Visibility.Collapsed;
        HubGlyph.Text = glyph;
        HubTitle.Text = title;
        HubSubtitle.Text = subtitle;
        HubContent.Children.Clear();

        // Side hubs are a physical second column. Never collapse a healthy active WebView2
        // merely to open the hub: hiding its child HWND forces an unnecessary compositor
        // detach/reattach exactly while the grid is being resized.
        WebViewHost.Visibility = Visibility.Visible;
        if (_activeTab is { IsNewTabPage: true })
        {
            _activeTab.View.Visibility = Visibility.Collapsed;
            ErrorPanel.Visibility = Visibility.Collapsed;
            NewTabPanel.Visibility = Visibility.Visible;
        }
        else if (_activeTab?.Error is not null)
        {
            _activeTab.View.Visibility = Visibility.Collapsed;
            NewTabPanel.Visibility = Visibility.Collapsed;
            ErrorPanel.Visibility = Visibility.Visible;
        }
        else
        {
            NewTabPanel.Visibility = Visibility.Collapsed;
            ErrorPanel.Visibility = Visibility.Collapsed;
            if (_activeTab is not null)
                _activeTab.View.Visibility = Visibility.Visible;
        }

        HubPanel.Visibility = Visibility.Visible;
        UpdateHubComposition();
        WebViewHost.InvalidateMeasure();
        WebViewHost.InvalidateArrange();
        _activeTab?.View.InvalidateMeasure();
        _activeTab?.View.InvalidateArrange();
    }
}
