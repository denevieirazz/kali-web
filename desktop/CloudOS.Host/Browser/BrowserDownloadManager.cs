using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Host.Browser;

public sealed record BrowserDownloadStatus(
    string Id,
    string FileName,
    long BytesReceived,
    long? TotalBytes,
    string State,
    string? InterruptReason);

public sealed class BrowserDownloadManager : IDisposable
{
    private const int MaxDownloadNameLength = 180;
    private const int MaxCollisionAttempts = 10_000;
    private static readonly HashSet<string> ReservedDeviceNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    };

    private readonly Dictionary<string, TrackedDownload> _active = new(StringComparer.Ordinal);
    private readonly Func<Window, string, string?>? _destinationSelector;
    private bool _disposed;

    public BrowserDownloadManager(Func<Window, string, string?>? destinationSelector = null)
    {
        _destinationSelector = destinationSelector;
    }

    public event EventHandler<BrowserDownloadStatus>? StatusChanged;
    public bool HasActiveDownloads => _active.Count > 0;
    public int ActiveCount => _active.Count;

    public void Handle(Window owner, CoreWebView2DownloadStartingEventArgs args)
    {
        if (_disposed)
        {
            args.Cancel = true;
            args.Handled = true;
            return;
        }

        var deferral = args.GetDeferral();
        try
        {
            var suggestedPath = args.ResultFilePath;
            var suggestedName = string.IsNullOrWhiteSpace(suggestedPath) ? "download" : Path.GetFileName(suggestedPath);
            if (string.IsNullOrWhiteSpace(suggestedName)) suggestedName = "download";
            var destination = _destinationSelector is null
                ? SelectCloudOsDestination(suggestedName)
                : _destinationSelector(owner, suggestedName);

            if (string.IsNullOrWhiteSpace(destination) || !Path.IsPathFullyQualified(destination))
            {
                args.Cancel = true;
                args.Handled = true;
                return;
            }

            var directory = Path.GetDirectoryName(destination);
            if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory))
            {
                args.Cancel = true;
                args.Handled = true;
                return;
            }

            args.ResultFilePath = destination;
            args.Handled = true;
            Track(args.DownloadOperation, destination);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
            args.Cancel = true;
            args.Handled = true;
        }
        finally
        {
            deferral.Complete();
        }
    }

    public int CancelAll()
    {
        var requested = 0;
        foreach (var item in _active.Values.ToArray())
        {
            try
            {
                if (item.Operation.State != CoreWebView2DownloadState.InProgress) continue;
                item.Operation.Cancel();
                requested++;
            }
            catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException or COMException)
            {
                PublishFailure(item, "CancelFailed", error.GetType().Name);
            }
        }
        return requested;
    }

    private string SelectCloudOsDestination(string suggestedName)
    {
        var localApplicationData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(localApplicationData))
            throw new InvalidOperationException("LOCALAPPDATA is unavailable for CloudOS Drive downloads.");
        var overrideRoot = Environment.GetEnvironmentVariable("CLOUDOS_DRIVE_DIR");
        var downloads = BrowserStorageLayout.CloudOsDriveDownloads(localApplicationData, overrideRoot);
        return AllocateCloudOsDownloadPath(downloads, suggestedName, _active.Values.Select(item => item.Path));
    }

    internal static string AllocateCloudOsDownloadPath(
        string directory,
        string suggestedName,
        IEnumerable<string>? reservedPaths = null)
    {
        if (string.IsNullOrWhiteSpace(directory) || !Path.IsPathFullyQualified(directory))
            throw new ArgumentException("A fully-qualified CloudOS Downloads directory is required.", nameof(directory));

        var normalizedDirectory = Path.GetFullPath(directory);
        Directory.CreateDirectory(normalizedDirectory);
        var safeName = SanitizeDownloadName(suggestedName);
        var extension = Path.GetExtension(safeName);
        var stem = Path.GetFileNameWithoutExtension(safeName);
        if (string.IsNullOrWhiteSpace(stem)) stem = "download";

        var reserved = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (reservedPaths is not null)
        {
            foreach (var reservedPath in reservedPaths)
            {
                if (string.IsNullOrWhiteSpace(reservedPath)) continue;
                try { reserved.Add(Path.GetFullPath(reservedPath)); }
                catch (Exception error) when (error is ArgumentException or NotSupportedException) { }
            }
        }

        for (var attempt = 0; attempt < MaxCollisionAttempts; attempt++)
        {
            var fileName = attempt == 0 ? safeName : $"{stem} ({attempt}){extension}";
            var candidate = Path.GetFullPath(Path.Combine(normalizedDirectory, fileName));
            var candidateDirectory = Path.GetDirectoryName(candidate);
            if (!string.Equals(candidateDirectory?.TrimEnd(Path.DirectorySeparatorChar), normalizedDirectory.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("The download destination escaped CloudOS Drive.");
            if (!reserved.Contains(candidate) && !File.Exists(candidate) && !Directory.Exists(candidate)) return candidate;
        }

        throw new IOException("CloudOS Downloads could not allocate a unique file name.");
    }

    internal static string SanitizeDownloadName(string suggestedName)
    {
        var name = Path.GetFileName(suggestedName ?? string.Empty);
        if (string.IsNullOrWhiteSpace(name)) name = "download";

        var invalid = Path.GetInvalidFileNameChars();
        var characters = name.Select(character => invalid.Contains(character) || char.IsControl(character) ? '_' : character).ToArray();
        name = new string(characters).Trim().TrimEnd('.', ' ');
        if (string.IsNullOrWhiteSpace(name) || name is "." or "..") name = "download";

        var extension = Path.GetExtension(name);
        var stem = Path.GetFileNameWithoutExtension(name);
        if (ReservedDeviceNames.Contains(stem)) stem = $"_{stem}";

        var maximumStemLength = Math.Max(1, MaxDownloadNameLength - extension.Length);
        if (stem.Length > maximumStemLength) stem = stem[..maximumStemLength];
        name = (stem + extension).TrimEnd('.', ' ');
        return string.IsNullOrWhiteSpace(name) ? "download" : name;
    }

    private void Track(CoreWebView2DownloadOperation operation, string path)
    {
        var id = Guid.NewGuid().ToString("N");
        var tracked = new TrackedDownload(id, path, operation);
        _active[id] = tracked;
        tracked.BytesHandler = (_, _) => Publish(tracked);
        tracked.StateHandler = (_, _) =>
        {
            if (operation.State != CoreWebView2DownloadState.InProgress)
                Untrack(tracked);
            Publish(tracked);
        };
        operation.BytesReceivedChanged += tracked.BytesHandler;
        operation.StateChanged += tracked.StateHandler;
        Publish(tracked);
    }

    private void Publish(TrackedDownload tracked)
    {
        long? total = null;
        string? reason = null;
        try
        {
            var expected = tracked.Operation.TotalBytesToReceive;
            if (expected.HasValue && expected.Value <= long.MaxValue) total = (long)expected.Value;
            if (tracked.Operation.State == CoreWebView2DownloadState.Interrupted)
                reason = tracked.Operation.InterruptReason.ToString();

            StatusChanged?.Invoke(this, new BrowserDownloadStatus(
                tracked.Id,
                Path.GetFileName(tracked.Path),
                tracked.Operation.BytesReceived,
                total,
                tracked.Operation.State.ToString(),
                reason));
        }
        catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException or COMException)
        {
            PublishFailure(tracked, "Unavailable", error.GetType().Name);
        }
    }

    private void PublishFailure(TrackedDownload tracked, string state, string reason)
    {
        StatusChanged?.Invoke(this, new BrowserDownloadStatus(
            tracked.Id,
            Path.GetFileName(tracked.Path),
            0,
            null,
            state,
            reason));
    }

    private void Untrack(TrackedDownload tracked)
    {
        if (!_active.Remove(tracked.Id)) return;
        if (tracked.BytesHandler is not null)
            tracked.Operation.BytesReceivedChanged -= tracked.BytesHandler;
        if (tracked.StateHandler is not null)
            tracked.Operation.StateChanged -= tracked.StateHandler;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        CancelAll();
        foreach (var tracked in _active.Values.ToArray())
            Untrack(tracked);
    }

    private sealed class TrackedDownload(string id, string path, CoreWebView2DownloadOperation operation)
    {
        public string Id { get; } = id;
        public string Path { get; } = path;
        public CoreWebView2DownloadOperation Operation { get; } = operation;
        public EventHandler<object>? BytesHandler { get; set; }
        public EventHandler<object>? StateHandler { get; set; }
    }
}
