using CloudOS.Host.Native;
using CloudOS.Installer;

namespace CloudOS.Host.Installer;

public sealed record InstallerContainedLaunchAdmission(
    bool Allowed,
    string? ErrorCode,
    string? Message,
    NativeProcessLaunchSpec? LaunchSpec)
{
    public static InstallerContainedLaunchAdmission Permit(NativeProcessLaunchSpec launchSpec) =>
        new(true, null, null, launchSpec ?? throw new ArgumentNullException(nameof(launchSpec)));

    public static InstallerContainedLaunchAdmission Deny(string errorCode, string message) =>
        new(false, errorCode, message, null);
}

/// <summary>
/// Converts an already-consumed installer capability into the existing CloudOS
/// suspended/Job-contained process boundary. This type never accepts web paths.
/// MSI remains broker-only until Windows Installer service/elevation lifecycle is
/// physically proven to remain inside the CloudOS containment contract.
/// </summary>
public static class InstallerContainedLaunchPolicy
{
    public const string BrokerRequiredCode = "INSTALLER_BROKER_REQUIRED";
    public const string UnsupportedCode = "INSTALLER_EXECUTION_UNSUPPORTED";
    public const string InvalidPlanCode = "INSTALLER_LAUNCH_PLAN_INVALID";

    public static InstallerContainedLaunchAdmission Evaluate(InstallerLaunchPlan plan)
    {
        ArgumentNullException.ThrowIfNull(plan);

        InstallerLaunchPlan validated;
        try
        {
            validated = plan.Validate();
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException)
        {
            return InstallerContainedLaunchAdmission.Deny(
                InvalidPlanCode,
                "The installer launch capability is invalid.");
        }

        if (validated.ElevatedBrokerRequired)
        {
            return InstallerContainedLaunchAdmission.Deny(
                BrokerRequiredCode,
                "This installer requires the CloudOS privileged installation broker.");
        }

        if (validated.Kind == InstallerArtifactKind.WindowsInstallerPackage)
        {
            return InstallerContainedLaunchAdmission.Deny(
                BrokerRequiredCode,
                "MSI installation is blocked until the privileged Windows Installer lifecycle is qualified by CloudOS.");
        }

        if (validated.Kind != InstallerArtifactKind.WindowsExecutable)
        {
            return InstallerContainedLaunchAdmission.Deny(
                UnsupportedCode,
                "This installer format cannot enter the contained Windows runtime.");
        }

        try
        {
            return InstallerContainedLaunchAdmission.Permit(
                NativeProcessLaunchSpec.Create(
                    validated.ExecutablePath,
                    validated.Arguments,
                    validated.WorkingDirectory));
        }
        catch (Exception error) when (error is ArgumentException or IOException or NotSupportedException or UnauthorizedAccessException)
        {
            return InstallerContainedLaunchAdmission.Deny(
                InvalidPlanCode,
                "The installer launch capability cannot be represented as a safe contained process.");
        }
    }
}
