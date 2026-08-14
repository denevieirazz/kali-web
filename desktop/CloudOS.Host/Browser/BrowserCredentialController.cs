using System.Windows;
using System.Windows.Controls;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Host.Browser;

public sealed class BrowserCredentialController
{
    public async Task HandleClientCertificateAsync(Window owner, CoreWebView2ClientCertificateRequestedEventArgs args)
    {
        var deferral = args.GetDeferral();
        try
        {
            args.Handled = true;
            var certificates = args.MutuallyTrustedCertificates?.ToList() ?? [];
            if (certificates.Count == 0) return;
            var selected = await SelectCertificateAsync(owner, args.Host, certificates);
            if (selected is not null) args.SelectedCertificate = selected;
        }
        finally { deferral.Complete(); }
    }

    public async Task HandleBasicAuthenticationAsync(Window owner, CoreWebView2BasicAuthenticationRequestedEventArgs args)
    {
        var deferral = args.GetDeferral();
        try
        {
            var result = await PromptCredentialsAsync(owner, args.Uri, args.Challenge);
            if (result is null)
            {
                args.Cancel = true;
                return;
            }
            args.Response.UserName = result.Value.UserName;
            args.Response.Password = result.Value.Password;
            args.Cancel = false;
        }
        finally { deferral.Complete(); }
    }

    private static Task<CoreWebView2ClientCertificate?> SelectCertificateAsync(Window owner, string host, IReadOnlyList<CoreWebView2ClientCertificate> certificates)
    {
        var completion = new TaskCompletionSource<CoreWebView2ClientCertificate?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var dialog = CreateDialog(owner, "Certificado de cliente", 610, 390);
        var grid = new Grid { Margin = new Thickness(22) };
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var intro = new TextBlock { Text = $"{host} solicita um certificado. Selecione um certificado mutuamente confiável:", TextWrapping = TextWrapping.Wrap, Foreground = System.Windows.Media.Brushes.Black, Margin = new Thickness(0, 0, 0, 12) };
        grid.Children.Add(intro);
        var list = new ListBox { DisplayMemberPath = nameof(CertificateItem.Label), ItemsSource = certificates.Select(c => new CertificateItem(c)).ToList() };
        Grid.SetRow(list, 1);
        grid.Children.Add(list);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 14, 0, 0) };
        Grid.SetRow(buttons, 2);
        var cancel = new Button { Content = "Cancelar", MinWidth = 90, Padding = new Thickness(12, 7, 12, 7), Margin = new Thickness(0, 0, 8, 0) };
        var use = new Button { Content = "Usar certificado", MinWidth = 130, Padding = new Thickness(12, 7, 12, 7) };
        buttons.Children.Add(cancel); buttons.Children.Add(use); grid.Children.Add(buttons);
        dialog.Content = grid;
        void Complete(CoreWebView2ClientCertificate? certificate)
        {
            if (!completion.TrySetResult(certificate)) return;
            dialog.Close();
        }
        cancel.Click += (_, _) => Complete(null);
        use.Click += (_, _) => Complete((list.SelectedItem as CertificateItem)?.Certificate);
        dialog.Closed += (_, _) => completion.TrySetResult(null);
        dialog.Show();
        return completion.Task;
    }

    private static Task<(string UserName, string Password)?> PromptCredentialsAsync(Window owner, string uri, string challenge)
    {
        var completion = new TaskCompletionSource<(string, string)?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var dialog = CreateDialog(owner, "Autenticação do site", 480, 310);
        var stack = new StackPanel { Margin = new Thickness(22) };
        stack.Children.Add(new TextBlock { Text = $"O site solicita autenticação HTTP.\n{uri}\n{challenge}", TextWrapping = TextWrapping.Wrap, Foreground = System.Windows.Media.Brushes.Black, Margin = new Thickness(0, 0, 0, 14) });
        stack.Children.Add(new TextBlock { Text = "Usuário", Foreground = System.Windows.Media.Brushes.Black });
        var user = new TextBox { Margin = new Thickness(0, 4, 0, 10) };
        stack.Children.Add(user);
        stack.Children.Add(new TextBlock { Text = "Senha", Foreground = System.Windows.Media.Brushes.Black });
        var password = new PasswordBox { Margin = new Thickness(0, 4, 0, 16) };
        stack.Children.Add(password);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = "Cancelar", MinWidth = 90, Padding = new Thickness(12, 7, 12, 7), Margin = new Thickness(0, 0, 8, 0) };
        var login = new Button { Content = "Entrar", MinWidth = 90, Padding = new Thickness(12, 7, 12, 7) };
        buttons.Children.Add(cancel); buttons.Children.Add(login); stack.Children.Add(buttons);
        dialog.Content = stack;
        void Complete((string, string)? value)
        {
            if (!completion.TrySetResult(value)) return;
            password.Clear();
            dialog.Close();
        }
        cancel.Click += (_, _) => Complete(null);
        login.Click += (_, _) => Complete((user.Text, password.Password));
        dialog.Closed += (_, _) => completion.TrySetResult(null);
        dialog.Show();
        return completion.Task;
    }

    private static Window CreateDialog(Window owner, string title, double width, double height) => new()
    {
        Title = title,
        Owner = owner,
        Width = width,
        Height = height,
        ResizeMode = ResizeMode.NoResize,
        WindowStartupLocation = WindowStartupLocation.CenterOwner,
        Background = System.Windows.Media.Brushes.White,
        ShowInTaskbar = false
    };

    private sealed record CertificateItem(CoreWebView2ClientCertificate Certificate)
    {
        public string Label => $"{Certificate.DisplayName}\nSubject: {Certificate.Subject}\nIssuer: {Certificate.Issuer}\nValidade: {Certificate.ValidFrom:g} — {Certificate.ValidTo:g}";
    }
}
