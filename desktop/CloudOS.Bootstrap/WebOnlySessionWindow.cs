using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace CloudOS.Bootstrap;

public sealed class WebOnlySessionWindow : Window
{
    public WebOnlySessionWindow(Uri url, Action openBrowser)
    {
        Title = "CloudOS — WebOnly";
        Width = 520;
        Height = 270;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = new SolidColorBrush(Color.FromRgb(8, 13, 24));
        Foreground = Brushes.White;
        var body = new StackPanel { Margin = new Thickness(28) };
        Content = body;
        body.Children.Add(new TextBlock { Text = "CloudOS WebOnly está em execução", FontSize = 24, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0,0,0,12) });
        body.Children.Add(new TextBlock { Text = "O backend local pertence a esta sessão e será encerrado quando esta janela for fechada.", Opacity=.78, TextWrapping=TextWrapping.Wrap });
        body.Children.Add(new TextBlock { Text = url.ToString(), Margin = new Thickness(0,14,0,14), Opacity=.85 });
        var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var reopen = new Button { Content = "Abrir novamente", MinWidth=120, Margin=new Thickness(6) };
        reopen.Click += (_,_) => openBrowser();
        var close = new Button { Content = "Encerrar WebOnly", MinWidth=130, Margin=new Thickness(6) };
        close.Click += (_,_) => Close();
        row.Children.Add(reopen); row.Children.Add(close); body.Children.Add(row);
    }
}
