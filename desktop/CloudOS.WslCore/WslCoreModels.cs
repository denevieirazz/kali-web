using System.Text.Json.Serialization;

namespace CloudOS.WslCore;

public sealed class WslCoreDistroInfo
{
    [JsonPropertyName("id")] public string? Id { get; init; }
    [JsonPropertyName("versionId")] public string? VersionId { get; init; }
    [JsonPropertyName("prettyName")] public string? PrettyName { get; init; }
    [JsonPropertyName("user")] public string? User { get; init; }
    [JsonPropertyName("systemd")] public bool Systemd { get; init; }
}

public sealed class WslCoreHealth
{
    [JsonPropertyName("status")] public string? Status { get; init; }
    [JsonPropertyName("protocol")] public int Protocol { get; init; }
    [JsonPropertyName("pid")] public int Pid { get; init; }
    [JsonPropertyName("distro")] public WslCoreDistroInfo? Distro { get; init; }
    [JsonPropertyName("activeSessions")] public int ActiveSessions { get; init; }
    [JsonPropertyName("protection")] public string? Protection { get; init; }
}

public sealed class WslCoreMemoryMetrics
{
    [JsonPropertyName("totalBytes")] public ulong TotalBytes { get; init; }
    [JsonPropertyName("availableBytes")] public ulong AvailableBytes { get; init; }
}

public sealed class WslCoreMetrics
{
    [JsonPropertyName("uptimeSeconds")] public double UptimeSeconds { get; init; }
    [JsonPropertyName("load1")] public double Load1 { get; init; }
    [JsonPropertyName("load5")] public double Load5 { get; init; }
    [JsonPropertyName("load15")] public double Load15 { get; init; }
    [JsonPropertyName("memory")] public WslCoreMemoryMetrics? Memory { get; init; }
    [JsonPropertyName("processCount")] public int ProcessCount { get; init; }
    [JsonPropertyName("cgroupV2")] public bool CgroupV2 { get; init; }
    [JsonPropertyName("cgroupPath")] public string? CgroupPath { get; init; }
    [JsonPropertyName("cgroup")] public Dictionary<string, string>? Cgroup { get; init; }
}

public sealed class WslCoreSessionStatus
{
    [JsonPropertyName("sessionId")] public string? SessionId { get; init; }
    [JsonPropertyName("pid")] public int Pid { get; init; }
    [JsonPropertyName("state")] public string? State { get; init; }
    [JsonPropertyName("exitCode")] public int? ExitCode { get; init; }
    [JsonPropertyName("signal")] public string? Signal { get; init; }
    [JsonPropertyName("pty")] public bool Pty { get; init; }
}

public sealed class WslCoreEvent
{
    [JsonPropertyName("type")] public string? Type { get; init; }
    [JsonPropertyName("sessionId")] public string? SessionId { get; init; }
    [JsonPropertyName("stream")] public string? Stream { get; init; }
    [JsonPropertyName("data")] public string? Data { get; init; }
    [JsonPropertyName("exitCode")] public int? ExitCode { get; init; }
    [JsonPropertyName("signal")] public string? Signal { get; init; }
}

public sealed record WslCoreCreateSession(
    string Executable,
    IReadOnlyList<string>? Args = null,
    string? Cwd = null,
    IReadOnlyDictionary<string, string>? Env = null,
    string? User = null,
    bool Pty = false,
    int Cols = 80,
    int Rows = 24);

public sealed record WslCoreSupervisorOptions(string Distribution, string LinuxCorePath, bool AllowBootstrap);

public sealed record WslCoreDistribution(string Name, int Version, bool IsDefault);
