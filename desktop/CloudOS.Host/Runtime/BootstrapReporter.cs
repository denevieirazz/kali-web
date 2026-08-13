using System.IO;
using System.IO.Pipes;
using System.Text.Json;

namespace CloudOS.Host.Runtime;

/// <summary>
/// Optional, one-shot readiness channel used by CloudOS.Bootstrap. The random pipe
/// name is supplied on the command line by the parent process and is never exposed
/// to the web document.
/// </summary>
public sealed class BootstrapReporter(string? pipeName) : IDisposable
{
    private readonly CancellationTokenSource _lifetime = new();
    // 0 = disponível, 1 = enviando, 2 = confirmado. Uma falha transitória volta
    // para 0 para que um novo documento/handshake possa tentar novamente.
    private int _reportState;
    private int _disposed;

    public async Task ReportReadyAsync()
    {
        if (string.IsNullOrWhiteSpace(pipeName) || Volatile.Read(ref _disposed) != 0 ||
            Interlocked.CompareExchange(ref _reportState, 1, 0) != 0) return;

        try
        {
            await using var client = new NamedPipeClientStream(
                ".",
                pipeName,
                PipeDirection.Out,
                PipeOptions.Asynchronous,
                System.Security.Principal.TokenImpersonationLevel.Anonymous);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
            timeout.CancelAfter(TimeSpan.FromSeconds(3));
            await client.ConnectAsync(timeout.Token);
            var payload = JsonSerializer.SerializeToUtf8Bytes(new
            {
                protocol = 1,
                @event = "ready",
                pid = Environment.ProcessId
            });
            await client.WriteAsync(payload, timeout.Token);
            await client.FlushAsync(timeout.Token);
            Volatile.Write(ref _reportState, 2);
        }
        catch (Exception error) when (error is IOException or OperationCanceledException or UnauthorizedAccessException or ObjectDisposedException)
        {
            // Readiness reporting is advisory. Failure must not take down the shell.
            if (Volatile.Read(ref _disposed) == 0) Volatile.Write(ref _reportState, 0);
        }
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
        _lifetime.Cancel();
        _lifetime.Dispose();
    }
}
