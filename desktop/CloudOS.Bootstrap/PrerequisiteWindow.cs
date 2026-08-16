using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace CloudOS.Bootstrap;

public enum PrerequisiteAction { Exit, Full, WebOnly }

public sealed class PrerequisiteWindow : Window
{
    private readonly Func<CancellationToken, Task<PrerequisiteReport>> _refresh;
    private readonly StackPanel _items = new();
    private readonly Button _full = new() { Content = "Iniciar Full", MinWidth = 130, Margin = new Thickness(6) };
    private readonly Button _webOnly = new() { Content = "Iniciar WebOnly", MinWidth = 130, Margin = new Thickness(6) };
    private readonly TextBlock _summary = new() { Margin = new Thickness(0, 8, 0, 8), TextWrapping = TextWrapping.Wrap };
    private readonly CancellationTokenSource _lifetime = new();

    public PrerequisiteWindow(PrerequisiteReport report, Func<CancellationToken, Task<PrerequisiteReport>> refresh)
    {
        _refresh = refresh;
        Title = "CloudOS — Central de pré-requisitos";
        Width = 760;
        Height = 660;
        MinWidth = 640;
        MinHeight = 520;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = new SolidColorBrush(Color.FromRgb(8, 13, 24));
        Foreground = Brushes.White;

        var root = new DockPanel { Margin = new Thickness(24) };
        Content = root;
        var footer = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        DockPanel.SetDock(footer, Dock.Bottom);
        root.Children.Add(footer);

        var recheck = new Button { Content = "Verificar novamente", MinWidth = 140, Margin = new Thickness(6) };
        recheck.Click += async (_, _) =>
        {
            recheck.IsEnabled = false;
            try { Render(await _refresh(_lifetime.Token)); }
            catch (OperationCanceledException) { }
            finally { recheck.IsEnabled = true; }
        };
        footer.Children.Add(recheck);
        footer.Children.Add(_webOnly);
        footer.Children.Add(_full);
        var close = new Button { Content = "Sair", MinWidth = 90, Margin = new Thickness(6) };
        footer.Children.Add(close);
        close.Click += (_, _) => { SelectedAction = PrerequisiteAction.Exit; Close(); };
        _full.Click += (_, _) => { SelectedAction = PrerequisiteAction.Full; Close(); };
        _webOnly.Click += (_, _) => { SelectedAction = PrerequisiteAction.WebOnly; Close(); };

        var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        root.Children.Add(scroll);
        var body = new StackPanel();
        scroll.Content = body;
        body.Children.Add(new TextBlock { Text = "Antes de iniciar", FontSize = 28, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 8) });
        body.Children.Add(new TextBlock { Text = "O CloudOS verifica o que já existe no computador. Nada é instalado ou alterado automaticamente.", Opacity = .8, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) });
        body.Children.Add(_summary);
        body.Children.Add(_items);
        Render(report);
    }

    public PrerequisiteAction SelectedAction { get; private set; } = PrerequisiteAction.Exit;

    private void Render(PrerequisiteReport report)
    {
        _items.Children.Clear();
        foreach (var item in report.Items)
        {
            var card = new Border { Background = new SolidColorBrush(Color.FromRgb(17, 26, 43)), CornerRadius = new CornerRadius(8), Padding = new Thickness(12), Margin = new Thickness(0, 4, 0, 4) };
            var row = new Grid();
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(180) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.Children.Add(new TextBlock { Text = item.Label, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
            var state = new TextBlock { Text = item.State, Opacity = .9, VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(state, 1); row.Children.Add(state);
            var detail = new TextBlock { Text = item.Detail, Opacity = .72, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(detail, 2); row.Children.Add(detail);
            card.Child = row;
            _items.Children.Add(card);
        }
        _full.IsEnabled = report.FullReady;
        _webOnly.IsEnabled = report.WebOnlyReady;
        _summary.Text = report.FullReady
            ? "Modo Full pronto. O modo WebOnly também está disponível."
            : report.WebOnlyReady
                ? "Modo Full requer ação do usuário, mas WebOnly pode iniciar agora."
                : "A instalação está incompleta. Verifique os itens marcados antes de iniciar.";
    }

    protected override void OnClosed(EventArgs e)
    {
        _lifetime.Cancel();
        _lifetime.Dispose();
        base.OnClosed(e);
    }
}
