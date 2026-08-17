using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace CloudOS.Bootstrap;

public sealed class UpdateWindow : Window
{
    private readonly string _source;
    private readonly string? _channel;
    private readonly ProductMetadata _metadata;
    private readonly string _localRoot;
    private readonly DistributionStateStore _stateStore;
    private readonly TextBlock _status = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) };
    private readonly ProgressBar _progress = new() { Minimum = 0, Maximum = 100, Height = 16, Margin = new Thickness(0, 0, 0, 12) };
    private readonly Button _download = new() { Content = "Baixar", IsEnabled = false, MinWidth = 90, Margin = new Thickness(6) };
    private readonly Button _apply = new() { Content = "Aplicar e reiniciar", IsEnabled = false, MinWidth = 130, Margin = new Thickness(6) };
    private CancellationTokenSource? _downloadCancellation;
    private PreparedUpdate? _prepared;

    public UpdateWindow(string source, string? channel, ProductMetadata metadata, string localRoot)
    {
        _source = source; _channel = channel; _metadata = metadata; _localRoot = localRoot;
        _stateStore = new DistributionStateStore(localRoot);
        _stateStore.AssertPackageChannel(DistributionChannelPolicy.Load(metadata.Root), metadata.Channel);
        Title = "CloudOS — Atualizações";
        Width = 620; Height = 340; ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = new SolidColorBrush(Color.FromRgb(8, 13, 24)); Foreground = Brushes.White;
        var body = new StackPanel { Margin = new Thickness(28) }; Content = body;
        body.Children.Add(new TextBlock { Text = "Atualização controlada", FontSize = 26, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0,0,0,8) });
        body.Children.Add(new TextBlock { Text = "O CloudOS valida canal, versão, origem e SHA-256 antes de preparar uma atualização. Preview/stable permanecem bloqueados enquanto assinatura e origens oficiais não estiverem configuradas.", Opacity=.78, TextWrapping=TextWrapping.Wrap, Margin=new Thickness(0,0,0,16) });
        body.Children.Add(_status); body.Children.Add(_progress);
        var row = new StackPanel { Orientation=Orientation.Horizontal, HorizontalAlignment=HorizontalAlignment.Right };
        var check = new Button { Content="Verificar", MinWidth=90, Margin=new Thickness(6) };
        var cancel = new Button { Content="Cancelar download", MinWidth=120, Margin=new Thickness(6) };
        var close = new Button { Content="Fechar", MinWidth=80, Margin=new Thickness(6) };
        row.Children.Add(check); row.Children.Add(_download); row.Children.Add(cancel); row.Children.Add(_apply); row.Children.Add(close); body.Children.Add(row);
        check.Click += async (_,_) => await CheckAsync(check);
        _download.Click += async (_,_) => await DownloadAsync();
        cancel.Click += (_,_) => _downloadCancellation?.Cancel();
        _apply.Click += (_,_) => Apply();
        close.Click += (_,_) => Close();
        Loaded += async (_,_) => await CheckAsync(check);
    }

    private async Task CheckAsync(Button check)
    {
        check.IsEnabled=false; _download.IsEnabled=false; _apply.IsEnabled=false; _prepared=null; _progress.Value=0;
        _status.Text="Verificando feed...";
        try
        {
            _prepared=await DistributionUpdateService.CheckAsync(_source,_channel,_metadata,_stateStore);
            if(_prepared is null){_status.Text="Nenhuma atualização disponível.";return;}
            _status.Text=$"Versão {_prepared.Version} disponível no canal {_prepared.Channel}.\nSHA-256: {_prepared.Sha256}";
            _download.IsEnabled=true;
        }
        catch(Exception error){_status.Text=$"Não foi possível verificar: {error.Message}";}
        finally{check.IsEnabled=true;}
    }

    private async Task DownloadAsync()
    {
        if(_prepared is null)return;
        _download.IsEnabled=false; _downloadCancellation?.Dispose(); _downloadCancellation=new CancellationTokenSource(); _status.Text="Baixando e validando pacote...";
        try
        {
            await DistributionUpdateService.DownloadAsync(_prepared, value => Dispatcher.Invoke(()=>_progress.Value=value), _downloadCancellation.Token);
            _progress.Value=100; _status.Text=$"Pacote {_prepared.Version} baixado e validado. Reinicie para aplicar."; _apply.IsEnabled=true;
        }
        catch(OperationCanceledException){_status.Text="Download cancelado. Nenhuma atualização foi aplicada.";_download.IsEnabled=true;}
        catch(Exception error){_status.Text=$"Pacote rejeitado: {error.Message}";_download.IsEnabled=true;}
    }

    private void Apply()
    {
        if(_prepared is null)return;
        if(MessageBox.Show("O CloudOS será reiniciado para aplicar a atualização. Continuar?","CloudOS",MessageBoxButton.YesNo,MessageBoxImage.Question)!=MessageBoxResult.Yes)return;
        DistributionUpdateService.ApplyAndRestart(_prepared,_localRoot,_stateStore);
    }

    protected override void OnClosed(EventArgs e){_downloadCancellation?.Cancel();_downloadCancellation?.Dispose();base.OnClosed(e);}
}
