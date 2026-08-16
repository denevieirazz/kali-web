using System.Diagnostics;
using System.IO;
using System.Windows;

namespace CloudOS.Bootstrap;

public enum RecoveryAction { Exit, Retry, Rollback }

public partial class RecoveryWindow : Window
{
    private readonly string _logPath;

    public RecoveryWindow(string details, string logPath, bool canRollback = false)
    {
        _logPath = logPath;
        InitializeComponent();
        FailureDetails.Text = string.IsNullOrWhiteSpace(details) ? "Falha de inicialização sem detalhes adicionais." : details;
        RollbackButton.IsEnabled = canRollback;
        RollbackButton.ToolTip = canRollback ? "Restaurar binários anteriores preservando dados." : "Nenhuma versão anterior conhecida está disponível para esta sessão.";
    }

    public RecoveryAction SelectedAction { get; private set; } = RecoveryAction.Exit;
    private void Retry_Click(object sender, RoutedEventArgs e) { SelectedAction = RecoveryAction.Retry; Close(); }
    private void Rollback_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show("Restaurar a versão anterior conhecida? Seus dados serão preservados.", "CloudOS Recovery", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        SelectedAction = RecoveryAction.Rollback; Close();
    }

    private void OpenLogs_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (!File.Exists(_logPath)) { MessageBox.Show("O arquivo de log ainda não existe.", "CloudOS", MessageBoxButton.OK, MessageBoxImage.Information); return; }
            var notepad = Path.Combine(Environment.SystemDirectory, "notepad.exe");
            Process.Start(new ProcessStartInfo { FileName = notepad, UseShellExecute = false, ArgumentList = { _logPath } });
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException)
        { MessageBox.Show($"Não foi possível abrir o log: {error.Message}", "CloudOS", MessageBoxButton.OK, MessageBoxImage.Error); }
    }
    private void Exit_Click(object sender, RoutedEventArgs e) { SelectedAction = RecoveryAction.Exit; Close(); }
}
