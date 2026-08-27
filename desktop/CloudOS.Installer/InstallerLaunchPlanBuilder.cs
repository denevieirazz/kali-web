namespace CloudOS.Installer;

public static class InstallerLaunchPlanBuilder
{
    public static InstallerLaunchPlan Build(
        InstallerArtifactRecord record,
        string stagedArtifactPath,
        string logPath)
    {
        ArgumentNullException.ThrowIfNull(record);
        ArgumentException.ThrowIfNullOrWhiteSpace(stagedArtifactPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(logPath);

        var staged = Path.GetFullPath(stagedArtifactPath);
        var workingDirectory = Path.GetDirectoryName(staged)
            ?? throw new InvalidOperationException("Staged installer has no working directory.");

        return record.Kind switch
        {
            InstallerArtifactKind.WindowsExecutable => new InstallerLaunchPlan(
                record.ArtifactId,
                record.Kind,
                staged,
                Array.Empty<string>(),
                workingDirectory,
                null,
                MayRequireElevation: true,
                ElevatedBrokerRequired: false,
                record.Sha256).Validate(),

            InstallerArtifactKind.WindowsInstallerPackage => BuildMsi(record, staged, workingDirectory, logPath),

            _ => throw new NotSupportedException($"Installer kind '{record.Kind}' does not have an execution plan.")
        };
    }

    private static InstallerLaunchPlan BuildMsi(
        InstallerArtifactRecord record,
        string staged,
        string workingDirectory,
        string logPath)
    {
        var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        if (string.IsNullOrWhiteSpace(windows))
            throw new InvalidOperationException("Windows directory is unavailable.");
        var msiexec = Path.Combine(windows, "System32", "msiexec.exe");
        if (!File.Exists(msiexec))
            throw new FileNotFoundException("Windows Installer executable was not found.", msiexec);

        var fullLogPath = Path.GetFullPath(logPath);
        var logDirectory = Path.GetDirectoryName(fullLogPath)
            ?? throw new InvalidOperationException("Installer log has no parent directory.");
        Directory.CreateDirectory(logDirectory);

        return new InstallerLaunchPlan(
            record.ArtifactId,
            record.Kind,
            msiexec,
            new[] { "/i", staged, "/norestart", "/L*V", fullLogPath },
            workingDirectory,
            fullLogPath,
            MayRequireElevation: true,
            ElevatedBrokerRequired: false,
            record.Sha256).Validate();
    }
}
