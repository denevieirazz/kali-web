using System.Text.Json;
using System.Text.Json.Serialization;

namespace CloudOS.Bootstrap;

public sealed class ProductMetadata
{
    [JsonPropertyName("schemaVersion")] public int SchemaVersion { get; init; }
    [JsonPropertyName("product")] public string Product { get; init; } = "CloudOS";
    [JsonPropertyName("version")] public string Version { get; init; } = "development";
    [JsonPropertyName("channel")] public string Channel { get; init; } = "development";
    [JsonPropertyName("signing")] public string Signing { get; init; } = "unsigned-development";
    [JsonPropertyName("stableUpdatesEnabled")] public bool StableUpdatesEnabled { get; init; }
    [JsonPropertyName("baseSha")] public string BaseSha { get; init; } = string.Empty;

    public static ProductMetadata Load(string? baseDirectory = null)
    {
        var root = Path.GetFullPath(baseDirectory ?? AppContext.BaseDirectory);
        var candidates = new[]
        {
            Path.Combine(root, "meta", "product.json"),
            Path.Combine(root, "productization", "cloudos-product.json")
        };
        foreach (var path in candidates)
        {
            try
            {
                if (!File.Exists(path)) continue;
                var product = JsonSerializer.Deserialize<ProductMetadata>(File.ReadAllText(path));
                if (product is { SchemaVersion: 1 }) return product;
            }
            catch (JsonException) { }
            catch (IOException) { }
        }
        return new ProductMetadata();
    }
}
