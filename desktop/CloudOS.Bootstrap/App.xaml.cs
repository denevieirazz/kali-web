using System.IO;
using System.Windows;
using Velopack;

namespace CloudOS.Bootstrap;

public partial class App : Application
{
    private static readonly TimeSpan ReadinessTimeout = TimeSpan.FromSeconds(45);
    private static readonly TimeSpan StabilityPeriod = TimeSpan.FromSeconds(90);
    private readonly CancellationTokenSource _lifetime = new();
    private readonly CrashLoopPolicy _policy = new();
    private BootstrapInstanceGuard? _instanceGuard;
    private BootstrapSupervisor? _supervisor;
    private BootStateStore? _store;
    private DistributionStateStore? _distributionStateStore;
    private ProductMetadata _productMetadata = new();

    [STAThread]
    private static void Main(string[] args)
    {
        VelopackApp.Build().Run();
        var app = new App();
        app.InitializeComponent();
        app.Run();
    }

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _instanceGuard = new BootstrapInstanceGuard();
        if (!_instanceGuard.TryAcquire()) { Shutdown(); return; }

        BootstrapOptions options;
        try
        {
            options = BootstrapOptions.Parse(e.Args);
            var localRoot = DistributionEnvironment.ResolveLocalRoot();
            _store = new BootStateStore(localRoot);
            _distributionStateStore = new DistributionStateStore(localRoot);
            _productMetadata = ProductMetadata.Load(DistributionEnvironment.ResolvePackageRoot(options));
            _store.AppendLog($"Bootstrap iniciado. host={options.HostPath} version={_productMetadata.Version} channel={_productMetadata.Channel}");

            if (options.CheckUpdateOnly)
            {
                ShowUpdateWindow(options);
                Shutdown();
                return;
            }

            var requiresPrerequisites = options.ShowPrerequisites ||
                (!options.SkipPrerequisites && !PrerequisiteStateStore.IsAccepted(localRoot));
            if (requiresPrerequisites)
            {
                var action = await ShowPrerequisitesAsync(options);
                if (action == PrerequisiteAction.Exit) { Shutdown(); return; }
                PrerequisiteStateStore.MarkAccepted(localRoot, action == PrerequisiteAction.Full ? "Full" : "WebOnly");
                if (action == PrerequisiteAction.WebOnly)
                {
                    await RunWebOnlyAsync(options);
                    Shutdown();
                    return;
                }
            }

            await RunLoopAsync(options, _lifetime.Token);
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested)
        {
            Shutdown();
        }
        catch (Exception error)
        {
            try { _store ??= new BootStateStore(DistributionEnvironment.ResolveLocalRoot()); }
            catch (Exception storageError) when (storageError is IOException or UnauthorizedAccessException)
            {
                MessageBox.Show($"O CloudOS não conseguiu preparar o diretório de recuperação: {storageError.Message}", "CloudOS", MessageBoxButton.OK, MessageBoxImage.Error);
                Shutdown(1); return;
            }
            _store.AppendLog($"Falha do bootstrap: {error.GetType().Name}: {error.Message}");
            var action = ShowRecovery(error.Message);
            if (action == RecoveryAction.Rollback)
            {
                try { await RollbackAsync(); return; }
                catch (Exception rollbackError)
                {
                    _store.AppendLog($"Rollback falhou: {rollbackError.GetType().Name}: {rollbackError.Message}");
                    MessageBox.Show($"Não foi possível restaurar a versão anterior: {rollbackError.Message}", "CloudOS Recovery", MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
            else if (action == RecoveryAction.Retry)
            {
                MessageBox.Show("Revise os pré-requisitos e inicie o CloudOS novamente.", "CloudOS", MessageBoxButton.OK, MessageBoxImage.Information);
            }
            Shutdown(1);
        }
    }

    private async Task<PrerequisiteAction> ShowPrerequisitesAsync(BootstrapOptions options)
    {
        var report = await PrerequisiteProbe.RunAsync(options, _lifetime.Token);
        var window = new PrerequisiteWindow(report, token => PrerequisiteProbe.RunAsync(options, token));
        MainWindow = window; window.ShowDialog(); MainWindow = null;
        return window.SelectedAction;
    }

    private async Task RunWebOnlyAsync(BootstrapOptions options)
    {
        await using var session = new WebOnlySession();
        var url = await session.StartAsync(options, _lifetime.Token);
        session.OpenBrowser();
        var window = new WebOnlySessionWindow(url, session.OpenBrowser);
        MainWindow = window; window.ShowDialog(); MainWindow = null;
        await session.StopAsync(_lifetime.Token);
    }

    private void ShowUpdateWindow(BootstrapOptions options)
    {
        var source = options.UpdateSource ?? Environment.GetEnvironmentVariable("CLOUDOS_UPDATE_SOURCE");
        if (string.IsNullOrWhiteSpace(source))
        {
            MessageBox.Show("Nenhuma fonte de atualização foi configurada.", "CloudOS Atualizações", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var window = new UpdateWindow(source, options.UpdateChannel, _productMetadata, DistributionEnvironment.ResolveLocalRoot());
        MainWindow = window; window.ShowDialog(); MainWindow = null;
    }

    private async Task RollbackAsync()
    {
        if (_distributionStateStore is null) throw new InvalidOperationException("Estado de distribuição indisponível.");
        var state = _distributionStateStore.Load();
        if (string.IsNullOrWhiteSpace(state.PreviousVersion) || string.IsNullOrWhiteSpace(state.PendingSource) || string.IsNullOrWhiteSpace(state.PendingChannel))
            throw new InvalidOperationException("Nenhuma versão anterior conhecida está disponível.");
        _store?.AppendLog($"Preparando rollback explícito para version={state.PreviousVersion} channel={state.PendingChannel}");
        var update = await DistributionUpdateService.PrepareSpecificVersionAsync(state.PendingSource, state.PendingChannel, state.PreviousVersion, _productMetadata);
        await DistributionUpdateService.DownloadAsync(update, null, _lifetime.Token);
        DistributionUpdateService.ApplyAndRestart(update, DistributionEnvironment.ResolveLocalRoot(), _distributionStateStore);
    }

    private async Task RunLoopAsync(BootstrapOptions options, CancellationToken cancellationToken)
    {
        var forceOneAttempt = false;
        while (!cancellationToken.IsCancellationRequested)
        {
            var state = _store!.Load();
            if (_policy.ShouldEnterRecovery(state, DateTimeOffset.UtcNow) && !forceOneAttempt)
            {
                var action = ShowRecovery(state.LastFailure ?? "O CloudOS falhou repetidamente durante a inicialização.");
                if (action == RecoveryAction.Rollback) { await RollbackAsync(); return; }
                if (action != RecoveryAction.Retry) { Shutdown(); return; }
                forceOneAttempt = true;
            }

            _supervisor = new BootstrapSupervisor();
            _supervisor.ReadinessReached += OnReadinessReached;
            _supervisor.StabilityReached += OnStabilityReached;
            _store.AppendLog("Iniciando CloudOS.Host sob supervisão.");

            HostRunResult result;
            try { result = await _supervisor.RunAsync(options, ReadinessTimeout, StabilityPeriod, cancellationToken); }
            finally
            {
                _supervisor.ReadinessReached -= OnReadinessReached;
                _supervisor.StabilityReached -= OnStabilityReached;
                await _supervisor.DisposeAsync();
                _supervisor = null;
            }

            forceOneAttempt = false;
            var now = DateTimeOffset.UtcNow;
            state = _store.Load();
            if (result.Ready && result.ExitCode == 0 && (result.Stable || options.AllowEarlyCleanExit))
            {
                _store.Save(_policy.RecordCleanExit(state, now, 0));
                _store.AppendLog("CloudOS.Host encerrou normalmente.");
                Shutdown(); return;
            }

            var reason = result.Failure ?? (result.Ready && result.ExitCode == 0
                ? "CloudOS.Host encerrou antes do período mínimo de estabilidade."
                : "CloudOS.Host encerrou inesperadamente.");
            state = _policy.RecordFailure(state, now, result.ExitCode, reason);
            _store.Save(state);
            _store.AppendLog($"Falha do host. ready={result.Ready} stable={result.Stable} exit={result.ExitCode?.ToString() ?? "n/a"} detail={reason}");
            if (_policy.ShouldEnterRecovery(state, now)) continue;
            await Task.Delay(_policy.RestartDelay(state, now), cancellationToken);
        }
    }

    private void OnReadinessReached(object? sender, EventArgs e)
    {
        var now = DateTimeOffset.UtcNow;
        _store!.Save(_policy.RecordReady(_store.Load(), now));
        _store.AppendLog("Handshake de prontidão confirmado.");
    }

    private void OnStabilityReached(object? sender, EventArgs e)
    {
        var now = DateTimeOffset.UtcNow;
        _store!.Save(_policy.RecordStable(_store.Load(), now));
        _distributionStateStore?.MarkHealthy(_productMetadata.Version);
        _store.AppendLog("Host permaneceu estável; contador de falhas foi zerado e a versão foi marcada saudável.");
    }

    private RecoveryAction ShowRecovery(string details)
    {
        var recovery = new RecoveryWindow(details, _store!.CurrentLogPath, _distributionStateStore?.CanRollback() == true);
        MainWindow = recovery; recovery.ShowDialog(); MainWindow = null;
        return recovery.SelectedAction;
    }

    protected override void OnSessionEnding(SessionEndingCancelEventArgs e)
    {
        _lifetime.Cancel(); base.OnSessionEnding(e); e.Cancel = false;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _lifetime.Cancel(); _instanceGuard?.Dispose(); _lifetime.Dispose(); base.OnExit(e);
    }
}
