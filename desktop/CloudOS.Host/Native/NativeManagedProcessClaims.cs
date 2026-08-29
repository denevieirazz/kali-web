using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CloudOS.Host.Native;

/// <summary>
/// Process identity exported only from the trusted native Host to the backend launch
/// guard. PID alone is not authority because Windows can reuse it; the creation time
/// must match the process observed by the backend probe as well.
/// </summary>
public sealed record NativeManagedProcessClaim(
    [property: JsonPropertyName("processId")] int ProcessId,
    [property: JsonPropertyName("startTimeFileTimeUtc")] string StartTimeFileTimeUtc);

public static class NativeManagedProcessClaims
{
    public const int MaximumClaims = 1_024;

    public static IReadOnlyList<NativeManagedProcessClaim> Capture(
        IEnumerable<NativeContainedProcessLease> leases)
    {
        ArgumentNullException.ThrowIfNull(leases);
        var claims = new Dictionary<int, NativeManagedProcessClaim>();

        foreach (var lease in leases.Distinct())
        {
            if (lease is null || lease.IsDisposed) continue;

            IReadOnlyList<int> processIds;
            try
            {
                processIds = lease.GetMemberProcessIds();
            }
            catch (Exception error) when (error is InvalidOperationException or Win32Exception or NotSupportedException)
            {
                // Omission is fail-closed: the backend will still see the process and reject
                // a same-executable launch unless a later exact PID+creation-time claim exists.
                continue;
            }

            foreach (var processId in processIds)
            {
                if (claims.Count >= MaximumClaims) return Ordered(claims.Values);
                if (processId <= 0 || claims.ContainsKey(processId)) continue;

                try
                {
                    using var process = Process.GetProcessById(processId);
                    var startTimeFileTimeUtc = process.StartTime.ToUniversalTime().ToFileTimeUtc();
                    if (startTimeFileTimeUtc <= 0) continue;
                    claims[processId] = new NativeManagedProcessClaim(
                        processId,
                        startTimeFileTimeUtc.ToString(CultureInfo.InvariantCulture));
                }
                catch (Exception error) when (error is ArgumentException or InvalidOperationException
                    or Win32Exception or NotSupportedException)
                {
                    // A member may exit after the Job query. Never synthesize a claim.
                }
            }
        }

        return Ordered(claims.Values);
    }

    public static string CreateLaunchGuardRequestJson(
        IEnumerable<NativeContainedProcessLease> leases) =>
        JsonSerializer.Serialize(new
        {
            managedProcesses = Capture(leases)
        });

    private static IReadOnlyList<NativeManagedProcessClaim> Ordered(
        IEnumerable<NativeManagedProcessClaim> claims) =>
        claims.OrderBy(claim => claim.ProcessId).ToArray();
}
