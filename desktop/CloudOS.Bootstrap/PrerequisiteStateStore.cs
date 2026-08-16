using System.Text.Json;

namespace CloudOS.Bootstrap;

public static class PrerequisiteStateStore
{
    private const int SchemaVersion = 1;

    public static bool IsAccepted(string localRoot)
    {
        try
        {
            var path = GetPath(localRoot);
            if (!File.Exists(path)) return false;
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            return document.RootElement.TryGetProperty("schemaVersion", out var schema)
                && schema.GetInt32() == SchemaVersion
                && document.RootElement.TryGetProperty("accepted", out var accepted)
                && accepted.GetBoolean();
        }
        catch { return false; }
    }

    public static void MarkAccepted(string localRoot, string mode)
    {
        Directory.CreateDirectory(localRoot);
        var payload = new
        {
            schemaVersion = SchemaVersion,
            accepted = true,
            mode,
            checkedAt = DateTimeOffset.UtcNow
        };
        File.WriteAllText(GetPath(localRoot), JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
    }

    private static string GetPath(string localRoot) => Path.Combine(Path.GetFullPath(localRoot), "prerequisites-v1.json");
}
