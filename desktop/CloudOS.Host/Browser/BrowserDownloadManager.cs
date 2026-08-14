using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using Microsoft.Win32;
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
    private readonly Dictionary<string, TrackedDownload> _active = new(StringComparer.Ordinal);
    private bool _disposed;

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
            var dialog = new SaveFileDialog
            {
                Title = "Salvar download — Navegador CloudOS",
                FileName = string.IsNullOrWhiteSpace(suggestedName) ? "download" : suggestedName,
                OverwritePrompt = true,
                CheckPathExists = true,
                AddExtension = false
            };
            if (dialog.ShowDialog(owner) != true || string.IsNullOrWhiteSpace(dialog.FileName))
            {
                args.Cancel = true;
                args.Handled = true;
                return;
            }

            args.ResultFilePath = dialog.FileName;
            args.Handled = true;
            Track(args.DownloadOperation, dialog.FileName);
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
