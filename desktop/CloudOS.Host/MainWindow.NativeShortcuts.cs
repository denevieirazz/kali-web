using System.Runtime.InteropServices;
using System.Text.Json;
using CloudOS.Host.Native;

namespace CloudOS.Host;

public partial class MainWindow
{
    internal void DispatchNativeShortcut(NativeHostShortcut shortcut)
    {
        if (_closing) return;
        _ = Dispatcher.BeginInvoke(new Action(() => _ = ForwardNativeShortcutAsync(shortcut)));
    }

    private async Task ForwardNativeShortcutAsync(NativeHostShortcut shortcut)
    {
        if (_closing) return;
        var core = ShellWebView.CoreWebView2;
        if (core is null) return;

        var descriptor = shortcut switch
        {
            NativeHostShortcut.ToggleStartMenu => (Key: "Meta", Code: "MetaLeft", Alt: false, Meta: true),
            NativeHostShortcut.CycleWindows => (Key: "Tab", Code: "Tab", Alt: true, Meta: false),
            NativeHostShortcut.CloseActiveWindow => (Key: "F4", Code: "F4", Alt: true, Meta: false),
            _ => throw new ArgumentOutOfRangeException(nameof(shortcut))
        };

        var script = $"window.dispatchEvent(new KeyboardEvent('keydown', {{ key: {JsonSerializer.Serialize(descriptor.Key)}, code: {JsonSerializer.Serialize(descriptor.Code)}, altKey: {JsonSerializer.Serialize(descriptor.Alt)}, metaKey: {JsonSerializer.Serialize(descriptor.Meta)}, bubbles: true, cancelable: true }}));";
        try
        {
            await core.ExecuteScriptAsync(script);
        }
        catch (Exception error) when (error is InvalidOperationException or ObjectDisposedException or COMException)
        {
            // The WebView may be navigating or shutting down while the native key
            // sequence completes. The low-level key remains consumed either way.
        }
    }
}
