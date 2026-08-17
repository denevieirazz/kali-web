using System.Text.RegularExpressions;
using Velopack;
using Velopack.Logging;
using Velopack.Sources;

namespace CloudOS.Bootstrap;

public sealed class PreparedUpdate
{
    internal PreparedUpdate(UpdateManager manager, UpdateInfo info, string source, string channel)
    {
        Manager = manager;
        Info = info;
        Source = source;
        Channel = channel;
    }
    internal UpdateManager Manager { get; }
    internal UpdateInfo Info { get; }
    public string Source { get; }
    public string Channel { get; }
    public string Version => Info.TargetFullRelease.Version.ToString();
    public string? CurrentVersion => Manager.CurrentVersion?.ToString();
    public string FileName => Info.TargetFullRelease.FileName;
    public string Sha256 => Info.TargetFullRelease.SHA256;
}

public static class DistributionUpdateService
{
    public static async Task<PreparedUpdate?> CheckAsync(
        string source,
        string? requestedChannel,
        ProductMetadata metadata,
        DistributionStateStore? stateStore = null)
    {
        var policy = DistributionChannelPolicy.Load(metadata.Root);
        var persisted = stateStore?.Load();
        var currentChannel = policy.Normalize(persisted?.ConfirmedChannel ?? metadata.Channel);
        var channel = policy.Normalize(requestedChannel ?? metadata.Channel);
        policy.AssertTransition(currentChannel, channel, !string.IsNullOrWhiteSpace(requestedChannel));
        policy.AssertRuntimeReady(channel, metadata);
        var safeSource = ValidateSource(source, channel, policy);
        var manager = new UpdateManager(safeSource, new UpdateOptions { ExplicitChannel = channel, AllowVersionDowngrade = false });
        if (!manager.IsInstalled)
            throw new InvalidOperationException("Atualizações só podem ser aplicadas à instalação gerenciada. O modo portátil permanece manual.");
        var info = await manager.CheckForUpdatesAsync();
        if (info is null) return null;
        if (manager.CurrentVersion is not null)
            policy.AssertVersionDirection(manager.CurrentVersion.ToString(), info.TargetFullRelease.Version.ToString(), false);
        if (info.IsDowngrade) throw new InvalidOperationException("Downgrade silencioso foi rejeitado.");
        AssertAsset(info.TargetFullRelease);
        return new PreparedUpdate(manager, info, safeSource, channel);
    }

    public static async Task<PreparedUpdate> PrepareSpecificVersionAsync(string source, string channel, string version, ProductMetadata metadata)
    {
        var policy = DistributionChannelPolicy.Load(metadata.Root);
        channel = policy.Normalize(channel);
        policy.AssertRuntimeReady(channel, metadata);
        var safeSource = ValidateSource(source, channel, policy, allowLocalForRollback: true);
        IUpdateSource updateSource = Uri.TryCreate(safeSource, UriKind.Absolute, out var uri) && uri.Scheme.StartsWith("http", StringComparison.OrdinalIgnoreCase)
            ? new SimpleWebSource(safeSource)
            : new SimpleFileSource(new DirectoryInfo(safeSource));
        var manager = new UpdateManager(updateSource, new UpdateOptions { ExplicitChannel = channel, AllowVersionDowngrade = true });
        if (!manager.IsInstalled) throw new InvalidOperationException("Rollback exige uma instalação gerenciada pelo Velopack.");
        var feed = await updateSource.GetReleaseFeed(NullVelopackLogger.Instance, manager.AppId, channel);
        var targetVersion = SemanticVersion.Parse(version);
        var target = feed.Assets
            .Where(asset => asset.Type == VelopackAssetType.Full)
            .SingleOrDefault(asset => asset.Version == targetVersion)
            ?? throw new InvalidOperationException("A versão anterior conhecida não existe mais no feed configurado.");
        AssertAsset(target);
        if (manager.CurrentVersion is not null)
            policy.AssertVersionDirection(manager.CurrentVersion.ToString(), target.Version.ToString(), true);
        var isDowngrade = manager.CurrentVersion is not null && target.Version < manager.CurrentVersion;
        return new PreparedUpdate(manager, new UpdateInfo(target, isDowngrade), safeSource, channel);
    }

    public static Task DownloadAsync(PreparedUpdate update, Action<int>? progress, CancellationToken cancellationToken)
        => update.Manager.DownloadUpdatesAsync(update.Info, progress, cancellationToken);

    public static void ApplyAndRestart(PreparedUpdate update, string localRoot, DistributionStateStore? stateStore = null)
    {
        var criticalLock = Path.Combine(Path.GetFullPath(localRoot), "distribution-critical.lock");
        if (File.Exists(criticalLock)) throw new InvalidOperationException("Uma sessão crítica está ativa; a atualização não será aplicada agora.");
        stateStore?.RecordPrepared(update);
        update.Manager.ApplyUpdatesAndRestart(update.Info.TargetFullRelease, new[] { "--skip-prerequisites" });
    }

    private static void AssertAsset(VelopackAsset asset)
    {
        var hash = asset.SHA256 ?? string.Empty;
        if (!Regex.IsMatch(hash, "^[0-9a-fA-F]{64}$"))
            throw new InvalidOperationException("O feed não forneceu SHA-256 válido para o pacote alvo.");
        if (asset.Size <= 0 || string.IsNullOrWhiteSpace(asset.FileName))
            throw new InvalidOperationException("O feed forneceu metadados de pacote inválidos.");
    }

    private static string ValidateSource(
        string source,
        string channel,
        DistributionChannelPolicy policy,
        bool allowLocalForRollback = false)
    {
        if (string.IsNullOrWhiteSpace(source)) throw new InvalidOperationException("Fonte de atualização não configurada.");
        if (Uri.TryCreate(source, UriKind.Absolute, out var uri))
        {
            if (!string.IsNullOrEmpty(uri.UserInfo) || !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment))
                throw new InvalidOperationException("A fonte de atualização não pode conter credenciais, query string ou fragmento.");
            if (uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
            {
                policy.AssertRemoteOrigin(channel, uri);
                return uri.ToString().TrimEnd('/');
            }
            var localFixtureAllowed = channel == "development"
                && Environment.GetEnvironmentVariable("CLOUDOS_ALLOW_LOCAL_UPDATE_FIXTURE") == "1"
                && uri.Scheme.Equals(Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase)
                && IPAddressIsLoopback(uri.Host);
            if (localFixtureAllowed) return uri.ToString().TrimEnd('/');
            if (uri.IsFile)
            {
                if (!allowLocalForRollback) policy.AssertLocalSourceAllowed(channel);
                return Path.GetFullPath(uri.LocalPath);
            }
            throw new InvalidOperationException("Feeds remotos exigem HTTPS; HTTP é aceito apenas para fixture loopback de development explicitamente habilitada.");
        }
        var full = Path.GetFullPath(source);
        if (!allowLocalForRollback) policy.AssertLocalSourceAllowed(channel);
        if (!Directory.Exists(full)) throw new DirectoryNotFoundException("Diretório local de atualização não encontrado.");
        return full;
    }

    private static bool IPAddressIsLoopback(string host)
        => host.Equals("localhost", StringComparison.OrdinalIgnoreCase)
           || host == "127.0.0.1"
           || host == "::1";
}
