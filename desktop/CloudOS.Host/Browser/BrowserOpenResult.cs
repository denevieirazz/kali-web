using System.Text.Json.Serialization;

namespace CloudOS.Host.Browser;

public sealed record BrowserOpenResult
{
    [JsonPropertyName("opened")]
    public required bool Opened { get; init; }

    [JsonPropertyName("reused")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public bool? Reused { get; init; }

    [JsonPropertyName("windowVisible")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public bool? WindowVisible { get; init; }

    [JsonPropertyName("code")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Code { get; init; }

    [JsonPropertyName("message")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Message { get; init; }

    public static BrowserOpenResult Success(bool reused, bool windowVisible) => new()
    {
        Opened = true,
        Reused = reused,
        WindowVisible = windowVisible
    };

    public static BrowserOpenResult Failure(string code, string message) => new()
    {
        Opened = false,
        Code = code,
        Message = message
    };
}
