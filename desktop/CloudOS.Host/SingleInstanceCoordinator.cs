using System.IO.Pipes;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;

namespace CloudOS.Host;

public sealed class SingleInstanceCoordinator : IDisposable
{
    private readonly CancellationTokenSource _lifetime = new();
    private readonly string _pipeName;
    private readonly string _mutexName;
    private Mutex? _mutex;
    private bool _ownsMutex;

    public SingleInstanceCoordinator()
    {
        var sid = WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName;
        var suffix = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sid)))[..20];
        _mutexName = $"Local\\CloudOS.Host.{suffix}";
        _pipeName = $"CloudOS.Host.Activation.{suffix}";
    }

    public event EventHandler? ActivationRequested;

    public bool TryAcquire()
    {
        _mutex = new Mutex(true, _mutexName, out var createdNew);
        if (createdNew)
        {
            _ownsMutex = true;
            return true;
        }

        // O objeto nomeado pode continuar existindo por alguns instantes mesmo
        // depois de o antigo proprietário morrer. Nesse caso não há processo a
        // ativar, mas o mutex pode ser retomado imediatamente.
        try
        {
            _ownsMutex = _mutex.WaitOne(0);
        }
        catch (AbandonedMutexException)
        {
            _ownsMutex = true;
        }
        return _ownsMutex;
    }

    public void StartListening() => _ = ListenAsync(_lifetime.Token);

    public async Task<bool> SignalExistingAsync()
    {
        try
        {
            await using var client = new NamedPipeClientStream(".", _pipeName, PipeDirection.Out, PipeOptions.Asynchronous);
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(1));
            await client.ConnectAsync(timeout.Token);
            await client.WriteAsync("activate\n"u8.ToArray(), timeout.Token);
            await client.FlushAsync(timeout.Token);
            return true;
        }
        catch
        {
            return false;
        }
    }

    public static bool TryTerminateUnresponsiveHost(out string? error)
    {
        error = null;
        using var current = Process.GetCurrentProcess();
        Process[] candidates;
        try
        {
            var currentPath = current.MainModule?.FileName;
            if (string.IsNullOrWhiteSpace(currentPath)
                || current.ProcessName.Equals("dotnet", StringComparison.OrdinalIgnoreCase))
            {
                error = "A recuperação automática só é permitida no executável publicado CloudOS.Host.exe.";
                return false;
            }

            var matching = new List<Process>();
            foreach (var process in Process.GetProcessesByName(current.ProcessName))
            {
                try
                {
                    var sameExecutable = string.Equals(process.MainModule?.FileName, currentPath, StringComparison.OrdinalIgnoreCase);
                    if (process.Id != current.Id && process.SessionId == current.SessionId && sameExecutable)
                        matching.Add(process);
                    else
                        process.Dispose();
                }
                catch
                {
                    process.Dispose();
                }
            }
            candidates = matching.ToArray();
        }
        catch (Exception exception)
        {
            error = $"Não foi possível localizar a instância anterior: {exception.Message}";
            return false;
        }

        try
        {
            if (candidates.Length != 1)
            {
                error = candidates.Length == 0
                    ? "A instância anterior encerrou durante a recuperação. Tente abrir o CloudOS novamente."
                    : "Há mais de uma instância do CloudOS nesta sessão; use o script stop-cloudos.ps1 antes de reiniciar.";
                return false;
            }

            var candidate = candidates[0];
            if (candidate.HasExited) return true;
            if (candidate.CloseMainWindow() && candidate.WaitForExit(2000)) return true;
            candidate.Kill(entireProcessTree: false);
            if (candidate.WaitForExit(5000)) return true;
            error = "A instância anterior não encerrou dentro do tempo esperado.";
            return false;
        }
        catch (Exception exception)
        {
            error = $"Não foi possível reiniciar a instância anterior: {exception.Message}";
            return false;
        }
        finally
        {
            foreach (var candidate in candidates) candidate.Dispose();
        }
    }

    private async Task ListenAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await using var server = new NamedPipeServerStream(
                    _pipeName,
                    PipeDirection.In,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await server.WaitForConnectionAsync(cancellationToken);
                var buffer = new byte[32];
                var read = await server.ReadAsync(buffer, cancellationToken);
                if (Encoding.UTF8.GetString(buffer, 0, read).Trim() == "activate")
                    ActivationRequested?.Invoke(this, EventArgs.Empty);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                return;
            }
            catch
            {
                await Task.Delay(250, cancellationToken);
            }
        }
    }

    public void Dispose()
    {
        _lifetime.Cancel();
        if (_ownsMutex)
        {
            try { _mutex?.ReleaseMutex(); } catch (ApplicationException) { }
        }
        _mutex?.Dispose();
        _lifetime.Dispose();
    }
}
