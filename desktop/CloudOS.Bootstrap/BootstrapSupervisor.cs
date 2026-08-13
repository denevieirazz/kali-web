using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CloudOS.Bootstrap;

public sealed record HostRunResult(
    bool Ready,
    bool Stable,
    int? ExitCode,
    string? Failure,
    DateTimeOffset StartedAtUtc,
    DateTimeOffset? ReadyAtUtc,
    DateTimeOffset ExitedAtUtc);

public sealed class BootstrapSupervisor : IAsyncDisposable
{
    private Process? _process;
    private bool _disposed;

    public event EventHandler? ReadinessReached;
    public event EventHandler? StabilityReached;

    public async Task<HostRunResult> RunAsync(
        BootstrapOptions options,
        TimeSpan readinessTimeout,
        TimeSpan stabilityPeriod,
        CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_process is not null) throw new InvalidOperationException("CloudOS.Host já está sob supervisão.");
        if (readinessTimeout < TimeSpan.FromSeconds(5) || readinessTimeout > TimeSpan.FromMinutes(3))
            throw new ArgumentOutOfRangeException(nameof(readinessTimeout));
        if (stabilityPeriod < TimeSpan.FromSeconds(10) || stabilityPeriod > TimeSpan.FromMinutes(10))
            throw new ArgumentOutOfRangeException(nameof(stabilityPeriod));

        var startedAt = DateTimeOffset.UtcNow;
        var pipeName = $"CloudOS.Bootstrap.Ready.{Guid.NewGuid():N}";
        await using var pipe = new NamedPipeServerStream(
            pipeName,
            PipeDirection.In,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);

        var startInfo = new ProcessStartInfo
        {
            FileName = options.HostPath,
            WorkingDirectory = Path.GetDirectoryName(options.HostPath)!,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        foreach (var argument in options.HostArguments) startInfo.ArgumentList.Add(argument);
        startInfo.ArgumentList.Add("--bootstrap-pipe");
        startInfo.ArgumentList.Add(pipeName);

        var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        _process = process;
        try
        {
            if (!process.Start())
            {
                process.Dispose();
                _process = null;
                return FailureResult("CloudOS.Host.exe recusou a inicialização.", startedAt, null);
            }
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            process.Dispose();
            _process = null;
            return FailureResult($"CloudOS.Host.exe não iniciou: {error.Message}", startedAt, null);
        }

        DateTimeOffset? readyAt = null;
        var stable = false;
        try
        {
            var readinessFailure = await WaitForReadinessAsync(pipe, process, readinessTimeout, cancellationToken);
            if (readinessFailure is not null)
            {
                await StopProcessAsync(CancellationToken.None);
                return FailureResult(readinessFailure, startedAt, SafeExitCode(process));
            }

            readyAt = DateTimeOffset.UtcNow;
            Notify(ReadinessReached);

            var exitTask = process.WaitForExitAsync(cancellationToken);
            var stabilityTask = Task.Delay(stabilityPeriod, cancellationToken);
            if (await Task.WhenAny(exitTask, stabilityTask) == stabilityTask)
            {
                await stabilityTask;
                stable = true;
                Notify(StabilityReached);
                await exitTask;
            }
            else
            {
                await exitTask;
            }

            var exitCode = SafeExitCode(process);
            return new HostRunResult(
                true,
                stable,
                exitCode,
                exitCode == 0 ? null : $"CloudOS.Host encerrou com código {exitCode}.",
                startedAt,
                readyAt,
                DateTimeOffset.UtcNow);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            await StopProcessAsync(CancellationToken.None);
            throw;
        }
        finally
        {
            try
            {
                if (process.HasExited)
                {
                    process.Dispose();
                    if (ReferenceEquals(_process, process)) _process = null;
                }
            }
            catch (InvalidOperationException)
            {
                if (ReferenceEquals(_process, process)) _process = null;
            }
        }
    }

    public async Task StopProcessAsync(CancellationToken cancellationToken)
    {
        var process = _process;
        if (process is null) return;

        try
        {
            if (!process.HasExited && process.MainWindowHandle != IntPtr.Zero) process.CloseMainWindow();
        }
        catch (InvalidOperationException) { }

        if (!process.HasExited)
        {
            try
            {
                using var graceful = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                graceful.CancelAfter(TimeSpan.FromSeconds(3));
                await process.WaitForExitAsync(graceful.Token);
            }
            catch (OperationCanceledException)
            {
                // Kill only the exact host object started here. Applications launched
                // from CloudOS may legitimately outlive a shell restart.
                if (!process.HasExited) process.Kill(entireProcessTree: false);
            }
        }

        if (!process.HasExited)
        {
            using var forced = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            forced.CancelAfter(TimeSpan.FromSeconds(5));
            try { await process.WaitForExitAsync(forced.Token); } catch (OperationCanceledException) { }
        }

        if (process.HasExited)
        {
            process.Dispose();
            if (ReferenceEquals(_process, process)) _process = null;
        }
    }

    private static async Task<string?> WaitForReadinessAsync(
        NamedPipeServerStream pipe,
        Process process,
        TimeSpan readinessTimeout,
        CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(readinessTimeout);
        var connectTask = pipe.WaitForConnectionAsync(timeout.Token);
        var exitTask = process.WaitForExitAsync(cancellationToken);
        var completed = await Task.WhenAny(connectTask, exitTask);
        cancellationToken.ThrowIfCancellationRequested();

        if (completed == exitTask)
        {
            timeout.Cancel();
            try { await connectTask; } catch (OperationCanceledException) { }
            return $"CloudOS.Host encerrou antes de sinalizar prontidão (código {SafeExitCode(process)}).";
        }

        try
        {
            await connectTask;
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return "CloudOS.Host excedeu o tempo limite para sinalizar prontidão.";
        }

        using var readTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        readTimeout.CancelAfter(TimeSpan.FromSeconds(3));
        using var payload = new MemoryStream();
        var buffer = new byte[256];
        try
        {
            while (payload.Length <= 1_024)
            {
                var count = await pipe.ReadAsync(buffer, readTimeout.Token);
                if (count == 0) break;
                payload.Write(buffer, 0, count);
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return "O sinal de prontidão do host ficou incompleto.";
        }
        if (payload.Length is 0 or > 1_024) return "O sinal de prontidão do host é inválido.";

        try
        {
            var message = JsonSerializer.Deserialize<ReadinessMessage>(payload.ToArray());
            if (message?.Protocol != 1 || message.Event != "ready" || message.Pid != process.Id)
                return "A identidade do sinal de prontidão não corresponde ao host iniciado.";
        }
        catch (JsonException)
        {
            return "O sinal de prontidão do host não contém JSON válido.";
        }
        return null;
    }

    private static HostRunResult FailureResult(string failure, DateTimeOffset startedAt, int? exitCode) =>
        new(false, false, exitCode, failure, startedAt, null, DateTimeOffset.UtcNow);

    private static int? SafeExitCode(Process process)
    {
        try { return process.HasExited ? process.ExitCode : null; } catch (InvalidOperationException) { return null; }
    }

    private void Notify(EventHandler? handler)
    {
        if (handler is null) return;
        try { handler(this, EventArgs.Empty); } catch { }
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        await StopProcessAsync(CancellationToken.None);
        _disposed = true;
    }

    private sealed class ReadinessMessage
    {
        [JsonPropertyName("protocol")] public int Protocol { get; init; }
        [JsonPropertyName("event")] public string? Event { get; init; }
        [JsonPropertyName("pid")] public int Pid { get; init; }
    }
}
