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
        TrimToLimit(_state.History, HistoryLimit);
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
        if (_state.Favorites.Count >= FavoritesLimit) _state.Favorites.RemoveAt(0);
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

    internal static BrowserStateDocument Normalize(BrowserStateDocument? parsed)
    {
        if (parsed is null || parsed.SchemaVersion != 1) return Empty();
        var history = parsed.History ?? [];
        var favorites = parsed.Favorites ?? [];
        TrimToLimit(history, HistoryLimit);
        TrimToLimit(favorites, FavoritesLimit);
        return new BrowserStateDocument(1, history, favorites);
    }

    private BrowserStateDocument Load()
    {
        try
        {
            if (!File.Exists(_path)) return Empty();
            return Normalize(JsonSerializer.Deserialize<BrowserStateDocument>(File.ReadAllText(_path), _json));
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
            var corrupt = _path + $".corrupt-{DateTime.UtcNow:yyyyMMddHHmmssfff}";
            File.Move(_path, corrupt, overwrite: false);
        }
        catch { }
    }

    private static void TrimToLimit<T>(List<T> items, int limit)
    {
        if (items.Count > limit) items.RemoveRange(0, items.Count - limit);
    }

    private static BrowserStateDocument Empty() => new(1, [], []);
}
