#pragma once

#include <Windows.h>

#include <string>
#include <vector>

namespace CloudOS
{
enum class UnifiedAppPlatformV16
{
    Windows,
    Linux,
};

struct UnifiedAppV16 final
{
    std::wstring name;
    std::wstring launch_target;
    std::wstring source;
    std::wstring uninstall_command;
    std::wstring distro;
    std::wstring desktop_id;
    std::wstring package_manager;
    std::wstring package_id;
    UnifiedAppPlatformV16 platform{UnifiedAppPlatformV16::Windows};
    bool can_launch{};
    bool can_uninstall{};
};

class NativeIntegrationV16 final
{
public:
    static std::vector<UnifiedAppV16> EnumerateWindowsInstalledApps();
    static std::vector<UnifiedAppV16> EnumerateLinuxGuiApps();
    static std::vector<std::wstring> EnumerateWslDistributions();

    static bool LaunchLinuxApp(HWND owner, const UnifiedAppV16& app);
    static bool LaunchWindowsUninstaller(HWND owner, const UnifiedAppV16& app);
    static bool ResolveLinuxRemovalCommand(
        const UnifiedAppV16& app,
        std::wstring* command_line,
        std::wstring* package_label);

    static bool IsWinGetAvailable();
    static std::wstring BuildWingetInstallCommand(const std::wstring& exact_name);
    static std::wstring BuildWingetUninstallCommand(const std::wstring& exact_name);
    static std::wstring BuildLinuxInstallCommand(
        const std::wstring& distro,
        const std::wstring& package_name);

    // V17 reuses the V16 discovery/launch boundary instead of teaching Start or
    // Desktop how to construct WSL launch commands independently.
    static std::wstring LinuxApplicationsDirectory(const std::wstring& distro);
    static std::wstring EnsureLinuxLauncherShortcut(const UnifiedAppV16& app);

    // V18 keeps Windows<->Linux path translation and WSLg file launch inside
    // the same V16 integration authority. Files/Open-With only consume these
    // operations and never construct wsl.exe/wslpath/gtk-launch commands.
    static bool TryMapWindowsPathToLinux(
        const UnifiedAppV16& app,
        const std::wstring& windows_path,
        std::wstring* linux_path);
    static bool LaunchLinuxAppWithPath(
        HWND owner,
        const UnifiedAppV16& app,
        const std::wstring& windows_path);

    static std::wstring DownloadsFolder();
    static std::wstring DesktopFolder();
    static std::wstring PublicDesktopFolder();
    static std::wstring DocumentsFolder();
    static std::wstring WslRoot();
    static std::wstring WslExecutable();
};
} // namespace CloudOS
