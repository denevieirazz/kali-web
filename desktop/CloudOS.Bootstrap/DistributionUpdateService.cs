using System.Text.RegularExpressions;
using Velopack;

namespace CloudOS.Bootstrap;

public sealed class PreparedUpdate
{
    internal PreparedUpdate(UpdateManager manager, UpdateInfo info, string channel)
    {
        Manager = manager;
        Info = info;
        Channel = channel;
    }
    internal UpdateManager Manager { get; }
    internal UpdateInfo Info { get; }
    public string Channel { get; }
    public string Version => Info.TargetFullRelease.Version.ToString();
    public string FileName => Info.TargetFullRelease.FileName;
    public string Sha256 => Info.TargetFullRelease.SHA256;
}

public static class DistributionUpdateService
{
    public static async Task<PreparedUpdate?> CheckAsync(string source, string? requestedChannel, ProductMetadata metadata)
    {
        var channel = NormalizeChannel(requestedChannel ?? metadata.Channel);
        if (channel == "stable" && !metadata.StableUpdatesEnabled)
            throw new InvalidOperationException("O canal stable permanece desativado neste lote experimental.");
        var safeSource = ValidateSource(source, channel);
        var manager = new UpdateManager(safeSource, new UpdateOptions { ExplicitChannel = channel, AllowVersionDowngrade = false });
        if (!manager.IsInstalled)
            throw new InvalidOperationException("Atualizações só podem ser aplicadas à instalação gerenciada. O modo portátil permanece manual.");
        var info = await manager.CheckForUpdatesAsync();
        if (info is null) return null;
        if (info.IsDowngrade) throw new InvalidOperationException("Downgrade silencioso foi rejeitado.");
        var hash = info.TargetFullRelease.SHA256 ?? string.Empty;
        if (!Regex.IsMatch(hash, "^[0-9a-fA-F]{64}$"))
            throw new InvalidOperationException("O feed não forneceu SHA-256 válido para o pacote alvo.");
        return new PreparedUpdate(manager, info, channel);
    }

    public static Task DownloadAsync(PreparedUpdate update, Action<int>? progress, CancellationToken cancellationToken)
        => update.Manager.DownloadUpdatesAsync(update.Info, progress, cancellationToken);

    public static void ApplyAndRestart(PreparedUpdate update, string localRoot)
    {
        var criticalLock = Path.Combine(Path.GetFullPath(localRoot), "distribution-critical.lock");
        if (File.Exists(criticalLock)) throw new InvalidOperationException("Uma sessão crítica está ativa; a atualização não será aplicada agora.");
        update.Manager.ApplyUpdatesAndRestart(update.Info.TargetFullRelease, new[] { "--skip-prerequisites" });
    }

    private static string NormalizeChannel(string channel)
    {
        var normalized = (channel ?? string.Empty).Trim().ToLowerInvariant();
        return normalized is "stable" or "preview" or "development"
            ? normalized
            : throw new InvalidOperationException("Canal de atualização inválido.");
    }

    private static string ValidateSource(string source, string channel)
    {
        if (string.IsNullOrWhiteSpace(source)) throw new InvalidOperationException("Fonte de atualização não configurada.");
        if (Uri.TryCreate(source, UriKind.Absolute, out var uri))
        {
            if (uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)) return uri.ToString().TrimEnd('/');
            if (uri.IsFile && channel == "development") return Path.GetFullPath(uri.LocalPath);
            throw new InvalidOperationException("Feeds remotos exigem HTTPS; fonte local é permitida somente no canal development.");
        }
        var full = Path.GetFullPath(source);
        if (channel != "development") throw new InvalidOperationException("Fonte local é permitida somente no canal development.");
        if (!Directory.Exists(full)) throw new DirectoryNotFoundException("Diretório local de atualização não encontrado.");
        return full;
    }
}
