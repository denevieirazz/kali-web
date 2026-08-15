using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Host.Browser;

internal static class BrowserSurfaceCoordinatorBootstrap
{
    [ModuleInitializer]
    internal static void Register()
    {
        EventManager.RegisterClassHandler(
            typeof(BrowserWindow),
            FrameworkElement.LoadedEvent,
            new RoutedEventHandler(OnBrowserLoaded),
            handledEventsToo: true);
    }

    private static void OnBrowserLoaded(object sender, RoutedEventArgs e)
    {
        if (sender is not BrowserWindow window) return;
        _ = window.Dispatcher.BeginInvoke(
            DispatcherPriority.ApplicationIdle,
            new Action(window.InitializeCorrectedBrowserSurfaces));
    }
}

public partial class BrowserWindow
{
    private const double MenuEdgeInset = 8d;
    private const double MenuGap = 4d;
    private const string OwnershipMarker = "CloudOS.Browser.ExtensionOwnership.v1";

    private bool _correctedSurfacesInitialized;
    private bool _menuPlaceAbove;
    private bool _ownershipRefreshQueued;
    private Grid? _surfaceContentGrid;
    private ColumnDefinition? _surfaceHubColumn;
    private FrameworkElement? _menuSurface;
    private ScrollViewer? _menuScroll;

    internal void InitializeCorrectedBrowserSurfaces()
    {
        if (_correctedSurfacesInitialized || _closing) return;
        _correctedSurfacesInitialized = true;

        ConfigureHubComposition();
        ConfigureMenuPlacement();
        HarmonizeHubChrome();

        HubPanel.IsVisibleChanged += CorrectedHubPanel_IsVisibleChanged;
        HubContent.LayoutUpdated += CorrectedHubContent_LayoutUpdated;
        SizeChanged += CorrectedSurfaces_SizeChanged;
        Closed += CorrectedSurfaces_Closed;

        UpdateHubComposition();
        UpdateMenuGeometry();
    }

    private void CorrectedSurfaces_Closed(object? sender, EventArgs e)
    {
        HubPanel.IsVisibleChanged -= CorrectedHubPanel_IsVisibleChanged;
        HubContent.LayoutUpdated -= CorrectedHubContent_LayoutUpdated;
        SizeChanged -= CorrectedSurfaces_SizeChanged;
        Closed -= CorrectedSurfaces_Closed;
        if (_menuSurface is not null)
        {
            _menuSurface.PreviewKeyDown -= BrowserMenuSurface_PreviewKeyDown;
            _menuSurface.RemoveHandler(
                Keyboard.GotKeyboardFocusEvent,
                new KeyboardFocusChangedEventHandler(BrowserMenuSurface_GotKeyboardFocus));
        }
        BrowserMenuPopup.Opened -= BrowserMenuPopup_CorrectedOpened;
    }

    private void ConfigureHubComposition()
    {
        _surfaceContentGrid = HubPanel.Parent as Grid;
        if (_surfaceContentGrid is null || !ReferenceEquals(WebViewHost.Parent, _surfaceContentGrid))
            return;

        if (_surfaceContentGrid.ColumnDefinitions.Count == 0)
        {
            _surfaceContentGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            _surfaceContentGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0) });
        }
        else if (_surfaceContentGrid.ColumnDefinitions.Count == 1)
        {
            _surfaceContentGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0) });
        }

        _surfaceHubColumn = _surfaceContentGrid.ColumnDefinitions[1];
        foreach (UIElement child in _surfaceContentGrid.Children)
        {
            Grid.SetColumn(child, ReferenceEquals(child, HubPanel) ? 1 : 0);
            Grid.SetColumnSpan(child, 1);
        }

        HubPanel.Width = double.NaN;
        HubPanel.HorizontalAlignment = HorizontalAlignment.Stretch;
        WebViewHost.SetResourceReference(Panel.BackgroundProperty, "BrowserWindowBrush");
    }

    private void ConfigureMenuPlacement()
    {
        BrowserMenuPopup.Placement = PlacementMode.Custom;
        BrowserMenuPopup.CustomPopupPlacementCallback = PlaceBrowserMenuInsideWindow;
        BrowserMenuPopup.Opened += BrowserMenuPopup_CorrectedOpened;

        _menuSurface = BrowserMenuPopup.Child as FrameworkElement;
        _menuScroll = _menuSurface is null ? null : SurfaceDescendants<ScrollViewer>(_menuSurface).FirstOrDefault();
        if (_menuSurface is null) return;

        if (_menuSurface is Border border)
        {
            border.Margin = new Thickness(0);
            border.SnapsToDevicePixels = true;
        }

        KeyboardNavigation.SetTabNavigation(_menuSurface, KeyboardNavigationMode.Cycle);
        KeyboardNavigation.SetDirectionalNavigation(_menuSurface, KeyboardNavigationMode.Contained);
        _menuSurface.PreviewKeyDown += BrowserMenuSurface_PreviewKeyDown;
        _menuSurface.AddHandler(
            Keyboard.GotKeyboardFocusEvent,
            new KeyboardFocusChangedEventHandler(BrowserMenuSurface_GotKeyboardFocus),
            handledEventsToo: true);
    }

    private void HarmonizeHubChrome()
    {
        HubPanel.SetResourceReference(Border.BackgroundProperty, "BrowserChromeBrush");
        HubPanel.SetResourceReference(Border.BorderBrushProperty, "BrowserBorderBrush");
        HubPanel.SnapsToDevicePixels = true;
        HubGlyph.SetResourceReference(TextBlock.ForegroundProperty, "BrowserAccentBrush");
        HubTitle.SetResourceReference(TextBlock.ForegroundProperty, "BrowserTextPrimaryBrush");
        HubSubtitle.SetResourceReference(TextBlock.ForegroundProperty, "BrowserTextMutedBrush");

        var scroll = SurfaceDescendants<ScrollViewer>(HubPanel).FirstOrDefault();
        if (scroll is not null)
        {
            scroll.SetResourceReference(Control.BackgroundProperty, "BrowserWindowBrush");
            scroll.HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled;
            scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            scroll.PanningMode = PanningMode.VerticalOnly;
        }
    }

    private void CorrectedSurfaces_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (!_correctedSurfacesInitialized) return;
        UpdateHubComposition();
        UpdateMenuGeometry();
        if (BrowserMenuPopup.IsOpen)
        {
            var offset = BrowserMenuPopup.HorizontalOffset;
            BrowserMenuPopup.HorizontalOffset = offset + 0.01;
            BrowserMenuPopup.HorizontalOffset = offset;
        }
    }

    private void CorrectedHubPanel_IsVisibleChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        UpdateHubComposition();
        if (HubPanel.Visibility == Visibility.Visible)
        {
            RestoreDeliberateContentSurfaceBesideHub();
            QueueHubVisualNormalization();
        }
    }

    private void UpdateHubComposition()
    {
        if (_surfaceHubColumn is null) return;
        HubPanel.Width = double.NaN;
        if (HubPanel.Visibility != Visibility.Visible)
        {
            _surfaceHubColumn.Width = new GridLength(0);
            return;
        }

        var width = ActualWidth > 0 ? ActualWidth : Width;
        var maximumByContent = Math.Max(340d, width - 360d);
        var desired = Math.Clamp(width * 0.36d, 340d, 500d);
        desired = Math.Min(desired, maximumByContent);
        _surfaceHubColumn.Width = new GridLength(desired);
    }

    private void RestoreDeliberateContentSurfaceBesideHub()
    {
        WebViewHost.Visibility = Visibility.Visible;
        if (_activeTab is null) return;

        if (_activeTab.IsNewTabPage)
        {
            _activeTab.View.Visibility = Visibility.Collapsed;
            ErrorPanel.Visibility = Visibility.Collapsed;
            NewTabPanel.Visibility = Visibility.Visible;
            return;
        }

        if (_activeTab.Error is not null)
        {
            _activeTab.View.Visibility = Visibility.Collapsed;
            NewTabPanel.Visibility = Visibility.Collapsed;
            ErrorPanel.Visibility = Visibility.Visible;
            return;
        }

        NewTabPanel.Visibility = Visibility.Collapsed;
        ErrorPanel.Visibility = Visibility.Collapsed;
        _activeTab.View.Visibility = Visibility.Visible;
    }

    private void UpdateMenuGeometry()
    {
        if (_menuSurface is null || !BrowserMenuButton.IsLoaded) return;
        UpdateLayout();

        var targetOrigin = BrowserMenuButton.TranslatePoint(new Point(0, 0), this);
        var targetBottom = targetOrigin.Y + BrowserMenuButton.ActualHeight;
        var availableBelow = Math.Max(0d, ActualHeight - targetBottom - MenuEdgeInset - MenuGap);
        var availableAbove = Math.Max(0d, targetOrigin.Y - MenuEdgeInset - MenuGap);
        _menuPlaceAbove = availableBelow < 220d && availableAbove > availableBelow;
        var available = _menuPlaceAbove ? availableAbove : availableBelow;
        available = Math.Max(160d, available);

        _menuSurface.MaxHeight = available;
        if (_menuScroll is not null)
        {
            var chrome = _menuSurface is Border border
                ? border.Padding.Top + border.Padding.Bottom + border.BorderThickness.Top + border.BorderThickness.Bottom
                : 0d;
            _menuScroll.MaxHeight = Math.Max(120d, available - chrome);
            _menuScroll.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        }
    }

    private CustomPopupPlacement[] PlaceBrowserMenuInsideWindow(Size popupSize, Size targetSize, Point offset)
    {
        var targetOrigin = BrowserMenuButton.TranslatePoint(new Point(0, 0), this);
        var minX = MenuEdgeInset - targetOrigin.X;
        var maxX = ActualWidth - MenuEdgeInset - targetOrigin.X - popupSize.Width;
        var fitsToRight = targetOrigin.X + popupSize.Width <= ActualWidth - MenuEdgeInset;
        var desiredX = fitsToRight ? 0d : targetSize.Width - popupSize.Width;
        desiredX = Math.Clamp(desiredX, Math.Min(minX, maxX), Math.Max(minX, maxX));

        var desiredY = _menuPlaceAbove
            ? -popupSize.Height - MenuGap
            : targetSize.Height + MenuGap;
        var minY = MenuEdgeInset - targetOrigin.Y;
        var maxY = ActualHeight - MenuEdgeInset - targetOrigin.Y - popupSize.Height;
        desiredY = Math.Clamp(desiredY, Math.Min(minY, maxY), Math.Max(minY, maxY));

        return [new CustomPopupPlacement(new Point(desiredX, desiredY), PopupPrimaryAxis.Horizontal)];
    }

    private void BrowserMenuPopup_CorrectedOpened(object? sender, EventArgs e)
    {
        UpdateMenuGeometry();
        _ = Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() =>
        {
            var first = MenuFocusableButtons().FirstOrDefault();
            if (first is null) return;
            first.Focus();
            first.BringIntoView();
        }));
    }

    private void BrowserMenuSurface_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            BrowserMenuPopup.IsOpen = false;
            BrowserMenuButton.Focus();
            e.Handled = true;
            return;
        }

        if (e.Key is not (Key.Down or Key.Up or Key.Home or Key.End)) return;
        var buttons = MenuFocusableButtons();
        if (buttons.Count == 0) return;

        var focused = Keyboard.FocusedElement as Button;
        var index = focused is null ? -1 : buttons.IndexOf(focused);
        index = e.Key switch
        {
            Key.Home => 0,
            Key.End => buttons.Count - 1,
            Key.Up when index <= 0 => buttons.Count - 1,
            Key.Up => index - 1,
            Key.Down when index < 0 || index >= buttons.Count - 1 => 0,
            _ => index + 1
        };

        buttons[index].Focus();
        buttons[index].BringIntoView();
        e.Handled = true;
    }

    private void BrowserMenuSurface_GotKeyboardFocus(object sender, KeyboardFocusChangedEventArgs e)
    {
        if (e.NewFocus is FrameworkElement element && _menuSurface is not null && IsVisualDescendant(_menuSurface, element))
            element.BringIntoView();
    }

    private List<Button> MenuFocusableButtons() => _menuSurface is null
        ? []
        : SurfaceDescendants<Button>(_menuSurface)
            .Where(button => button.IsVisible && button.IsEnabled && button.Focusable)
            .ToList();

    private void CorrectedHubContent_LayoutUpdated(object? sender, EventArgs e)
    {
        if (HubPanel.Visibility != Visibility.Visible) return;
        QueueHubVisualNormalization();
    }

    private void QueueHubVisualNormalization()
    {
        if (_ownershipRefreshQueued) return;
        _ownershipRefreshQueued = true;
        _ = Dispatcher.BeginInvoke(DispatcherPriority.ContextIdle, new Action(() =>
        {
            _ownershipRefreshQueued = false;
            if (HubPanel.Visibility != Visibility.Visible) return;
            HarmonizeHubChrome();
            if (string.Equals(_activeHub, "extensions", StringComparison.Ordinal))
                NormalizeExtensionOwnershipUi();
            else if (string.Equals(_activeHub, "settings", StringComparison.Ordinal))
                NormalizeSettingsSelectionUi();
        }));
    }

    private void NormalizeExtensionOwnershipUi()
    {
        var manager = _extensionManager;
        if (manager is null) return;

        var taggedButtons = SurfaceDescendants<Button>(HubContent)
            .Where(button => button.Tag is string)
            .ToList();
        foreach (var group in taggedButtons.GroupBy(button => (string)button.Tag!, StringComparer.Ordinal))
        {
            var id = group.Key;
            var managed = manager.IsManagedExtension(id);
            var actionPanel = group.Select(button => button.Parent as Panel).FirstOrDefault(panel => panel is not null);
            if (actionPanel is null) continue;

            foreach (var remove in group.Where(button => string.Equals(button.Content as string, "Remover", StringComparison.Ordinal)).ToArray())
            {
                if (!managed && remove.Parent is Panel parent)
                    parent.Children.Remove(remove);
            }

            if (actionPanel.Parent is not StackPanel cardContent) continue;
            var marker = cardContent.Children
                .OfType<TextBlock>()
                .FirstOrDefault(text => string.Equals(text.Tag as string, OwnershipMarker, StringComparison.Ordinal));
            if (marker is null)
            {
                marker = new TextBlock
                {
                    Tag = OwnershipMarker,
                    FontSize = 10,
                    Margin = new Thickness(0, 5, 0, 1),
                    TextWrapping = TextWrapping.Wrap
                };
                var actionIndex = cardContent.Children.IndexOf(actionPanel);
                cardContent.Children.Insert(Math.Max(0, actionIndex), marker);
            }

            marker.Text = managed
                ? "Instalada pelo CloudOS · pacote local gerenciado"
                : "Componente do perfil WebView2 · não gerenciado pelo CloudOS";
            marker.SetResourceReference(
                TextBlock.ForegroundProperty,
                managed ? "BrowserSuccessBrush" : "BrowserTextMutedBrush");
            AutomationProperties.SetHelpText(marker, managed
                ? "Esta extensão pode ser removida porque pertence ao armazenamento gerenciado do CloudOS Browser."
                : "Este componente não pode ser removido pelo CloudOS Browser.");
        }
    }

    private void NormalizeSettingsSelectionUi()
    {
        foreach (var button in SurfaceDescendants<Button>(HubContent))
        {
            if (button.Content is not string label) continue;
            var selected = label switch
            {
                "Seguir Windows" => ChromeThemeMode == BrowserThemeMode.System,
                "Claro" => ChromeThemeMode == BrowserThemeMode.Light,
                "Escuro" => ChromeThemeMode == BrowserThemeMode.Dark,
                _ => IsTrackingSelection(label)
            };
            if (label is not ("Seguir Windows" or "Claro" or "Escuro" or "Básica" or "Equilibrada" or "Estrita"))
                continue;

            button.SetResourceReference(Control.BackgroundProperty, selected ? "BrowserSurfacePressedBrush" : "BrowserSurfaceBrush");
            button.SetResourceReference(Control.BorderBrushProperty, selected ? "BrowserAccentBrush" : "BrowserBorderBrush");
            button.FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal;
        }
    }

    private bool IsTrackingSelection(string label)
    {
        try
        {
            return ActiveProfile?.PreferredTrackingPreventionLevel switch
            {
                CoreWebView2TrackingPreventionLevel.Basic => label == "Básica",
                CoreWebView2TrackingPreventionLevel.Strict => label == "Estrita",
                CoreWebView2TrackingPreventionLevel.Balanced => label == "Equilibrada",
                _ => false
            };
        }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            return false;
        }
    }

    private static IEnumerable<T> SurfaceDescendants<T>(DependencyObject root) where T : DependencyObject
    {
        var count = VisualTreeHelper.GetChildrenCount(root);
        for (var index = 0; index < count; index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is T match) yield return match;
            foreach (var nested in SurfaceDescendants<T>(child))
                yield return nested;
        }
    }

    private static bool IsVisualDescendant(DependencyObject root, DependencyObject candidate)
    {
        for (DependencyObject? current = candidate; current is not null; current = VisualTreeHelper.GetParent(current))
            if (ReferenceEquals(current, root)) return true;
        return false;
    }
}
