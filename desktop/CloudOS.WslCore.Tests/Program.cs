using System.Buffers.Binary;
using CloudOS.WslCore;

var failures = new List<string>();
await Run("framing-partial-invalid-version", TestFramingAsync);
await Run("mutual-auth-proof-role", TestProofAsync);
await Run("protected-channel-integrity-replay-sequence", TestSecureChannelAsync);
await Run("arguments-and-environment", TestBootstrapArgumentsAsync);
await Run("distro-validation-and-fallback", TestDistroAndFallbackAsync);
await Run("disconnect-and-timeout", TestDisconnectAndTimeoutAsync);

if (failures.Count > 0)
{
    foreach (var failure in failures) Console.Error.WriteLine($"FAIL {failure}");
    return 1;
}
Console.WriteLine("PASS CloudOS WSL core Windows contracts");
return 0;

async Task Run(string name, Func<Task> test)
{
    try { await test(); Console.WriteLine($"PASS {name}"); }
    catch (Exception error) { failures.Add($"{name}: {error.GetType().Name} {error.Message}"); }
}

static async Task TestFramingAsync()
{
    await using var memory = new MemoryStream();
    await WslCoreProtocol.WriteFrameAsync(memory, new WireEnvelope
    {
        Version = WslCoreProtocol.Version,
        Type = "hello",
        Id = "abc",
        Payload = WslCoreProtocol.Payload(new { method = "health" })
    }, CancellationToken.None);
    memory.Position = 0;
    await using var chunked = new ChunkedReadStream(memory, 1);
    var decoded = await WslCoreProtocol.ReadFrameAsync(chunked, CancellationToken.None);
    Assert(decoded.Type == "hello" && decoded.Id == "abc", "partial frame changed");

    var invalid = new byte[5];
    BinaryPrimitives.WriteUInt32BigEndian(invalid.AsSpan(0, 4), (uint)(WslCoreProtocol.MaxFrameBytes + 1));
    await using var invalidStream = new MemoryStream(invalid);
    await AssertThrowsAsync<WslCoreProtocolException>(() => WslCoreProtocol.ReadFrameAsync(invalidStream, CancellationToken.None), "oversize accepted");

    await using var wrongVersion = new MemoryStream();
    await WslCoreProtocol.WriteLengthPrefixedAsync(wrongVersion, System.Text.Encoding.UTF8.GetBytes("{\"v\":1,\"type\":\"hello\"}"), CancellationToken.None);
    wrongVersion.Position = 0;
    await AssertThrowsCodeAsync(() => WslCoreProtocol.ReadFrameAsync(wrongVersion, CancellationToken.None), "PROTOCOL_VERSION", "version mismatch accepted");
}

static Task TestProofAsync()
{
    var secret = Enumerable.Repeat((byte)1, 32).ToArray();
    var client = Enumerable.Repeat((byte)2, 32).ToArray();
    var server = Enumerable.Repeat((byte)3, 32).ToArray();
    var serverProof = Convert.ToBase64String(WslCoreProtocol.Proof(secret, "server", client, server));
    Assert(WslCoreProtocol.VerifyProof(secret, "server", client, server, serverProof), "valid proof rejected");
    Assert(!WslCoreProtocol.VerifyProof(secret, "client", client, server, serverProof), "role confusion accepted");
    return Task.CompletedTask;
}

static async Task TestSecureChannelAsync()
{
    var secret = Enumerable.Repeat((byte)7, 32).ToArray();
    var clientNonce = Enumerable.Repeat((byte)8, 32).ToArray();
    var serverNonce = Enumerable.Repeat((byte)9, 32).ToArray();
    await using var wire = new MemoryStream();
    await using (var client = WslCoreSecureChannel.Create(new MemoryStream(), wire, secret, clientNonce, serverNonce, serverSide: false))
    {
        await client.WriteAsync(new WireEnvelope { Version = 2, Type = "request", Id = "one", Payload = WslCoreProtocol.Payload(new { method = "health" }) }, CancellationToken.None);
    }
    var captured = wire.ToArray();
    await using (var server = WslCoreSecureChannel.Create(new MemoryStream(captured), new MemoryStream(), secret, clientNonce, serverNonce, serverSide: true))
    {
        var decoded = await server.ReadAsync(CancellationToken.None);
        Assert(decoded.Type == "request" && decoded.Id == "one", "protected roundtrip failed");
    }

    var tampered = captured.ToArray();
    tampered[^1] ^= 0x40;
    await using (var server = WslCoreSecureChannel.Create(new MemoryStream(tampered), new MemoryStream(), secret, clientNonce, serverNonce, serverSide: true))
    {
        await AssertThrowsCodeAsync(() => server.ReadAsync(CancellationToken.None), "FRAME_INTEGRITY", "tampered protected frame accepted");
    }

    var replay = new byte[captured.Length * 2];
    captured.CopyTo(replay, 0);
    captured.CopyTo(replay, captured.Length);
    await using (var server = WslCoreSecureChannel.Create(new MemoryStream(replay), new MemoryStream(), secret, clientNonce, serverNonce, serverSide: true))
    {
        _ = await server.ReadAsync(CancellationToken.None);
        await AssertThrowsCodeAsync(() => server.ReadAsync(CancellationToken.None), "FRAME_SEQUENCE", "replayed protected frame accepted");
    }

    var outOfOrder = captured.ToArray();
    BinaryPrimitives.WriteUInt64BigEndian(outOfOrder.AsSpan(4, 8), 2);
    await using (var server = WslCoreSecureChannel.Create(new MemoryStream(outOfOrder), new MemoryStream(), secret, clientNonce, serverNonce, serverSide: true))
    {
        await AssertThrowsCodeAsync(() => server.ReadAsync(CancellationToken.None), "FRAME_SEQUENCE", "out-of-order protected frame accepted");
    }
}

static Task TestBootstrapArgumentsAsync()
{
    Environment.SetEnvironmentVariable("JWT_SECRET", "must-not-leak");
    var info = WslCoreSupervisor.BuildBootstrapStartInfo("wsl.exe", "kali-linux", "/tmp/cloudos-core");
    Assert(!info.UseShellExecute, "shell execute enabled");
    Assert(info.ArgumentList.SequenceEqual(["--distribution", "kali-linux", "--exec", "/tmp/cloudos-core", "serve"]), "bootstrap arguments changed");
    Assert(!info.Environment.ContainsKey("JWT_SECRET"), "secret environment inherited");
    AssertThrowsSync<ArgumentException>(() => WslCoreSupervisor.BuildBootstrapStartInfo("wsl.exe", "kali-linux;whoami", "/tmp/core"), "distro injection accepted");
    AssertThrowsSync<ArgumentException>(() => WslCoreSupervisor.BuildBootstrapStartInfo("wsl.exe", "kali-linux", "relative/core"), "relative core path accepted");
    return Task.CompletedTask;
}

static async Task TestDistroAndFallbackAsync()
{
    var parsed = WslCoreSupervisor.ParseVerboseList("  NAME            STATE           VERSION\0\r\n* kali-linux      Running         2\0\r\n  Ubuntu-24.04    Stopped         2\0\r\n  Debian          Stopped         1\0\r\n");
    Assert(parsed.Count == 3, "distro list parsing failed");
    Assert(parsed[0] == new WslCoreDistribution("kali-linux", 2, true), "default WSL2 distro parse failed");
    Assert(parsed[2] == new WslCoreDistribution("Debian", 1, false), "WSL1 distro parse failed");
    await using var supervisor = new WslCoreSupervisor(Path.Combine(Path.GetTempPath(), Guid.NewGuid() + "-wsl.exe"));
    try
    {
        _ = await supervisor.ListInstalledAsync();
        throw new Exception("missing WSL fallback did not fail");
    }
    catch (WslCoreProtocolException error)
    {
        Assert(error.Code == "WSL_NOT_FOUND", "wrong missing WSL code");
    }
}

static async Task TestDisconnectAndTimeoutAsync()
{
    await using var earlyEnd = new MemoryStream([0, 0]);
    await AssertThrowsAsync<EndOfStreamException>(() => WslCoreProtocol.ReadFrameAsync(earlyEnd, CancellationToken.None), "early disconnect accepted");
    await using var hanging = new HangingStream();
    using var timeout = new CancellationTokenSource(80);
    try
    {
        _ = await WslCoreProtocol.ReadFrameAsync(hanging, timeout.Token);
        throw new Exception("timeout not observed");
    }
    catch (OperationCanceledException) { }
}

static void Assert(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

static void AssertThrowsSync<T>(Action action, string message) where T : Exception
{
    try { action(); }
    catch (T) { return; }
    throw new Exception(message);
}

static async Task AssertThrowsAsync<T>(Func<Task> action, string message) where T : Exception
{
    try { await action(); }
    catch (T) { return; }
    throw new Exception(message);
}

static async Task AssertThrowsCodeAsync(Func<Task> action, string code, string message)
{
    try { await action(); }
    catch (WslCoreProtocolException error) when (error.Code == code) { return; }
    throw new Exception(message);
}

sealed class ChunkedReadStream(Stream inner, int chunkSize) : Stream
{
    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => inner.Length;
    public override long Position { get => inner.Position; set => throw new NotSupportedException(); }
    public override int Read(byte[] buffer, int offset, int count) => inner.Read(buffer, offset, Math.Min(count, chunkSize));
    public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default) => inner.ReadAsync(buffer[..Math.Min(buffer.Length, chunkSize)], cancellationToken);
    public override void Flush() { }
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    protected override void Dispose(bool disposing) { if (disposing) inner.Dispose(); base.Dispose(disposing); }
    public override async ValueTask DisposeAsync() { await inner.DisposeAsync(); await base.DisposeAsync(); }
}

sealed class HangingStream : Stream
{
    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => 0;
    public override long Position { get => 0; set => throw new NotSupportedException(); }
    public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
    {
        await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
        return 0;
    }
    public override void Flush() { }
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
}
