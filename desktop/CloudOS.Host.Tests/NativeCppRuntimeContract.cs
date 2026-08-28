using System.Reflection;
using System.Runtime.CompilerServices;
using CloudOS.Host.Native;

internal static class NativeCppRuntimeContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        if (!OperatingSystem.IsWindows()) return;
        if (Environment.GetCommandLineArgs().Any(argument =>
            argument.StartsWith("--native-contained-fixture-", StringComparison.Ordinal)))
            return;
        if (!CloudOsNativeRuntime.IsAvailable)
        {
            Console.WriteLine("PASS C++ native runtime contract (managed fallback: DLL unavailable)");
            return;
        }

        var executable = Environment.ProcessPath
            ?? throw new InvalidOperationException("The Host test process path is unavailable.");
        var arguments = string.Equals(Path.GetFileNameWithoutExtension(executable), "dotnet", StringComparison.OrdinalIgnoreCase)
            ? new[] { Assembly.GetExecutingAssembly().Location, "--native-contained-fixture-wait" }
            : new[] { "--native-contained-fixture-wait" };
        var workingDirectory = Path.GetDirectoryName(executable)
            ?? throw new InvalidOperationException("The Host test working directory is unavailable.");
        var spec = NativeProcessLaunchSpec.Create(executable, arguments, workingDirectory);

        var previous = Environment.GetEnvironmentVariable("CLOUDOS_NATIVE_RUNTIME");
        try
        {
            Environment.SetEnvironmentVariable("CLOUDOS_NATIVE_RUNTIME", "cpp");
            using var lease = NativeContainedProcessLauncher.StartSuspended(spec);
            Assert(lease.Engine == "cpp", "The contained fixture must use the C++ runtime when explicitly required.");
            Assert(lease.GetMemberProcessIds().Contains(lease.ProcessId),
                "The C++ Job query must contain the suspended root process.");
            Assert(lease.JobProcessListBufferAllocationCount == 1,
                "The C++ runtime must expose one bounded native Job query buffer contract.");
            Assert(lease.TryTerminate(3_000, out var error),
                error ?? "The C++ contained Job fixture did not terminate.");
        }
        finally
        {
            Environment.SetEnvironmentVariable("CLOUDOS_NATIVE_RUNTIME", previous);
        }

        Console.WriteLine("PASS C++ native runtime process/Job contract");
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
