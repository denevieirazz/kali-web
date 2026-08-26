using System.Reflection;
using System.Runtime.CompilerServices;
using CloudOS.Host.Native;

internal static class NativeContainedJobBufferContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        if (Environment.GetCommandLineArgs().Any(argument =>
            argument.StartsWith("--native-contained-fixture-", StringComparison.Ordinal)))
            return;

        var executable = Environment.ProcessPath
            ?? throw new InvalidOperationException("The Host test process path is unavailable.");
        var arguments = string.Equals(Path.GetFileNameWithoutExtension(executable), "dotnet", StringComparison.OrdinalIgnoreCase)
            ? new[] { Assembly.GetExecutingAssembly().Location, "--native-contained-fixture-wait" }
            : new[] { "--native-contained-fixture-wait" };
        var workingDirectory = Path.GetDirectoryName(executable)
            ?? throw new InvalidOperationException("The Host test working directory is unavailable.");
        var spec = NativeProcessLaunchSpec.Create(executable, arguments, workingDirectory);

        using var lease = NativeContainedProcessLauncher.StartSuspended(spec);
        var first = lease.GetMemberProcessIds();
        var second = lease.GetMemberProcessIds();

        Assert(first.Contains(lease.ProcessId), "The first Job query must contain the suspended root process.");
        Assert(second.Contains(lease.ProcessId), "The repeated Job query must contain the suspended root process.");
        Assert(lease.JobProcessListBufferAllocationCount == 1,
            "Repeated Job membership queries must reuse one native process-list buffer.");

        Assert(lease.TryTerminate(3_000, out var terminationError),
            terminationError ?? "The contained Job fixture did not terminate.");
        Assert(lease.JobProcessListBufferAllocationCount == 1,
            "Termination polling must reuse the same native process-list buffer.");

        Console.WriteLine("PASS contained Job process-list buffer reuse contract");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
