using System.Windows;
using System.Windows.Controls;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Host.Browser;

public sealed class BrowserCredentialController : IDisposable
{
    private readonly CancellationTokenSource _lifetime = new();
    private bool _disposed;

    public async Task HandleClientCertificateAsync(
        Window owner,
        CoreWebView2ClientCertificateRequestedEventArgs args,
        Func<string?> currentSource)
    {
        var deferral = args.GetDeferral();
        try
        {
            args.Handled = true;
            if (_disposed || args.IsProxy)
            {
                args.Cancel = true;
                return;
            }

            var certificates = args.MutuallyTrustedCertificates?.ToList() ?? [];
            if (certificates.Count == 0)
            {
                args.Cancel = true;
                return;
            }

            var selected = await SelectCertificateAsync(owner, args.Host, certificates, _lifetime.Token);
            var current = currentSource();
            if (selected is null || !IsCurrentCertificateOrigin(args.Host, args.Port, current))
            {
                args.Cancel = true;
                return;
            }

            args.SelectedCertificate = selected;
            args.Cancel = false;
        }
        catch (OperationCanceledException)
        {
            args.Cancel = true;
        }
        finally
        {
            deferral.Complete();
        }
    }

    public async Task HandleBasicAuthenticationAsync(
        Window owner,
        CoreWebView2BasicAuthenticationRequestedEventArgs args,
        Func<string?> currentSource)
    {
        var deferral = args.GetDeferral();
        try
        {
            if (_disposed)
            {
                args.Cancel = true;
                return;
            }

            var requestedUri = args.Uri;
            var result = await PromptCredentialsAsync(owner, requestedUri, args.Challenge, _lifetime.Token);
            if (result is null || !BrowserPermissionController.IsSameOrigin(requestedUri, currentSource()))
            {
                args.Cancel = true;
                return;
            }

            args.Response.UserName = result.Value.UserName;
            args.Response.Password = result.Value.Password;
            args.Cancel = false;
        }
        catch (OperationCanceledException)
        {
            args.Cancel = true;
        }
        finally
        {
            deferral.Complete();
        }
    }

    private static bool IsCurrentCertificateOrigin(string host, int port, string? currentSource)
    {
        if (!Uri.TryCreate(currentSource, UriKind.Absolute, out var current)) return false;
        var requestedHost = host.Trim().Trim('[', ']').TrimEnd('.');
        var currentHost = current.IdnHost.Trim('[', ']').TrimEnd('.');
        return requestedHost.Equals(currentHost, StringComparison.OrdinalIgnoreCase) && current.Port == port;
    }

    private static Task<CoreWebView2ClientCertificate?> SelectCertificateAsync(
        Window owner,
        string host,
        IReadOnlyList<CoreWebView2ClientCertificate> certificates,
        CancellationToken cancellationToken)
    {
        var completion = new TaskCompletionSource<CoreWebView2ClientCertificate?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var dialog = CreateDialog(owner, "Certificado de cliente", 610, 390);
        var grid = new Grid { Margin = new Thickness(22) };
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.Children.Add(new TextBlock
        {
            Text = $"{host} solicita um certificado. Selecione um certificado mutuamente confiável:",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.Black,
            Margin = new Thickness(0, 0, 0, 12)
        });
        var list = new ListBox
        {
            DisplayMemberPath = nameof(CertificateItem.Label),
            ItemsSource = certificates.Select(c => new CertificateItem(c)).ToList()
        };
        Grid.SetRow(list, 1);
        grid.Children.Add(list);
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 14, 0, 0)
        };
        Grid.SetRow(buttons, 2);
        var cancel = new Button
        {
            Content = "Cancelar",
            MinWidth = 90,
            Padding = new Thickness(12, 7, 12, 7),
            Margin = new Thickness(0, 0, 8, 0)
        };
        var use = new Button { Content = "Usar certificado", MinWidth = 130, Padding = new Thickness(12, 7, 12, 7) };
        buttons.Children.Add(cancel);
        buttons.Children.Add(use);
        grid.Children.Add(buttons);
        dialog.Content = grid;

        CancellationTokenRegistration registration = default;
        void Complete(CoreWebView2ClientCertificate? certificate)
        {
            if (!completion.TrySetResult(certificate)) return;
            registration.Dispose();
            if (dialog.IsVisible) dialog.Close();
        }
        cancel.Click += (_, _) => Complete(null);
        use.Click += (_, _) => Complete((list.SelectedItem as CertificateItem)?.Certificate);
        dialog.Closed += (_, _) => Complete(null);
        registration = cancellationToken.Register(() => owner.Dispatcher.BeginInvoke(() => Complete(null)));
        dialog.Show();
        if (cancellationToken.IsCancellationRequested) Complete(null);
        return completion.Task;
    }

    private static Task<(string UserName, string Password)?> PromptCredentialsAsync(
        Window owner,
        string uri,
        string challenge,
        CancellationToken cancellationToken)
    {
        var completion = new TaskCompletionSource<(string, string)?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var dialog = CreateDialog(owner, "Autenticação do site", 480, 310);
        var stack = new StackPanel { Margin = new Thickness(22) };
        stack.Children.Add(new TextBlock
        {
            Text = $"O site solicita autenticação HTTP.\n{uri}\n{challenge}",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.Black,
            Margin = new Thickness(0, 0, 0, 14)
        });
        stack.Children.Add(new TextBlock { Text = "Usuário", Foreground = System.Windows.Media.Brushes.Black });
        var user = new TextBox { Margin = new Thickness(0, 4, 0, 10) };
        stack.Children.Add(user);
        stack.Children.Add(new TextBlock { Text = "Senha", Foreground = System.Windows.Media.Brushes.Black });
        var password = new PasswordBox { Margin = new Thickness(0, 4, 0, 16) };
        stack.Children.Add(password);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button
        {
            Content = "Cancelar",
            MinWidth = 90,
            Padding = new Thickness(12, 7, 12, 7),
            Margin = new Thickness(0, 0, 8, 0)
        };
        var login = new Button { Content = "Entrar", MinWidth = 90, Padding = new Thickness(12, 7, 12, 7) };
        buttons.Children.Add(cancel);
        buttons.Children.Add(login);
        stack.Children.Add(buttons);
        dialog.Content = stack;

        CancellationTokenRegistration registration = default;
        void Complete((string, string)? value)
        {
            if (!completion.TrySetResult(value)) return;
            registration.Dispose();
            password.Clear();
            user.Clear();
            if (dialog.IsVisible) dialog.Close();
        }
        cancel.Click += (_, _) => Complete(null);
        login.Click += (_, _) => Complete((user.Text, password.Password));
        dialog.Closed += (_, _) => Complete(null);
        registration = cancellationToken.Register(() => owner.Dispatcher.BeginInvoke(() => Complete(null)));
        dialog.Show();
        if (cancellationToken.IsCancellationRequested) Complete(null);
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

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (!_lifetime.IsCancellationRequested) _lifetime.Cancel();
        _lifetime.Dispose();
    }

    private sealed record CertificateItem(CoreWebView2ClientCertificate Certificate)
    {
        public string Label => $"{Certificate.DisplayName}\nSubject: {Certificate.Subject}\nIssuer: {Certificate.Issuer}\nValidade: {Certificate.ValidFrom:g} — {Certificate.ValidTo:g}";
    }
}
