using System.Windows;

namespace CloudOS.Host;

public partial class App : Application
{
    private SingleInstanceCoordinator? _singleInstance;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        HostOptions options;
        try
        {
            options = HostOptions.Parse(e.Args);
        }
        catch (ArgumentException error)
        {
            MessageBox.Show(error.Message, "CloudOS", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(2);
            return;
        }

        _singleInstance = new SingleInstanceCoordinator();
        if (!_singleInstance.TryAcquire())
        {
            var activated = false;
            for (var attempt = 0; attempt < 3 && !activated; attempt++)
            {
                activated = _singleInstance.SignalExistingAsync().GetAwaiter().GetResult();
                if (!activated) Thread.Sleep(250);
            }
            if (activated)
            {
                Shutdown();
                return;
            }

            var restart = MessageBox.Show(
                "O CloudOS está em segundo plano, mas não respondeu ao pedido para mostrar a janela.\n\nDeseja encerrar somente essa instância do CloudOS e abrir uma nova? Dados não salvos em aplicativos nativos podem ser perdidos.",
                "CloudOS não respondeu",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            if (restart != MessageBoxResult.Yes)
            {
                Shutdown(1);
                return;
            }

            _singleInstance.Dispose();
            _singleInstance = null;
            if (!SingleInstanceCoordinator.TryTerminateUnresponsiveHost(out var recoveryError))
            {
                MessageBox.Show(recoveryError, "CloudOS", MessageBoxButton.OK, MessageBoxImage.Error);
                Shutdown(1);
                return;
            }

            Thread.Sleep(200);
            _singleInstance = new SingleInstanceCoordinator();
            if (!_singleInstance.TryAcquire())
            {
                MessageBox.Show("A sessão antiga ainda está encerrando. Aguarde alguns segundos e abra o CloudOS novamente.", "CloudOS", MessageBoxButton.OK, MessageBoxImage.Information);
                Shutdown(1);
                return;
            }
        }

        var window = new MainWindow(options);
        MainWindow = window;
        _singleInstance.ActivationRequested += (_, _) => Dispatcher.Invoke(() =>
        {
            if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
            window.Show();
            window.Activate();
        });
        _singleInstance.StartListening();
        window.Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _singleInstance?.Dispose();
        base.OnExit(e);
    }

    protected override void OnSessionEnding(SessionEndingCancelEventArgs e)
    {
        if (MainWindow is MainWindow window) window.PrepareForSessionEnding();
        base.OnSessionEnding(e);
        // CloudOS kiosk must never veto Windows logoff or shutdown.
        e.Cancel = false;
    }
}
