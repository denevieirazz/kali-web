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

internal sealed class WslCoreSecureChannel : IAsyncDisposable
{
    private const int TagBytes = 16;
    private const int SequenceBytes = 8;
    private readonly Stream _readStream;
    private readonly Stream _writeStream;
    private readonly AesGcm _readAes;
    private readonly AesGcm _writeAes;
    private readonly byte[] _readPrefix;
    private readonly byte[] _writePrefix;
    private readonly string _readLabel;
    private readonly string _writeLabel;
    private readonly SemaphoreSlim _writeGate = new(1, 1);
    private ulong _readSequence;
    private ulong _writeSequence;
    private bool _disposed;

    private WslCoreSecureChannel(
        Stream readStream,
        Stream writeStream,
        AesGcm readAes,
        AesGcm writeAes,
        byte[] readPrefix,
        byte[] writePrefix,
        string readLabel,
        string writeLabel)
    {
        _readStream = readStream;
        _writeStream = writeStream;
        _readAes = readAes;
        _writeAes = writeAes;
        _readPrefix = readPrefix;
        _writePrefix = writePrefix;
        _readLabel = readLabel;
        _writeLabel = writeLabel;
    }

    internal static WslCoreSecureChannel Create(Stream readStream, Stream writeStream, ReadOnlySpan<byte> secret, ReadOnlySpan<byte> clientNonce, ReadOnlySpan<byte> serverNonce, bool serverSide)
    {
        var material = WslCoreProtocol.DeriveChannelMaterial(secret, clientNonce, serverNonce);
        try
        {
            var c2s = new AesGcm(material.ClientToServerKey, TagBytes);
            var s2c = new AesGcm(material.ServerToClientKey, TagBytes);
            return serverSide
                ? new WslCoreSecureChannel(readStream, writeStream, c2s, s2c, material.ClientToServerPrefix, material.ServerToClientPrefix, "c2s", "s2c")
                : new WslCoreSecureChannel(readStream, writeStream, s2c, c2s, material.ServerToClientPrefix, material.ClientToServerPrefix, "s2c", "c2s");
        }
        finally
        {
            CryptographicOperations.ZeroMemory(material.ClientToServerKey);
            CryptographicOperations.ZeroMemory(material.ServerToClientKey);
        }
    }

    internal async Task WriteAsync(WireEnvelope envelope, CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await _writeGate.WaitAsync(cancellationToken);
        try
        {
            if (_writeSequence == ulong.MaxValue)
                throw new WslCoreProtocolException("FRAME_SEQUENCE", "Protected frame sequence is exhausted.");
            var sequence = _writeSequence + 1;
            var body = JsonSerializer.SerializeToUtf8Bytes(envelope, WslCoreProtocol.JsonOptions);
            if (body.Length is <= 0 or > WslCoreProtocol.MaxFrameBytes)
                throw new WslCoreProtocolException("FRAME_LIMIT", "Protocol frame size is invalid.");

            var nonce = WslCoreProtocol.MakeNonce(_writePrefix, sequence);
            var aad = WslCoreProtocol.MakeAad(_writeLabel, sequence);
            var ciphertext = new byte[body.Length];
            var tag = new byte[TagBytes];
            _writeAes.Encrypt(nonce, body, ciphertext, tag, aad);

            var protectedBody = new byte[SequenceBytes + ciphertext.Length + tag.Length];
            BinaryPrimitives.WriteUInt64BigEndian(protectedBody.AsSpan(0, SequenceBytes), sequence);
            ciphertext.CopyTo(protectedBody.AsSpan(SequenceBytes));
            tag.CopyTo(protectedBody.AsSpan(SequenceBytes + ciphertext.Length));
            await WslCoreProtocol.WriteLengthPrefixedAsync(_writeStream, protectedBody, cancellationToken);
            _writeSequence = sequence;
        }
        finally
        {
            _writeGate.Release();
        }
    }

    internal async Task<WireEnvelope> ReadAsync(CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var max = WslCoreProtocol.MaxFrameBytes + SequenceBytes + TagBytes;
        var protectedBody = await WslCoreProtocol.ReadLengthPrefixedAsync(_readStream, max, cancellationToken);
        if (protectedBody.Length < SequenceBytes + TagBytes)
            throw new WslCoreProtocolException("FRAME_INTEGRITY", "Protected frame is truncated.");

        var sequence = BinaryPrimitives.ReadUInt64BigEndian(protectedBody.AsSpan(0, SequenceBytes));
        if (_readSequence == ulong.MaxValue || sequence != _readSequence + 1)
            throw new WslCoreProtocolException("FRAME_SEQUENCE", "Protected frame sequence is invalid.");

        var cipherLength = protectedBody.Length - SequenceBytes - TagBytes;
        var ciphertext = protectedBody.AsSpan(SequenceBytes, cipherLength);
        var tag = protectedBody.AsSpan(SequenceBytes + cipherLength, TagBytes);
        var nonce = WslCoreProtocol.MakeNonce(_readPrefix, sequence);
        var aad = WslCoreProtocol.MakeAad(_readLabel, sequence);
        var plaintext = new byte[cipherLength];
        try
        {
            _readAes.Decrypt(nonce, ciphertext, tag, plaintext, aad);
        }
        catch (CryptographicException)
        {
            throw new WslCoreProtocolException("FRAME_INTEGRITY", "Protected frame authentication failed.");
        }
        var envelope = WslCoreProtocol.DecodeEnvelope(plaintext);
        _readSequence = sequence;
        return envelope;
    }

    public ValueTask DisposeAsync()
    {
        if (_disposed) return ValueTask.CompletedTask;
        _disposed = true;
        _readAes.Dispose();
        if (!ReferenceEquals(_readAes, _writeAes)) _writeAes.Dispose();
        CryptographicOperations.ZeroMemory(_readPrefix);
        CryptographicOperations.ZeroMemory(_writePrefix);
        _writeGate.Dispose();
        return ValueTask.CompletedTask;
    }
}

internal sealed record WslCoreChannelMaterial(byte[] ClientToServerKey, byte[] ServerToClientKey, byte[] ClientToServerPrefix, byte[] ServerToClientPrefix);

internal static class WslCoreProtocol
{
    internal const int Version = 2;
    internal const int MaxFrameBytes = 1 << 20;
    internal const int NonceBytes = 32;
    internal const int SecretBytes = 32;
    internal static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    internal static JsonElement Payload(object value) => JsonSerializer.SerializeToElement(value, JsonOptions);

    internal static async Task WriteFrameAsync(Stream stream, WireEnvelope envelope, CancellationToken cancellationToken)
    {
        var body = JsonSerializer.SerializeToUtf8Bytes(envelope, JsonOptions);
        if (body.Length is <= 0 or > MaxFrameBytes)
            throw new WslCoreProtocolException("FRAME_LIMIT", "Protocol frame size is invalid.");
        await WriteLengthPrefixedAsync(stream, body, cancellationToken);
    }

    internal static async Task<WireEnvelope> ReadFrameAsync(Stream stream, CancellationToken cancellationToken)
    {
        var body = await ReadLengthPrefixedAsync(stream, MaxFrameBytes, cancellationToken);
        return DecodeEnvelope(body);
    }

    internal static WireEnvelope DecodeEnvelope(ReadOnlySpan<byte> body)
    {
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
        var prefix = Encoding.ASCII.GetBytes($"cloudos-core/v2/{role}");
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

    internal static WslCoreChannelMaterial DeriveChannelMaterial(ReadOnlySpan<byte> secret, ReadOnlySpan<byte> clientNonce, ReadOnlySpan<byte> serverNonce)
    {
        if (secret.Length != SecretBytes || clientNonce.Length != NonceBytes || serverNonce.Length != NonceBytes)
            throw new ArgumentException("Invalid secure channel material length.");

        var prefix = Encoding.ASCII.GetBytes("cloudos-core/v2/hkdf-salt");
        var context = new byte[prefix.Length + 1 + clientNonce.Length + serverNonce.Length];
        prefix.CopyTo(context, 0);
        clientNonce.CopyTo(context.AsSpan(prefix.Length + 1, clientNonce.Length));
        serverNonce.CopyTo(context.AsSpan(prefix.Length + 1 + clientNonce.Length, serverNonce.Length));
        var salt = SHA256.HashData(context);
        byte[] prk;
        using (var extract = new HMACSHA256(salt)) prk = extract.ComputeHash(secret.ToArray());
        try
        {
            return new WslCoreChannelMaterial(
                HkdfExpand(prk, "cloudos-core/v2/c2s/key", 32),
                HkdfExpand(prk, "cloudos-core/v2/s2c/key", 32),
                HkdfExpand(prk, "cloudos-core/v2/c2s/nonce", 4),
                HkdfExpand(prk, "cloudos-core/v2/s2c/nonce", 4));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(prk);
            CryptographicOperations.ZeroMemory(salt);
        }
    }

    internal static byte[] HkdfExpand(ReadOnlySpan<byte> prk, string info, int length)
    {
        if (length <= 0 || length > 255 * 32) throw new ArgumentOutOfRangeException(nameof(length));
        var infoBytes = Encoding.ASCII.GetBytes(info);
        var output = new byte[length];
        var previous = Array.Empty<byte>();
        var offset = 0;
        byte counter = 1;
        while (offset < length)
        {
            using var hmac = new HMACSHA256(prk.ToArray());
            var input = new byte[previous.Length + infoBytes.Length + 1];
            previous.CopyTo(input, 0);
            infoBytes.CopyTo(input, previous.Length);
            input[^1] = counter++;
            var block = hmac.ComputeHash(input);
            if (previous.Length > 0) CryptographicOperations.ZeroMemory(previous);
            previous = block;
            var take = Math.Min(block.Length, length - offset);
            block.AsSpan(0, take).CopyTo(output.AsSpan(offset, take));
            offset += take;
        }
        if (previous.Length > 0) CryptographicOperations.ZeroMemory(previous);
        return output;
    }

    internal static byte[] MakeNonce(ReadOnlySpan<byte> prefix, ulong sequence)
    {
        if (prefix.Length != 4) throw new ArgumentException("Invalid nonce prefix.", nameof(prefix));
        var nonce = new byte[12];
        prefix.CopyTo(nonce.AsSpan(0, 4));
        BinaryPrimitives.WriteUInt64BigEndian(nonce.AsSpan(4), sequence);
        return nonce;
    }

    internal static byte[] MakeAad(string direction, ulong sequence)
    {
        var prefix = Encoding.ASCII.GetBytes($"cloudos-core/v2/secure/{direction}");
        var aad = new byte[prefix.Length + 1 + 8];
        prefix.CopyTo(aad, 0);
        BinaryPrimitives.WriteUInt64BigEndian(aad.AsSpan(prefix.Length + 1), sequence);
        return aad;
    }

    internal static async Task WriteLengthPrefixedAsync(Stream stream, ReadOnlyMemory<byte> body, CancellationToken cancellationToken)
    {
        var header = new byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(header, checked((uint)body.Length));
        await stream.WriteAsync(header, cancellationToken);
        await stream.WriteAsync(body, cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }

    internal static async Task<byte[]> ReadLengthPrefixedAsync(Stream stream, int maxBytes, CancellationToken cancellationToken)
    {
        var header = new byte[4];
        await ReadExactlyAsync(stream, header, cancellationToken);
        var size = BinaryPrimitives.ReadUInt32BigEndian(header);
        if (size == 0 || size > (uint)maxBytes)
            throw new WslCoreProtocolException("FRAME_LIMIT", "Protocol frame size is invalid.");
        var body = new byte[checked((int)size)];
        await ReadExactlyAsync(stream, body, cancellationToken);
        return body;
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
