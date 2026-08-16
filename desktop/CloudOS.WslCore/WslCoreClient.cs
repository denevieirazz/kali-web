using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json;

namespace CloudOS.WslCore;

public sealed class WslCoreClient : IAsyncDisposable
{
    private readonly TcpClient _tcp;
    private readonly NetworkStream _stream;
    private readonly SemaphoreSlim _requestGate = new(1, 1);
    private bool _disposed;

    private WslCoreClient(TcpClient tcp)
    {
        _tcp = tcp;
        _stream = tcp.GetStream();
    }

    public event EventHandler<WslCoreEvent>? EventReceived;

    public static async Task<WslCoreClient> ConnectAuthenticatedAsync(int port, byte[] secret, CancellationToken cancellationToken)
    {
        if (port is < 1 or > 65535) throw new ArgumentOutOfRangeException(nameof(port));
        if (secret.Length != WslCoreProtocol.SecretBytes) throw new ArgumentException("Invalid bootstrap secret.", nameof(secret));

        var tcp = new TcpClient(AddressFamily.InterNetwork) { NoDelay = true };
        try
        {
            await tcp.ConnectAsync(IPAddress.Loopback, port, cancellationToken);
            var client = new WslCoreClient(tcp);
            await client.AuthenticateAsync(secret, cancellationToken);
            return client;
        }
        catch
        {
            tcp.Dispose();
            throw;
        }
    }

    private async Task AuthenticateAsync(byte[] secret, CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(8));
        var clientNonce = RandomNumberGenerator.GetBytes(WslCoreProtocol.NonceBytes);
        byte[]? serverNonce = null;
        try
        {
            await WslCoreProtocol.WriteFrameAsync(_stream, new WireEnvelope
            {
                Version = WslCoreProtocol.Version,
                Type = "hello",
                Payload = WslCoreProtocol.Payload(new { clientNonce = Convert.ToBase64String(clientNonce) })
            }, timeout.Token);

            var challenge = await WslCoreProtocol.ReadFrameAsync(_stream, timeout.Token);
            if (challenge.Type != "challenge" || challenge.Payload is null)
                throw new WslCoreProtocolException("AUTH_FAILED", "Guest did not return an authentication challenge.");
            string? serverNonceText;
            string? serverProof;
            try
            {
                serverNonceText = challenge.Payload.Value.GetProperty("serverNonce").GetString();
                serverProof = challenge.Payload.Value.GetProperty("proof").GetString();
            }
            catch (Exception error) when (error is KeyNotFoundException or InvalidOperationException)
            {
                throw new WslCoreProtocolException("AUTH_FAILED", "Guest authentication challenge is malformed.");
            }
            try { serverNonce = Convert.FromBase64String(serverNonceText ?? string.Empty); }
            catch (FormatException) { throw new WslCoreProtocolException("AUTH_FAILED", "Guest nonce is invalid."); }
            if (serverNonce.Length != WslCoreProtocol.NonceBytes ||
                !WslCoreProtocol.VerifyProof(secret, "server", clientNonce, serverNonce, serverProof))
                throw new WslCoreProtocolException("AUTH_FAILED", "Guest authentication proof is invalid.");

            var clientProof = Convert.ToBase64String(WslCoreProtocol.Proof(secret, "client", clientNonce, serverNonce));
            await WslCoreProtocol.WriteFrameAsync(_stream, new WireEnvelope
            {
                Version = WslCoreProtocol.Version,
                Type = "proof",
                Payload = WslCoreProtocol.Payload(new { proof = clientProof })
            }, timeout.Token);
            var ready = await WslCoreProtocol.ReadFrameAsync(_stream, timeout.Token);
            if (ready.Type != "ready" || ready.Payload is null)
                throw new WslCoreProtocolException("AUTH_FAILED", "Guest did not complete mutual authentication.");
            int protocol;
            try { protocol = ready.Payload.Value.GetProperty("protocol").GetInt32(); }
            catch (Exception error) when (error is KeyNotFoundException or InvalidOperationException or FormatException)
            {
                throw new WslCoreProtocolException("AUTH_FAILED", "Guest ready message is malformed.");
            }
            if (protocol != WslCoreProtocol.Version)
                throw new WslCoreProtocolException("AUTH_FAILED", "Guest protocol version changed during authentication.");
        }
        finally
        {
            CryptographicOperations.ZeroMemory(clientNonce);
            if (serverNonce is not null) CryptographicOperations.ZeroMemory(serverNonce);
        }
    }

    public Task<WslCoreHealth> HealthAsync(CancellationToken cancellationToken = default) =>
        RequestAsync<WslCoreHealth>("health", null, TimeSpan.FromSeconds(5), cancellationToken);

    public Task<WslCoreMetrics> MetricsAsync(CancellationToken cancellationToken = default) =>
        RequestAsync<WslCoreMetrics>("metrics.get", null, TimeSpan.FromSeconds(5), cancellationToken);

    public Task<WslCoreSessionStatus> CreateSessionAsync(WslCoreCreateSession request, CancellationToken cancellationToken = default) =>
        RequestAsync<WslCoreSessionStatus>("session.create", new
        {
            executable = request.Executable,
            args = request.Args ?? Array.Empty<string>(),
            cwd = request.Cwd,
            env = request.Env,
            user = request.User,
            pty = request.Pty,
            cols = request.Cols,
            rows = request.Rows
        }, TimeSpan.FromSeconds(8), cancellationToken);

    public Task InputAsync(string sessionId, ReadOnlyMemory<byte> data, CancellationToken cancellationToken = default) =>
        RequestNoResultAsync("session.input", new { sessionId, data = Convert.ToBase64String(data.Span) }, TimeSpan.FromSeconds(5), cancellationToken);

    public Task ResizeAsync(string sessionId, int rows, int cols, CancellationToken cancellationToken = default) =>
        RequestNoResultAsync("session.resize", new { sessionId, rows, cols }, TimeSpan.FromSeconds(5), cancellationToken);

    public Task SignalAsync(string sessionId, string signal, CancellationToken cancellationToken = default) =>
        RequestNoResultAsync("session.signal", new { sessionId, signal }, TimeSpan.FromSeconds(5), cancellationToken);

    public Task<WslCoreSessionStatus> StatusAsync(string sessionId, CancellationToken cancellationToken = default) =>
        RequestAsync<WslCoreSessionStatus>("session.status", new { sessionId }, TimeSpan.FromSeconds(5), cancellationToken);

    public Task<WslCoreSessionStatus> WaitAsync(string sessionId, int timeoutMs = 8_000, CancellationToken cancellationToken = default) =>
        RequestAsync<WslCoreSessionStatus>("session.wait", new { sessionId, timeoutMs }, TimeSpan.FromMilliseconds(Math.Clamp(timeoutMs + 1500, 2500, 12_000)), cancellationToken);

    public Task ShutdownAsync(CancellationToken cancellationToken = default) =>
        RequestNoResultAsync("shutdown", null, TimeSpan.FromSeconds(5), cancellationToken);

    private async Task RequestNoResultAsync(string method, object? parameters, TimeSpan timeout, CancellationToken cancellationToken)
    {
        _ = await RequestAsync<JsonElement>(method, parameters, timeout, cancellationToken);
    }

    private async Task<T> RequestAsync<T>(string method, object? parameters, TimeSpan timeout, CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await _requestGate.WaitAsync(cancellationToken);
        try
        {
            using var bounded = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            bounded.CancelAfter(timeout);
            var id = Guid.NewGuid().ToString("N");
            await WslCoreProtocol.WriteFrameAsync(_stream, new WireEnvelope
            {
                Version = WslCoreProtocol.Version,
                Type = "request",
                Id = id,
                Payload = WslCoreProtocol.Payload(new { method, @params = parameters })
            }, bounded.Token);

            while (true)
            {
                var envelope = await WslCoreProtocol.ReadFrameAsync(_stream, bounded.Token);
                if (envelope.Type == "event")
                {
                    DispatchEvent(envelope);
                    continue;
                }
                if (envelope.Type != "response" || envelope.Id != id) continue;
                if (envelope.Ok != true)
                    throw new WslCoreProtocolException(envelope.Error?.Code ?? "REQUEST_FAILED", envelope.Error?.Message ?? "Guest request failed.");
                if (envelope.Payload is null)
                    return default!;
                return envelope.Payload.Value.Deserialize<T>() ?? default!;
            }
        }
        finally
        {
            _requestGate.Release();
        }
    }

    private void DispatchEvent(WireEnvelope envelope)
    {
        if (envelope.Payload is null) return;
        try
        {
            var value = envelope.Payload.Value.Deserialize<WslCoreEvent>();
            if (value is not null) EventReceived?.Invoke(this, value);
        }
        catch (JsonException) { }
    }

    public ValueTask DisposeAsync()
    {
        if (_disposed) return ValueTask.CompletedTask;
        _disposed = true;
        _stream.Dispose();
        _tcp.Dispose();
        _requestGate.Dispose();
        return ValueTask.CompletedTask;
    }
}
