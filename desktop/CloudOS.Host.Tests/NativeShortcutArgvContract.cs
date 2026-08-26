using System.Runtime.CompilerServices;
using CloudOS.Host.Native;

internal static class NativeShortcutArgvContract
{
    [ModuleInitializer]
    internal static void Validate()
    {
        if (Environment.GetCommandLineArgs().Any(argument =>
            argument.StartsWith("--native-contained-fixture-", StringComparison.Ordinal)))
            return;

        var admission = NativeLaunchContainmentPolicy.EvaluateLaunchKind("windows-shortcut-argv");
        if (!admission.Allowed)
            throw new InvalidOperationException("windows-shortcut-argv must be admitted as a direct Host launch kind.");
        if (!NativeLaunchContainmentPolicy.AllowsArgumentVector("windows-shortcut-argv", 3))
            throw new InvalidOperationException("A validated shortcut argv vector must cross the Host boundary.");
        if (NativeLaunchContainmentPolicy.AllowsArgumentVector("windows-shortcut-argv", 0))
            throw new InvalidOperationException("The argv shortcut launch kind must not accept an empty vector.");
        if (!NativeLaunchContainmentPolicy.AllowsArgumentVector("windows-shortcut-direct", 0))
            throw new InvalidOperationException("Argument-free direct shortcuts must remain supported.");
        if (NativeLaunchContainmentPolicy.AllowsArgumentVector("windows-shortcut-direct", 1))
            throw new InvalidOperationException("Argument-bearing shortcuts must use the explicit argv launch kind.");

        Console.WriteLine("PASS native shortcut argv launch contract");
    }
}
