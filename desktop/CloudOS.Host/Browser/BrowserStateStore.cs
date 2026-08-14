using System.Text;
using System.Text.Json;

namespace CloudOS.Host.Browser;

public sealed record BrowserHistoryEntry(string Url, string Title, DateTimeOffset VisitedAt);
public sealed record BrowserFavorite(string Id, string Url, string Title, DateTimeOffset CreatedAt);
public sealed record BrowserSessionTab(string Url, bool Pinned);
public sealed record BrowserSessionState(List<BrowserSessionTab> Tabs, int ActiveIndex, DateTimeOffset SavedAt);
public sealed record BrowserStateDocument(
    int SchemaVersion,
    List<BrowserHistoryEntry>? History,
    List<BrowserFavorite>? Favorites,
    bool RestoreLastSession = false,
    BrowserSessionState? Session = null);

public sealed class BrowserStateStore
{
    public const int HistoryLimit = 5000;
    public const int FavoritesLimit = 1000;
    public const int SessionTabLimit = 32;
    private static readonly HashSet<string> SensitiveQueryNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "access_token", "token", "jwt", "auth", "authorization", "password", "passwd", "secret",
        "recovery", "recovery_code", "code", "api_key", "apikey", "key"
    };

    private readonly string _path;
    private readonly JsonSerializerOptions _json = new() { WriteIndented = true };
    private BrowserStateDocument _state;

    public BrowserStateStore(string path)
    {
        _path = path;
        _state = Load();
    }

    public IReadOnlyList<BrowserHistoryEntry> History => _state.History ?? [];
    public IReadOnlyList<BrowserFavorite> Favorites => _state.Favorites ?? [];
    public bool RestoreLastSession => _state.RestoreLastSession;
    public BrowserSessionState? Session => _state.Session;
    public string? LastPersistenceError { get; private set; }

    public void AddHistory(Uri uri, string? title, DateTimeOffset? visitedAt = null)
    {
        var persisted = SanitizePersistedUri(uri);
        if (persisted is null) return;
        var history = _state.History ?? [];
        history.Add(new BrowserHistoryEntry(
            persisted,
            SanitizeTitle(title, uri.Host),
            visitedAt ?? DateTimeOffset.UtcNow));
        TrimToLimit(history, HistoryLimit);
        _state = _state with { History = history };
        Save();
    }

    public bool ToggleFavorite(Uri uri, string? title)
    {
        var persisted = SanitizePersistedUri(uri);
        if (persisted is null) return false;
        var favorites = _state.Favorites ?? [];
        var existing = favorites.FirstOrDefault(x =>
            string.Equals(x.Url, persisted, StringComparison.OrdinalIgnoreCase));
        if (existing is not null)
        {
            favorites.Remove(existing);
            _state = _state with { Favorites = favorites };
            Save();
            return false;
        }

        if (favorites.Count >= FavoritesLimit) favorites.RemoveAt(0);
        favorites.Add(new BrowserFavorite(
            Guid.NewGuid().ToString("D"),
            persisted,
            SanitizeTitle(title, uri.Host),
            DateTimeOffset.UtcNow));
        _state = _state with { Favorites = favorites };
        Save();
        return true;
    }

    public bool IsFavorite(Uri uri)
    {
        var persisted = SanitizePersistedUri(uri);
        return persisted is not null && Favorites.Any(x =>
            string.Equals(x.Url, persisted, StringComparison.OrdinalIgnoreCase));
    }

    public IReadOnlyList<BrowserHistoryEntry> SearchHistory(string? query, int limit = 500)
    {
        var needle = (query ?? string.Empty).Trim();
        var source = History.Reverse();
        if (needle.Length > 0)
            source = source.Where(item =>
                item.Title.Contains(needle, StringComparison.OrdinalIgnoreCase) ||
                item.Url.Contains(needle, StringComparison.OrdinalIgnoreCase));
        return source.Take(Math.Clamp(limit, 1, 1000)).ToList();
    }

    public IReadOnlyList<BrowserFavorite> SearchFavorites(string? query, int limit = 500)
    {
        var needle = (query ?? string.Empty).Trim();
        IEnumerable<BrowserFavorite> source = Favorites;
        if (needle.Length > 0)
            source = source.Where(item =>
                item.Title.Contains(needle, StringComparison.OrdinalIgnoreCase) ||
                item.Url.Contains(needle, StringComparison.OrdinalIgnoreCase));
        return source.Take(Math.Clamp(limit, 1, FavoritesLimit)).ToList();
    }

    public void SetRestoreLastSession(bool enabled)
    {
        _state = _state with { RestoreLastSession = enabled };
        Save();
    }

    public void SaveSession(IEnumerable<BrowserSessionTab> tabs, int activeIndex)
    {
        var safeTabs = tabs
            .Take(SessionTabLimit)
            .Select(tab => Uri.TryCreate(tab.Url, UriKind.Absolute, out var uri)
                ? new BrowserSessionTab(SanitizePersistedUri(uri) ?? string.Empty, tab.Pinned)
                : new BrowserSessionTab(string.Empty, tab.Pinned))
            .Where(tab => tab.Url.Length > 0)
            .ToList();
        var safeIndex = safeTabs.Count == 0 ? 0 : Math.Clamp(activeIndex, 0, safeTabs.Count - 1);
        _state = _state with
        {
            Session = safeTabs.Count == 0
                ? null
                : new BrowserSessionState(safeTabs, safeIndex, DateTimeOffset.UtcNow)
        };
        Save();
    }

    public void ClearSession()
    {
        _state = _state with { Session = null };
        Save();
    }

    public void ClearHistory()
    {
        _state = _state with { History = [] };
        Save();
    }

    public void ClearUserState()
    {
        _state = new BrowserStateDocument(1, [], [], false, null);
        Save();
    }

    public void RemoveFavorite(string id)
    {
        var favorites = (_state.Favorites ?? []).ToList();
        favorites.RemoveAll(x => string.Equals(x.Id, id, StringComparison.Ordinal));
        _state = _state with { Favorites = favorites };
        Save();
    }

    internal static BrowserStateDocument Normalize(BrowserStateDocument? parsed)
    {
        if (parsed is null || parsed.SchemaVersion != 1) return Empty();

        var history = (parsed.History ?? [])
            .Select(SanitizeHistoryEntry)
            .Where(entry => entry is not null)
            .Cast<BrowserHistoryEntry>()
            .ToList();
        var favorites = (parsed.Favorites ?? [])
            .Select(SanitizeFavorite)
            .Where(entry => entry is not null)
            .Cast<BrowserFavorite>()
            .ToList();
        TrimToLimit(history, HistoryLimit);
        TrimToLimit(favorites, FavoritesLimit);

        BrowserSessionState? session = null;
        if (parsed.Session is not null)
        {
            var tabs = parsed.Session.Tabs
                .Take(SessionTabLimit)
                .Select(tab => Uri.TryCreate(tab.Url, UriKind.Absolute, out var uri)
                    ? new BrowserSessionTab(SanitizePersistedUri(uri) ?? string.Empty, tab.Pinned)
                    : new BrowserSessionTab(string.Empty, tab.Pinned))
                .Where(tab => tab.Url.Length > 0)
                .ToList();
            if (tabs.Count > 0)
                session = new BrowserSessionState(
                    tabs,
                    Math.Clamp(parsed.Session.ActiveIndex, 0, tabs.Count - 1),
                    parsed.Session.SavedAt);
        }

        return new BrowserStateDocument(1, history, favorites, parsed.RestoreLastSession, session);
    }

    internal static string? SanitizePersistedUri(Uri uri)
    {
        if (!uri.IsAbsoluteUri || uri.Scheme is not ("http" or "https") || !string.IsNullOrEmpty(uri.UserInfo))
            return null;

        var builder = new UriBuilder(uri) { Fragment = string.Empty };
        if (builder.Query.Length > 1)
        {
            var kept = new List<string>();
            foreach (var pair in builder.Query[1..].Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                var separator = pair.IndexOf('=');
                var rawName = separator >= 0 ? pair[..separator] : pair;
                string decodedName;
                try { decodedName = Uri.UnescapeDataString(rawName.Replace('+', ' ')); }
                catch (UriFormatException) { continue; }
                if (!SensitiveQueryNames.Contains(decodedName)) kept.Add(pair);
            }
            builder.Query = string.Join('&', kept);
        }
        return builder.Uri.AbsoluteUri;
    }

    private BrowserStateDocument Load()
    {
        if (!File.Exists(_path)) return TryLoadBackup() ?? Empty();
        try
        {
            return Normalize(JsonSerializer.Deserialize<BrowserStateDocument>(File.ReadAllText(_path), _json));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException)
        {
            LastPersistenceError = $"STATE_READ_FAILED:{error.GetType().Name}";
            TryQuarantineCorruptFile();
            var backup = TryLoadBackup();
            if (backup is null) return Empty();
            try
            {
                SaveDocument(backup);
            }
            catch (Exception repairError) when (repairError is IOException or UnauthorizedAccessException)
            {
                LastPersistenceError = $"STATE_REPAIR_FAILED:{repairError.GetType().Name}";
            }
            return backup;
        }
    }

    private BrowserStateDocument? TryLoadBackup()
    {
        var backupPath = _path + ".bak";
        if (!File.Exists(backupPath)) return null;
        try
        {
            return Normalize(JsonSerializer.Deserialize<BrowserStateDocument>(File.ReadAllText(backupPath), _json));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException)
        {
            LastPersistenceError = $"STATE_BACKUP_READ_FAILED:{error.GetType().Name}";
            return null;
        }
    }

    private void Save()
    {
        try
        {
            SaveDocument(_state);
            LastPersistenceError = null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            LastPersistenceError = $"STATE_WRITE_FAILED:{error.GetType().Name}";
            throw;
        }
    }

    private void SaveDocument(BrowserStateDocument document)
    {
        var directory = Path.GetDirectoryName(_path) ?? throw new InvalidOperationException("Diretório de estado inválido.");
        Directory.CreateDirectory(directory);
        var temp = _path + ".tmp";
        var backup = _path + ".bak";
        try
        {
            using (var stream = new FileStream(temp, FileMode.Create, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            using (var writer = new StreamWriter(stream, new UTF8Encoding(false)))
            {
                writer.Write(JsonSerializer.Serialize(document, _json));
                writer.Flush();
                stream.Flush(flushToDisk: true);
            }

            if (File.Exists(_path))
            {
                try
                {
                    File.Replace(temp, _path, backup, ignoreMetadataErrors: true);
                }
                catch (PlatformNotSupportedException)
                {
                    File.Copy(_path, backup, overwrite: true);
                    File.Move(temp, _path, overwrite: true);
                }
                catch (IOException)
                {
                    File.Copy(_path, backup, overwrite: true);
                    File.Move(temp, _path, overwrite: true);
                }
            }
            else
            {
                File.Move(temp, _path);
                File.Copy(_path, backup, overwrite: true);
            }
        }
        finally
        {
            if (File.Exists(temp))
            {
                try { File.Delete(temp); }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                {
                    LastPersistenceError ??= $"STATE_TEMP_CLEANUP_FAILED:{error.GetType().Name}";
                }
            }
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
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            LastPersistenceError = $"STATE_QUARANTINE_FAILED:{error.GetType().Name}";
        }
    }

    private static BrowserHistoryEntry? SanitizeHistoryEntry(BrowserHistoryEntry entry)
    {
        if (!Uri.TryCreate(entry.Url, UriKind.Absolute, out var uri)) return null;
        var safe = SanitizePersistedUri(uri);
        return safe is null ? null : new BrowserHistoryEntry(safe, SanitizeTitle(entry.Title, uri.Host), entry.VisitedAt);
    }

    private static BrowserFavorite? SanitizeFavorite(BrowserFavorite entry)
    {
        if (!Guid.TryParse(entry.Id, out _) || !Uri.TryCreate(entry.Url, UriKind.Absolute, out var uri)) return null;
        var safe = SanitizePersistedUri(uri);
        return safe is null ? null : new BrowserFavorite(entry.Id, safe, SanitizeTitle(entry.Title, uri.Host), entry.CreatedAt);
    }

    private static string SanitizeTitle(string? title, string fallback)
    {
        var value = string.IsNullOrWhiteSpace(title) ? fallback : title.Trim();
        value = new string(value.Where(character => !char.IsControl(character)).ToArray());
        return value.Length <= 512 ? value : value[..512];
    }

    private static void TrimToLimit<T>(List<T> items, int limit)
    {
        if (items.Count > limit) items.RemoveRange(0, items.Count - limit);
    }

    private static BrowserStateDocument Empty() => new(1, [], [], false, null);
}
