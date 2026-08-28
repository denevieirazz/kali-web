using System.Runtime.CompilerServices;
using CloudOS.Host.Native;

internal static class NativeLaunchStartupToleranceContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        if (Environment.GetCommandLineArgs().Any(argument =>
            argument.StartsWith("--native-contained-fixture-", StringComparison.Ordinal)))
            return;

        if (NativeLaunchContainmentPolicy.WindowCorrelationTimeoutMilliseconds < 20_000)
            throw new InvalidOperationException("Native app window correlation must tolerate helper/splash startup latency.");
        if (NativeLaunchContainmentPolicy.PendingAttachTimeoutMilliseconds < 30_000)
            throw new InvalidOperationException("Native app attachment must tolerate renderer/UI startup latency.");

        Console.WriteLine("PASS native launch startup tolerance contract");
    }
}
