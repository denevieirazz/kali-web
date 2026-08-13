using System.IO.Pipes;
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
        try
        {
            _mutex = new Mutex(true, _mutexName, out var createdNew);
            if (createdNew)
            {
                _ownsMutex = true;
                return true;
            }

            if (_mutex.WaitOne(0, false))
            {
                _ownsMutex = true;
                return true;
            }

            return false;
        }
        catch (AbandonedMutexException)
        {
            _ownsMutex = true;
            return true;
        }
        catch
        {
            return true;
        }
    }

    public void StartListening() => _ = ListenAsync(_lifetime.Token);

    public async Task SignalExistingAsync()
    {
        try
        {
            await using var client = new NamedPipeClientStream(".", _pipeName, PipeDirection.Out, PipeOptions.Asynchronous);
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(1));
            await client.ConnectAsync(timeout.Token);
            await client.WriteAsync("activate\n"u8.ToArray(), timeout.Token);
            await client.FlushAsync(timeout.Token);
        }
        catch
        {
            // A outra instância pode estar encerrando. Não há PID a matar nem estado a reparar aqui.
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
