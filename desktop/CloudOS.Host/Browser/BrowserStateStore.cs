using System.Text.Json;

namespace CloudOS.Host.Browser;

public sealed record BrowserHistoryEntry(string Url, string Title, DateTimeOffset VisitedAt);
public sealed record BrowserFavorite(string Id, string Url, string Title, DateTimeOffset CreatedAt);
public sealed record BrowserStateDocument(int SchemaVersion, List<BrowserHistoryEntry> History, List<BrowserFavorite> Favorites);

public sealed class BrowserStateStore
{
    public const int HistoryLimit = 5000;
    public const int FavoritesLimit = 1000;
    private readonly string _path;
    private readonly JsonSerializerOptions _json = new() { WriteIndented = true };
    private BrowserStateDocument _state;

    public BrowserStateStore(string path)
    {
        _path = path;
        _state = Load();
    }

    public IReadOnlyList<BrowserHistoryEntry> History => _state.History;
    public IReadOnlyList<BrowserFavorite> Favorites => _state.Favorites;

    public void AddHistory(Uri uri, string? title, DateTimeOffset? visitedAt = null)
    {
        if (uri.Scheme is not ("http" or "https")) return;
        var entry = new BrowserHistoryEntry(uri.AbsoluteUri, string.IsNullOrWhiteSpace(title) ? uri.Host : title.Trim(), visitedAt ?? DateTimeOffset.UtcNow);
        _state.History.Add(entry);
        if (_state.History.Count > HistoryLimit)
            _state.History.RemoveRange(0, _state.History.Count - HistoryLimit);
        Save();
    }

    public bool ToggleFavorite(Uri uri, string? title)
    {
        var existing = _state.Favorites.FirstOrDefault(x => string.Equals(x.Url, uri.AbsoluteUri, StringComparison.OrdinalIgnoreCase));
        if (existing is not null)
        {
            _state.Favorites.Remove(existing);
            Save();
            return false;
        }
        if (_state.Favorites.Count >= FavoritesLimit)
            _state.Favorites.RemoveAt(0);
        _state.Favorites.Add(new BrowserFavorite(Guid.NewGuid().ToString("D"), uri.AbsoluteUri, string.IsNullOrWhiteSpace(title) ? uri.Host : title.Trim(), DateTimeOffset.UtcNow));
        Save();
        return true;
    }

    public bool IsFavorite(Uri uri) => _state.Favorites.Any(x => string.Equals(x.Url, uri.AbsoluteUri, StringComparison.OrdinalIgnoreCase));

    public void ClearHistory()
    {
        _state.History.Clear();
        Save();
    }

    public void RemoveFavorite(string id)
    {
        _state.Favorites.RemoveAll(x => string.Equals(x.Id, id, StringComparison.Ordinal));
        Save();
    }

    private BrowserStateDocument Load()
    {
        try
        {
            if (!File.Exists(_path)) return Empty();
            var parsed = JsonSerializer.Deserialize<BrowserStateDocument>(File.ReadAllText(_path), _json);
            if (parsed is null || parsed.SchemaVersion != 1) return Empty();
            parsed.History ??= [];
            parsed.Favorites ??= [];
            if (parsed.History.Count > HistoryLimit) parsed.History.RemoveRange(0, parsed.History.Count - HistoryLimit);
            if (parsed.Favorites.Count > FavoritesLimit) parsed.Favorites.RemoveRange(0, parsed.Favorites.Count - FavoritesLimit);
            return parsed;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException)
        {
            TryQuarantineCorruptFile();
            return Empty();
        }
    }

    private void Save()
    {
        var directory = Path.GetDirectoryName(_path) ?? throw new InvalidOperationException("Diretório de estado inválido.");
        Directory.CreateDirectory(directory);
        var temp = _path + ".tmp";
        var backup = _path + ".bak";
        File.WriteAllText(temp, JsonSerializer.Serialize(_state, _json));
        if (File.Exists(_path))
        {
            try { File.Replace(temp, _path, backup, ignoreMetadataErrors: true); }
            catch (PlatformNotSupportedException) { File.Move(temp, _path, overwrite: true); }
            catch (IOException) { File.Move(temp, _path, overwrite: true); }
        }
        else
        {
            File.Move(temp, _path);
        }
    }

    private void TryQuarantineCorruptFile()
    {
        try
        {
            if (!File.Exists(_path)) return;
            var corrupt = _path + $".corrupt-{DateTime.UtcNow:yyyyMMddHHmmss}";
            File.Move(_path, corrupt, overwrite: false);
        }
        catch { }
    }

    private static BrowserStateDocument Empty() => new(1, [], []);
}
