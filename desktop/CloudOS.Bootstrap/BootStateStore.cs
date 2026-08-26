using System.IO;
using System.Text;
using System.Text.Json;

namespace CloudOS.Bootstrap;

public sealed class BootStateStore
{
    private readonly object _logLock = new();
    private readonly JsonSerializerOptions _jsonOptions = new() { WriteIndented = true };

    public BootStateStore(string? localRoot = null)
    {
        LocalRoot = Path.GetFullPath(localRoot ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CloudOS"));
        Directory.CreateDirectory(LocalRoot);
        LogDirectory = Path.Combine(LocalRoot, "logs");
        Directory.CreateDirectory(LogDirectory);
        StatePath = Path.Combine(LocalRoot, "bootstrap-state.json");
        CurrentLogPath = Path.Combine(LogDirectory, $"bootstrap-{DateTime.UtcNow:yyyyMMdd}.log");
    }

    public string LocalRoot { get; }
    public string LogDirectory { get; }
    public string StatePath { get; }
    public string CurrentLogPath { get; }

    public BootstrapState Load()
    {
        try
        {
            if (!File.Exists(StatePath)) return new BootstrapState();
            var state = JsonSerializer.Deserialize<BootstrapState>(File.ReadAllText(StatePath, Encoding.UTF8));
            return state is { SchemaVersion: 1 } ? state : new BootstrapState();
        }
        catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException)
        {
            try
            {
                if (File.Exists(StatePath))
                    File.Move(StatePath, $"{StatePath}.corrupt-{DateTime.UtcNow:yyyyMMddHHmmss}", overwrite: false);
            }
            catch (Exception moveError) when (moveError is IOException or UnauthorizedAccessException) { }
            return new BootstrapState();
        }
    }

    public void Save(BootstrapState state)
    {
        Directory.CreateDirectory(LocalRoot);
        var temporary = $"{StatePath}.{Environment.ProcessId}.{Guid.NewGuid():N}.tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(state, _jsonOptions), new UTF8Encoding(false));
            File.Move(temporary, StatePath, overwrite: true);
        }
        finally
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); } catch (IOException) { }
        }
    }

    public void AppendLog(string message)
    {
        var safe = string.Concat((message ?? string.Empty).Where(character => character is not ('\r' or '\n' or '\0')));
        if (safe.Length > 4_096) safe = safe[..4_096];
        lock (_logLock)
        {
            File.AppendAllText(CurrentLogPath, $"{DateTimeOffset.Now:O} {safe}{Environment.NewLine}", Encoding.UTF8);
        }
    }
}
