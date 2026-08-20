using System.Windows;

namespace CloudOS.Host;

public partial class App : Application
{
    private SingleInstanceCoordinator? _singleInstance;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
        {
            var ex = args.ExceptionObject as Exception;
            var logPath = System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "CloudOS", "logs", $"host-{DateTime.UtcNow:yyyyMMdd}.log");
            try { System.IO.File.AppendAllText(logPath, $"{DateTimeOffset.Now:O} [crash:domain] {ex}\n"); } catch {}
        };
        DispatcherUnhandledException += (_, args) =>
        {
            var logPath = System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "CloudOS", "logs", $"host-{DateTime.UtcNow:yyyyMMdd}.log");
            try { System.IO.File.AppendAllText(logPath, $"{DateTimeOffset.Now:O} [crash:dispatcher] {args.Exception}\n"); } catch {}
        };

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
            _singleInstance.SignalExistingAsync().GetAwaiter().GetResult();
            Shutdown();
            return;
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
        window.Activate();
        window.Focus();
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
