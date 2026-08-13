using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Win32.SafeHandles;

namespace CloudOS.Host.Runtime;

/// <summary>
/// Owns a private, per-run pipe whose lifetime is tied to CloudOS.Host. The
/// backend keeps the client side open and therefore observes an OS-enforced
/// disconnect even when the host crashes or is terminated abruptly.
/// </summary>
internal sealed class RuntimeLeaseServer : IDisposable
{
    internal const int ProtocolVersion = 1;
    internal const string PipeEnvironmentVariable = "CLOUDOS_HOST_LEASE_PIPE";
    internal const string TokenEnvironmentVariable = "CLOUDOS_HOST_LEASE_TOKEN";
    private const string HandshakeType = "cloudos-runtime-lease";
    private const string AcceptedType = "cloudos-runtime-lease-accepted";
    private const int MaximumHandshakeBytes = 4_096;

    private readonly NamedPipeServerStream _pipe;
    private readonly byte[] _tokenBytes;
    private int _disposed;

    private RuntimeLeaseServer(string pipeName, byte[] tokenBytes)
    {
        PipeName = pipeName;
        _tokenBytes = tokenBytes;
        Token = Convert.ToBase64String(tokenBytes);
        _pipe = new NamedPipeServerStream(
            pipeName,
            PipeDirection.InOut,
            maxNumberOfServerInstances: 1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly,
            inBufferSize: MaximumHandshakeBytes,
            outBufferSize: 1_024);
    }

    public string PipeName { get; }

    public string Token { get; }

    public static RuntimeLeaseServer Create()
    {
        var suffix = Convert.ToHexString(RandomNumberGenerator.GetBytes(24));
        return new RuntimeLeaseServer($"CloudOS.Runtime.Lease.{suffix}", RandomNumberGenerator.GetBytes(48));
    }

    public async Task AcceptAuthenticatedClientAsync(
        Process childProcess,
        string runId,
        CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref _disposed) != 0, this);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));

        await _pipe.WaitForConnectionAsync(timeout.Token);

        if (!GetNamedPipeClientProcessId(_pipe.SafePipeHandle, out var actualClientProcessId) ||
            actualClientProcessId != (uint)childProcess.Id)
        {
            throw new InvalidOperationException("A lease do runtime foi aberta por um processo inesperado.");
        }

        var line = await ReadBoundedLineAsync(_pipe, timeout.Token);
        RuntimeLeaseHandshake handshake;
        try
        {
            handshake = JsonSerializer.Deserialize<RuntimeLeaseHandshake>(line)
                ?? throw new InvalidOperationException("O handshake da lease está vazio.");
        }
        catch (JsonException error)
        {
            throw new InvalidOperationException("O handshake da lease é inválido.", error);
        }

        if (handshake.Protocol != ProtocolVersion ||
            !string.Equals(handshake.Type, HandshakeType, StringComparison.Ordinal) ||
            handshake.Pid != childProcess.Id ||
            !string.Equals(handshake.RunId, runId, StringComparison.Ordinal) ||
            !TokenMatches(handshake.Token))
        {
            throw new InvalidOperationException("A identidade apresentada pela lease do runtime é inválida.");
        }

        var acknowledgement = JsonSerializer.SerializeToUtf8Bytes(new RuntimeLeaseAcknowledgement
        {
            Protocol = ProtocolVersion,
            Type = AcceptedType,
            RunId = runId,
            HostPid = Environment.ProcessId
        });
        await _pipe.WriteAsync(acknowledgement, timeout.Token);
        await _pipe.WriteAsync("\n"u8.ToArray(), timeout.Token);
        await _pipe.FlushAsync(timeout.Token);
    }

    private bool TokenMatches(string? candidate)
    {
        if (string.IsNullOrWhiteSpace(candidate)) return false;

        byte[] candidateBytes;
        try
        {
            candidateBytes = Convert.FromBase64String(candidate);
        }
        catch (FormatException)
        {
            return false;
        }

        try
        {
            return candidateBytes.Length == _tokenBytes.Length &&
                   CryptographicOperations.FixedTimeEquals(candidateBytes, _tokenBytes);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(candidateBytes);
        }
    }

    private static async Task<string> ReadBoundedLineAsync(Stream stream, CancellationToken cancellationToken)
    {
        using var buffer = new MemoryStream(capacity: 512);
        var singleByte = new byte[1];
        while (buffer.Length < MaximumHandshakeBytes)
        {
            var read = await stream.ReadAsync(singleByte, cancellationToken);
            if (read == 0) throw new EndOfStreamException("A lease foi fechada antes do handshake.");
            if (singleByte[0] == (byte)'\n')
            {
                var bytes = buffer.ToArray();
                if (bytes.Length > 0 && bytes[^1] == (byte)'\r') bytes = bytes[..^1];
                return new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true)
                    .GetString(bytes);
            }
            buffer.WriteByte(singleByte[0]);
        }

        throw new InvalidDataException("O handshake da lease excedeu o limite permitido.");
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
        _pipe.Dispose();
        CryptographicOperations.ZeroMemory(_tokenBytes);
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe, out uint clientProcessId);

    private sealed class RuntimeLeaseHandshake
    {
        [JsonPropertyName("protocol")] public int Protocol { get; init; }
        [JsonPropertyName("type")] public string? Type { get; init; }
        [JsonPropertyName("pid")] public int Pid { get; init; }
        [JsonPropertyName("runId")] public string? RunId { get; init; }
        [JsonPropertyName("token")] public string? Token { get; init; }
    }

    private sealed class RuntimeLeaseAcknowledgement
    {
        [JsonPropertyName("protocol")] public int Protocol { get; init; }
        [JsonPropertyName("type")] public string? Type { get; init; }
        [JsonPropertyName("runId")] public string? RunId { get; init; }
        [JsonPropertyName("hostPid")] public int HostPid { get; init; }
    }
}
