using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CloudOS.WslCore;

public sealed class WslCoreProtocolException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

internal sealed class WireError
{
    [JsonPropertyName("code")] public string? Code { get; init; }
    [JsonPropertyName("message")] public string? Message { get; init; }
}

internal sealed class WireEnvelope
{
    [JsonPropertyName("v")] public int Version { get; init; }
    [JsonPropertyName("type")] public string? Type { get; init; }
    [JsonPropertyName("id")] public string? Id { get; init; }
    [JsonPropertyName("ok")] public bool? Ok { get; init; }
    [JsonPropertyName("payload")] public JsonElement? Payload { get; init; }
    [JsonPropertyName("error")] public WireError? Error { get; init; }
}

internal static class WslCoreProtocol
{
    internal const int Version = 1;
    internal const int MaxFrameBytes = 1 << 20;
    internal const int NonceBytes = 32;
    internal const int SecretBytes = 32;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    internal static JsonElement Payload(object value) => JsonSerializer.SerializeToElement(value, JsonOptions);

    internal static async Task WriteFrameAsync(Stream stream, WireEnvelope envelope, CancellationToken cancellationToken)
    {
        var body = JsonSerializer.SerializeToUtf8Bytes(envelope, JsonOptions);
        if (body.Length is <= 0 or > MaxFrameBytes)
            throw new WslCoreProtocolException("FRAME_LIMIT", "Protocol frame size is invalid.");

        var header = new byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(header, checked((uint)body.Length));
        await stream.WriteAsync(header, cancellationToken);
        await stream.WriteAsync(body, cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }

    internal static async Task<WireEnvelope> ReadFrameAsync(Stream stream, CancellationToken cancellationToken)
    {
        var header = new byte[4];
        await ReadExactlyAsync(stream, header, cancellationToken);
        var size = BinaryPrimitives.ReadUInt32BigEndian(header);
        if (size is 0 or > MaxFrameBytes)
            throw new WslCoreProtocolException("FRAME_LIMIT", "Protocol frame size is invalid.");

        var body = new byte[checked((int)size)];
        await ReadExactlyAsync(stream, body, cancellationToken);
        WireEnvelope envelope;
        try
        {
            envelope = JsonSerializer.Deserialize<WireEnvelope>(body, JsonOptions)
                ?? throw new JsonException("empty envelope");
        }
        catch (JsonException error)
        {
            throw new WslCoreProtocolException("FRAME_INVALID", $"Protocol frame is invalid: {error.GetType().Name}.");
        }

        if (envelope.Version != Version)
            throw new WslCoreProtocolException("PROTOCOL_VERSION", "Protocol version is not supported.");
        if (string.IsNullOrWhiteSpace(envelope.Type))
            throw new WslCoreProtocolException("FRAME_INVALID", "Protocol frame type is missing.");
        return envelope;
    }

    internal static byte[] Proof(ReadOnlySpan<byte> secret, string role, ReadOnlySpan<byte> clientNonce, ReadOnlySpan<byte> serverNonce)
    {
        if (secret.Length != SecretBytes || clientNonce.Length != NonceBytes || serverNonce.Length != NonceBytes)
            throw new ArgumentException("Invalid authentication material length.");
        var prefix = Encoding.ASCII.GetBytes($"cloudos-core/v1/{role}");
        var message = new byte[prefix.Length + 1 + NonceBytes + NonceBytes];
        prefix.CopyTo(message, 0);
        clientNonce.CopyTo(message.AsSpan(prefix.Length + 1, NonceBytes));
        serverNonce.CopyTo(message.AsSpan(prefix.Length + 1 + NonceBytes, NonceBytes));
        using var hmac = new HMACSHA256(secret.ToArray());
        return hmac.ComputeHash(message);
    }

    internal static bool VerifyProof(ReadOnlySpan<byte> secret, string role, ReadOnlySpan<byte> clientNonce, ReadOnlySpan<byte> serverNonce, string? proof)
    {
        if (string.IsNullOrWhiteSpace(proof)) return false;
        byte[] candidate;
        try { candidate = Convert.FromBase64String(proof); }
        catch (FormatException) { return false; }
        try { return CryptographicOperations.FixedTimeEquals(candidate, Proof(secret, role, clientNonce, serverNonce)); }
        finally { CryptographicOperations.ZeroMemory(candidate); }
    }

    internal static async Task ReadExactlyAsync(Stream stream, Memory<byte> buffer, CancellationToken cancellationToken)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var read = await stream.ReadAsync(buffer[offset..], cancellationToken);
            if (read == 0) throw new EndOfStreamException("Protocol stream ended early.");
            offset += read;
        }
    }
}
