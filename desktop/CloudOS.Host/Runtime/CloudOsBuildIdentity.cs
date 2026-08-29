using System.Reflection;
using System.Text.RegularExpressions;

namespace CloudOS.Host.Runtime;

public static partial class CloudOsBuildIdentity
{
    private const string MetadataKey = "CloudOSSourceRevision";

    public static string SourceRevision
    {
        get
        {
            var value = typeof(CloudOsBuildIdentity).Assembly
                .GetCustomAttributes<AssemblyMetadataAttribute>()
                .FirstOrDefault(attribute => string.Equals(attribute.Key, MetadataKey, StringComparison.Ordinal))
                ?.Value;
            return NormalizeRevision(value) ?? "unknown";
        }
    }

    public static bool MatchesExpected(string? compiledRevision, string? expectedRevision) =>
        NormalizeRevision(compiledRevision) is { } compiled
        && NormalizeRevision(expectedRevision) is { } expected
        && string.Equals(compiled, expected, StringComparison.Ordinal);

    public static bool TryValidateExpected(string? expectedRevision, out string? error)
    {
        if (string.IsNullOrWhiteSpace(expectedRevision))
        {
            error = null;
            return true;
        }

        var expected = NormalizeRevision(expectedRevision);
        if (expected is null)
        {
            error = "O SHA de origem esperado pelo launcher é inválido.";
            return false;
        }

        var compiled = NormalizeRevision(SourceRevision);
        if (compiled is null)
        {
            error = "O Host não contém uma identidade de revisão compilada válida.";
            return false;
        }

        if (!string.Equals(compiled, expected, StringComparison.Ordinal))
        {
            error = $"O Host compilado pertence a outra revisão. esperado={expected} compilado={compiled}";
            return false;
        }

        error = null;
        return true;
    }

    public static string? NormalizeRevision(string? value)
    {
        var candidate = value?.Trim().ToLowerInvariant();
        return candidate is not null && RevisionPattern().IsMatch(candidate) ? candidate : null;
    }

    [GeneratedRegex("^[a-f0-9]{40}$", RegexOptions.CultureInvariant)]
    private static partial Regex RevisionPattern();
}
