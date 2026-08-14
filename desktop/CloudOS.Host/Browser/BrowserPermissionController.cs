using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Host.Browser;

public sealed class BrowserPermissionController : IDisposable
{
    private static readonly TimeSpan PromptTimeout = TimeSpan.FromSeconds(30);
    private CancellationTokenSource _promptLifetime = new();
    private bool _disposed;

    public static bool RequiresUserPrompt(CoreWebView2PermissionKind kind) =>
        BrowserSecurityPolicy.Permission(kind.ToString()) == BrowserPermissionDisposition.Prompt;

    public static bool IsDeniedByDefault(CoreWebView2PermissionKind kind) => !RequiresUserPrompt(kind);

    public async Task HandleAsync(
        Window owner,
        CoreWebView2PermissionRequestedEventArgs args,
        Func<string?> currentSource)
    {
        if (_disposed)
        {
            args.SavesInProfile = false;
            args.State = CoreWebView2PermissionState.Deny;
            args.Handled = true;
            return;
        }

        var deferral = args.GetDeferral();
        var token = _promptLifetime.Token;
        try
        {
            args.SavesInProfile = BrowserSecurityPolicy.SavesPermissionInProfile;
            args.Handled = true;
            if (IsDeniedByDefault(args.PermissionKind))
            {
                args.State = CoreWebView2PermissionState.Deny;
                return;
            }

            var requestedSource = args.Uri;
            var label = args.PermissionKind switch
            {
                CoreWebView2PermissionKind.Camera => "sua câmera",
                CoreWebView2PermissionKind.Microphone => "seu microfone",
                CoreWebView2PermissionKind.Geolocation => "sua localização",
                CoreWebView2PermissionKind.Notifications => "enviar notificações",
                CoreWebView2PermissionKind.MultipleAutomaticDownloads => "iniciar vários downloads automaticamente",
                _ => "este recurso"
            };
            var host = Uri.TryCreate(requestedSource, UriKind.Absolute, out var uri) ? uri.IdnHost : requestedSource;
            var allowed = await ShowTimedPromptAsync(
                owner,
                "Permissão do site",
                $"{host} deseja usar {label}.",
                "Permitir uma vez",
                "Bloquear",
                PromptTimeout,
                token);

            args.State = allowed && BrowserSecurityPolicy.IsSameOrigin(requestedSource, currentSource())
                ? CoreWebView2PermissionState.Allow
                : CoreWebView2PermissionState.Deny;
        }
        catch (OperationCanceledException)
        {
            args.State = CoreWebView2PermissionState.Deny;
        }
        finally
        {
            deferral.Complete();
        }
    }

    public void CancelAll()
    {
        if (_disposed) return;
        var previous = _promptLifetime;
        _promptLifetime = new CancellationTokenSource();
        previous.Cancel();
        previous.Dispose();
    }

    internal static Task<bool> ShowTimedPromptAsync(
        Window owner,
        string title,
        string message,
        string allowText,
        string denyText,
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        var completion = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var dialog = new Window
        {
            Title = title,
            Owner = owner,
            Width = 440,
            Height = 220,
            ResizeMode = ResizeMode.NoResize,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Background = System.Windows.Media.Brushes.White,
            ShowInTaskbar = false
        };
        var grid = new Grid { Margin = new Thickness(22) };
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.Children.Add(new TextBlock
        {
            Text = message,
            TextWrapping = TextWrapping.Wrap,
            FontSize = 15,
            Foreground = System.Windows.Media.Brushes.Black
        });
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 18, 0, 0)
        };
        Grid.SetRow(buttons, 1);
        var deny = new Button
        {
            Content = denyText,
            MinWidth = 90,
            Padding = new Thickness(12, 7, 12, 7),
            Margin = new Thickness(0, 0, 8, 0)
        };
        var allow = new Button
        {
            Content = allowText,
            MinWidth = 110,
            Padding = new Thickness(12, 7, 12, 7)
        };
        buttons.Children.Add(deny);
        buttons.Children.Add(allow);
        grid.Children.Add(buttons);
        dialog.Content = grid;

        var timer = new DispatcherTimer { Interval = timeout };
        CancellationTokenRegistration registration = default;
        void Complete(bool result)
        {
            if (!completion.TrySetResult(result)) return;
            timer.Stop();
            registration.Dispose();
            if (dialog.IsVisible) dialog.Close();
        }

        deny.Click += (_, _) => Complete(false);
        allow.Click += (_, _) => Complete(true);
        dialog.Closed += (_, _) => Complete(false);
        timer.Tick += (_, _) => Complete(false);
        registration = cancellationToken.Register(() =>
            owner.Dispatcher.BeginInvoke(() => Complete(false), DispatcherPriority.Send));
        timer.Start();
        dialog.Show();
        if (cancellationToken.IsCancellationRequested) Complete(false);
        return completion.Task;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        var lifetime = _promptLifetime;
        if (!lifetime.IsCancellationRequested) lifetime.Cancel();
        lifetime.Dispose();
    }
}
