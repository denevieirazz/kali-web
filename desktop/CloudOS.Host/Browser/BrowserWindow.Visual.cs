using Microsoft.Win32;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;

namespace CloudOS.Host.Browser;

public partial class BrowserWindow
{
    private const string TabVisualMarker = "CloudOS.Browser.TabVisual.v1";
    private BrowserThemeMode _browserThemeMode = BrowserThemeMode.System;
    private bool _visualChromeLoaded;
    private bool _visualChromeUpdating;
    private bool? _lastLoadingVisualState;
    private string? _lastSecurityVisualState;

    internal void SetChromeTheme(BrowserThemeMode mode)
    {
        _browserThemeMode = mode;
        ApplyChromeTheme();
    }

    private void BrowserWindowVisual_Loaded(object sender, RoutedEventArgs e)
    {
        _visualChromeLoaded = true;
        ApplyChromeTheme();
        UpdateResponsiveChrome();
        NormalizeDynamicChrome();
        StyleRenderedTabs(forceSizing: true);
    }

    private void BrowserWindowVisual_Activated(object? sender, EventArgs e)
    {
        if (_visualChromeLoaded && _browserThemeMode == BrowserThemeMode.System)
            ApplyChromeTheme();
    }

    private void BrowserWindowVisual_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (!_visualChromeLoaded) return;
        UpdateResponsiveChrome();
        StyleRenderedTabs(forceSizing: true);
    }

    private void BrowserWindowVisual_LayoutUpdated(object? sender, EventArgs e)
    {
        if (!_visualChromeLoaded || _visualChromeUpdating) return;
        _visualChromeUpdating = true;
        try
        {
            NormalizeDynamicChrome();
            StyleRenderedTabs();
        }
        finally
        {
            _visualChromeUpdating = false;
        }
    }

    private void ThemeButton_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu
        {
            PlacementTarget = ThemeButton,
            Placement = PlacementMode.Bottom,
            Background = FindBrush("BrowserSurfaceBrush"),
            Foreground = FindBrush("BrowserTextPrimaryBrush"),
            BorderBrush = FindBrush("BrowserBorderBrush"),
            BorderThickness = new Thickness(1)
        };

        menu.Items.Add(CreateThemeMenuItem("Seguir Windows", BrowserThemeMode.System));
        menu.Items.Add(CreateThemeMenuItem("Claro", BrowserThemeMode.Light));
        menu.Items.Add(CreateThemeMenuItem("Escuro", BrowserThemeMode.Dark));
        menu.IsOpen = true;
    }

    private MenuItem CreateThemeMenuItem(string label, BrowserThemeMode mode)
    {
        var item = new MenuItem
        {
            Header = label,
            IsCheckable = true,
            IsChecked = _browserThemeMode == mode
        };
        item.Click += (_, _) => SetChromeTheme(mode);
        return item;
    }

    private void TabScroll_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (TabScroll.ScrollableWidth <= 0) return;
        TabScroll.ScrollToHorizontalOffset(TabScroll.HorizontalOffset - e.Delta);
        e.Handled = true;
    }

    private void ApplyChromeTheme()
    {
        var palette = BrowserChromeTheme.Resolve(_browserThemeMode, ReadWindowsLightTheme());
        SetBrush("BrowserWindowBrush", palette.Window);
        SetBrush("BrowserChromeBrush", palette.Chrome);
        SetBrush("BrowserSurfaceBrush", palette.Surface);
        SetBrush("BrowserSurfaceAltBrush", palette.SurfaceAlt);
        SetBrush("BrowserSurfaceHoverBrush", palette.SurfaceHover);
        SetBrush("BrowserSurfacePressedBrush", palette.SurfacePressed);
        SetBrush("BrowserActiveTabBrush", palette.ActiveTab);
        SetBrush("BrowserInactiveTabBrush", palette.InactiveTab);
        SetBrush("BrowserBorderBrush", palette.Border);
        SetBrush("BrowserTextPrimaryBrush", palette.TextPrimary);
        SetBrush("BrowserTextSecondaryBrush", palette.TextSecondary);
        SetBrush("BrowserTextMutedBrush", palette.TextMuted);
        SetBrush("BrowserAccentBrush", palette.Accent);
        SetBrush("BrowserAccentHoverBrush", palette.AccentHover);
        SetBrush("BrowserDangerBrush", palette.Danger);
        SetBrush("BrowserSuccessBrush", palette.Success);
        SetBrush("BrowserInputBrush", palette.Input);

        NormalizeDynamicChrome();
        StyleRenderedTabs();
    }

    private static bool ReadWindowsLightTheme()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                writable: false);
            return key?.GetValue("AppsUseLightTheme") switch
            {
                int value => value != 0,
                long value => value != 0,
                _ => false
            };
        }
        catch (Exception error) when (
            error is UnauthorizedAccessException
            or System.Security.SecurityException
            or System.IO.IOException)
        {
            return false;
        }
    }

    private void SetBrush(string key, string hex)
    {
        var color = (Color)ColorConverter.ConvertFromString(hex)!;
        if (Resources[key] is SolidColorBrush existing && !existing.IsFrozen)
        {
            existing.Color = color;
            return;
        }
        Resources[key] = new SolidColorBrush(color);
    }

    private Brush FindBrush(string key) => (Brush)FindResource(key);

    private void UpdateResponsiveChrome()
    {
        BrandBadge.Visibility = ActualWidth >= 1080 ? Visibility.Visible : Visibility.Collapsed;
        SecurityIndicator.Visibility = ActualWidth >= 900 ? Visibility.Visible : Visibility.Collapsed;

        if (ActualWidth > 0)
            LibraryPanel.Width = Math.Clamp(ActualWidth * 0.32, 300, 430);
    }

    private void NormalizeDynamicChrome()
    {
        if (!_visualChromeLoaded) return;

        var loading = _activeTab?.IsLoading == true;
        if (_lastLoadingVisualState != loading || ReloadStopButton.Content is string)
        {
            _lastLoadingVisualState = loading;
            LoadingStatusText.Visibility = loading ? Visibility.Visible : Visibility.Collapsed;
            AddressShell.SetResourceReference(
                Border.BorderBrushProperty,
                loading ? "BrowserAccentBrush" : "BrowserBorderBrush");
            ReloadStopButton.Content = loading ? CreateStopIcon() : CreateReloadIcon();
            ReloadStopButton.ToolTip = loading ? "Parar carregamento (Esc)" : "Recarregar (Ctrl+R)";
        }

        if (FavoriteButton.Content is string favoriteContent && favoriteContent is "★" or "☆")
        {
            var isFavorite = favoriteContent == "★";
            FavoriteButton.Tag = isFavorite;
            FavoriteButton.Content = CreateFavoriteIcon(isFavorite);
            FavoriteButton.ToolTip = isFavorite ? "Remover dos favoritos" : "Adicionar aos favoritos";
        }

        var currentUri = _activeTab?.CurrentUri;
        var secure = currentUri?.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) == true;
        var securityState = currentUri is null ? "none" : secure ? "https" : "http";
        var securityLabel = secure ? "Seguro" : currentUri is null ? "—" : "HTTP";
        if (!string.Equals(_lastSecurityVisualState, securityState, StringComparison.Ordinal) ||
            !string.Equals(SecurityIndicator.Text, securityLabel, StringComparison.Ordinal))
        {
            _lastSecurityVisualState = securityState;
            SecurityIndicator.Text = securityLabel;
            SecurityIndicator.SetResourceReference(
                TextBlock.ForegroundProperty,
                secure ? "BrowserSuccessBrush" : "BrowserTextMutedBrush");
            SecurityIcon.Data = Geometry.Parse(secure
                ? "M3,7 L3,4.8 A3,3 0 0 1 9,4.8 L9,7 M2,7 L10,7 L10,13 L2,13 Z M6,9.4 L6,11"
                : "M4,7 L4,5 A3,3 0 0 1 9.8,4 M2,7 L10,7 L10,13 L2,13 Z M6,9.4 L6,11");
            SecurityIcon.SetResourceReference(
                Shape.StrokeProperty,
                secure ? "BrowserSuccessBrush" : "BrowserTextMutedBrush");
        }
    }

    private void StyleRenderedTabs(bool forceSizing = false)
    {
        if (!_visualChromeLoaded || TabStrip.Children.Count == 0) return;

        var available = TabScroll.ActualWidth > 0 ? TabScroll.ActualWidth : Math.Max(320, ActualWidth - 280);
        var visibleTarget = Math.Clamp(_tabs.Count, 1, 6);
        var maxSelectWidth = Math.Clamp((available / visibleTarget) - 38, 96, 210);

        foreach (var container in TabStrip.Children.OfType<StackPanel>())
        {
            var buttons = container.Children.OfType<Button>().ToArray();
            if (buttons.Length < 2 || buttons[0].Tag is not BrowserTab tab) continue;

            var selectButton = buttons[0];
            var closeButton = buttons[1];
            var needsVisual = selectButton.Content is not Grid { Tag: TabVisualMarker } || closeButton.Content is not Path;
            if (!needsVisual && !forceSizing) continue;

            var active = ReferenceEquals(tab, _activeTab);
            container.Margin = new Thickness(2, 0, 2, 0);
            container.VerticalAlignment = VerticalAlignment.Center;

            selectButton.Style = (Style)FindResource("TabSelectButtonStyle");
            selectButton.MinWidth = tab.IsPinned ? 80 : 108;
            selectButton.MaxWidth = tab.IsPinned ? Math.Min(132, maxSelectWidth) : maxSelectWidth;
            selectButton.ToolTip = tab.Title;
            selectButton.FontWeight = active ? FontWeights.SemiBold : FontWeights.Normal;
            selectButton.SetResourceReference(
                Control.BackgroundProperty,
                active ? "BrowserActiveTabBrush" : "BrowserInactiveTabBrush");
            selectButton.SetResourceReference(
                Control.ForegroundProperty,
                active ? "BrowserTextPrimaryBrush" : "BrowserTextSecondaryBrush");
            selectButton.SetResourceReference(
                Control.BorderBrushProperty,
                active ? "BrowserAccentBrush" : "BrowserBorderBrush");

            closeButton.Style = (Style)FindResource("TabCloseButtonStyle");
            closeButton.ToolTip = "Fechar aba (Ctrl+W)";
            closeButton.SetResourceReference(
                Control.BackgroundProperty,
                active ? "BrowserActiveTabBrush" : "BrowserInactiveTabBrush");
            closeButton.SetResourceReference(
                Control.BorderBrushProperty,
                active ? "BrowserAccentBrush" : "BrowserBorderBrush");

            if (needsVisual)
            {
                selectButton.Content = CreateTabVisual(tab, active);
                closeButton.Content = CreateCloseIcon();
                if (active) selectButton.BringIntoView();
            }
        }
    }

    private Grid CreateTabVisual(BrowserTab tab, bool active)
    {
        var grid = new Grid { Tag = TabVisualMarker };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var leading = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            VerticalAlignment = VerticalAlignment.Center
        };
        if (tab.IsPinned)
        {
            var pin = new Path
            {
                Width = 11,
                Height = 11,
                Margin = new Thickness(0, 0, 6, 0),
                Stretch = Stretch.Uniform,
                Data = Geometry.Parse("M3,1 L9,1 L8,5 L10,7 L6.8,7 L6,12 L5.2,7 L2,7 L4,5 Z")
            };
            pin.SetResourceReference(Shape.FillProperty, "BrowserAccentBrush");
            leading.Children.Add(pin);
        }
        if (tab.IsLoading)
        {
            var loadingDot = new Ellipse { Width = 7, Height = 7, Margin = new Thickness(0, 0, 6, 0) };
            loadingDot.SetResourceReference(Shape.FillProperty, "BrowserAccentBrush");
            leading.Children.Add(loadingDot);
        }
        Grid.SetColumn(leading, 0);
        grid.Children.Add(leading);

        var title = new TextBlock
        {
            Text = string.IsNullOrWhiteSpace(tab.Title) ? "Nova aba" : tab.Title,
            FontSize = 12,
            FontWeight = active ? FontWeights.SemiBold : FontWeights.Normal,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        title.SetResourceReference(
            TextBlock.ForegroundProperty,
            active ? "BrowserTextPrimaryBrush" : "BrowserTextSecondaryBrush");
        Grid.SetColumn(title, 1);
        grid.Children.Add(title);

        if (tab.IsMuted || tab.IsPlayingAudio)
        {
            var audio = new Path
            {
                Width = 12,
                Height = 12,
                Margin = new Thickness(6, 0, 0, 0),
                Stretch = Stretch.Uniform,
                StrokeThickness = 1.5,
                Data = Geometry.Parse(tab.IsMuted
                    ? "M1,6 L4,6 L7,3 L7,11 L4,8 L1,8 Z M9,5 L13,9 M13,5 L9,9"
                    : "M1,6 L4,6 L7,3 L7,11 L4,8 L1,8 Z M9,5 A4,4 0 0 1 9,9 M10.5,3 A6,6 0 0 1 10.5,11")
            };
            audio.SetResourceReference(Shape.StrokeProperty, "BrowserTextMutedBrush");
            Grid.SetColumn(audio, 2);
            grid.Children.Add(audio);
        }

        return grid;
    }

    private Path CreateReloadIcon()
    {
        var icon = new Path
        {
            Width = 17,
            Height = 17,
            Stretch = Stretch.Uniform,
            StrokeThickness = 1.7,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            Data = Geometry.Parse("M13.5,5.3 A6,6 0 1 0 14,10 M13.5,2.2 L13.5,5.4 L10.3,5.4")
        };
        icon.SetResourceReference(Shape.StrokeProperty, "BrowserTextSecondaryBrush");
        return icon;
    }

    private Path CreateStopIcon()
    {
        var icon = new Path
        {
            Width = 13,
            Height = 13,
            Stretch = Stretch.Uniform,
            Data = Geometry.Parse("M2,2 L12,2 L12,12 L2,12 Z")
        };
        icon.SetResourceReference(Shape.FillProperty, "BrowserTextSecondaryBrush");
        return icon;
    }

    private Path CreateFavoriteIcon(bool filled)
    {
        var icon = new Path
        {
            Width = 15,
            Height = 15,
            Stretch = Stretch.Uniform,
            StrokeThickness = 1.5,
            StrokeLineJoin = PenLineJoin.Round,
            Data = Geometry.Parse("M8,1.4 L10,5.3 L14.4,5.9 L11.2,9 L12,13.5 L8,11.4 L4,13.5 L4.8,9 L1.6,5.9 L6,5.3 Z")
        };
        icon.SetResourceReference(Shape.StrokeProperty, filled ? "BrowserAccentBrush" : "BrowserTextSecondaryBrush");
        if (filled) icon.SetResourceReference(Shape.FillProperty, "BrowserAccentBrush");
        return icon;
    }

    private Path CreateCloseIcon()
    {
        var icon = new Path
        {
            Width = 11,
            Height = 11,
            Stretch = Stretch.Uniform,
            StrokeThickness = 1.7,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            Data = Geometry.Parse("M2,2 L10,10 M10,2 L2,10")
        };
        icon.SetResourceReference(Shape.StrokeProperty, "BrowserTextMutedBrush");
        return icon;
    }
}
