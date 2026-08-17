using System.Text.Json;
using System.Text.Json.Serialization;
using Velopack;

namespace CloudOS.Bootstrap;

public sealed class DistributionChannelDefinition
{
    [JsonPropertyName("requiresAuthenticode")] public bool RequiresAuthenticode { get; init; }
    [JsonPropertyName("allowLocalSource")] public bool AllowLocalSource { get; init; }
    [JsonPropertyName("approvedOrigins")] public string[] ApprovedOrigins { get; init; } = Array.Empty<string>();
}

public sealed class DistributionChannelTransition
{
    [JsonPropertyName("from")] public string From { get; init; } = string.Empty;
    [JsonPropertyName("to")] public string To { get; init; } = string.Empty;
}

public sealed class DistributionChannelPolicy
{
    [JsonPropertyName("schemaVersion")] public int SchemaVersion { get; init; }
    [JsonPropertyName("channels")] public Dictionary<string, DistributionChannelDefinition> Channels { get; init; } = new(StringComparer.OrdinalIgnoreCase);
    [JsonPropertyName("transitions")] public DistributionChannelTransition[] Transitions { get; init; } = Array.Empty<DistributionChannelTransition>();

    public static DistributionChannelPolicy Load(string? baseDirectory = null)
    {
        var root = Path.GetFullPath(baseDirectory ?? AppContext.BaseDirectory);
        var candidates = new[]
        {
            Path.Combine(root, "meta", "channels.json"),
            Path.Combine(root, "productization", "channels.json"),
            Path.Combine(root, "channels.json")
        };
        foreach (var path in candidates)
        {
            if (!File.Exists(path)) continue;
            try
            {
                var policy = JsonSerializer.Deserialize<DistributionChannelPolicy>(
                    File.ReadAllText(path), new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                if (policy is null) continue;
                policy.ValidateContract();
                return policy;
            }
            catch (JsonException error)
            {
                throw new InvalidOperationException("A matriz de canais está corrompida.", error);
            }
        }
        throw new InvalidOperationException("A matriz de canais channels.json não foi encontrada.");
    }

    public string Normalize(string channel)
    {
        var normalized = (channel ?? string.Empty).Trim().ToLowerInvariant();
        if (!Channels.ContainsKey(normalized)) throw new InvalidOperationException("Canal de atualização inválido.");
        return normalized;
    }

    public bool IsTransitionAllowed(string from, string to)
    {
        from = Normalize(from); to = Normalize(to);
        return Transitions.Any(item =>
            string.Equals(item.From, from, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(item.To, to, StringComparison.OrdinalIgnoreCase));
    }

    public void AssertTransition(string currentChannel, string targetChannel, bool explicitChange)
    {
        currentChannel = Normalize(currentChannel); targetChannel = Normalize(targetChannel);
        if (!string.Equals(currentChannel, targetChannel, StringComparison.OrdinalIgnoreCase) && !explicitChange)
            throw new InvalidOperationException($"Troca silenciosa de canal rejeitada: {currentChannel} -> {targetChannel}.");
        if (!IsTransitionAllowed(currentChannel, targetChannel))
            throw new InvalidOperationException($"Transição de canal não permitida: {currentChannel} -> {targetChannel}.");
    }

    public void AssertRuntimeReady(string channel, ProductMetadata metadata)
    {
        channel = Normalize(channel);
        var definition = Channels[channel];
        if (channel == "stable" && !metadata.StableUpdatesEnabled)
            throw new InvalidOperationException("O canal stable permanece desativado neste lote experimental.");
        if (definition.RequiresAuthenticode && string.Equals(metadata.Signing, "unsigned-development", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"O canal {channel} exige assinatura; assinatura de distribuição ainda não está configurada.");
    }

    public void AssertRemoteOrigin(string channel, Uri uri)
    {
        channel = Normalize(channel);
        var definition = Channels[channel];
        if (channel == "development") return;
        var actual = CanonicalOrigin(uri);
        var allowed = definition.ApprovedOrigins.Any(origin =>
            Uri.TryCreate(origin, UriKind.Absolute, out var approved) &&
            string.Equals(CanonicalOrigin(approved), actual, StringComparison.OrdinalIgnoreCase));
        if (!allowed) throw new InvalidOperationException($"Origem de atualização não aprovada para o canal {channel}.");
    }

    public void AssertLocalSourceAllowed(string channel)
    {
        channel = Normalize(channel);
        if (!Channels[channel].AllowLocalSource)
            throw new InvalidOperationException($"Fonte local não é aprovada para o canal {channel}.");
    }

    public void AssertVersionDirection(string currentVersion, string targetVersion, bool allowExplicitDowngrade)
    {
        var current = SemanticVersion.Parse(currentVersion);
        var target = SemanticVersion.Parse(targetVersion);
        if (target < current && !allowExplicitDowngrade)
            throw new InvalidOperationException("Downgrade silencioso foi rejeitado.");
    }

    private void ValidateContract()
    {
        if (SchemaVersion != 1) throw new InvalidOperationException("Versão da matriz de canais não suportada.");
        foreach (var required in new[] { "development", "preview", "stable" })
            if (!Channels.ContainsKey(required)) throw new InvalidOperationException($"Canal obrigatório ausente: {required}.");
        foreach (var transition in Transitions)
        {
            if (string.IsNullOrWhiteSpace(transition.From) || string.IsNullOrWhiteSpace(transition.To))
                throw new InvalidOperationException("Transição de canal inválida.");
            _ = Normalize(transition.From); _ = Normalize(transition.To);
        }
    }

    private static string CanonicalOrigin(Uri uri)
    {
        var builder = new UriBuilder(uri.Scheme, uri.Host, uri.IsDefaultPort ? -1 : uri.Port);
        return builder.Uri.GetLeftPart(UriPartial.Authority).TrimEnd('/');
    }
}
