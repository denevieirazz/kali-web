#pragma once

#include <Windows.h>

#include <array>
#include <string>
#include <string_view>

#include "native_integration_v16.h"

namespace CloudOS
{
// V17 deliberately builds explicit, user-visible maintenance commands only.
// Execution remains in the first-party Terminal so WinGet/UAC/sudo/package-manager
// prompts stay visible instead of being captured or bypassed by the shell.
class NativePackageMaintenanceV17 final
{
public:
    static bool CanUpgrade(const UnifiedAppV16& app)
    {
        if (app.platform == UnifiedAppPlatformV16::Windows)
            return !app.name.empty() && !SearchExecutable(L"winget.exe").empty();

        if (app.platform != UnifiedAppPlatformV16::Linux || app.distro.empty() ||
            NativeIntegrationV16::WslExecutable().empty())
            return false;

        if (!app.package_manager.empty() && !app.package_id.empty())
            return KnownLinuxManager(app.package_manager) && SafeLinuxToken(app.package_id);
        return SafeLinuxToken(app.desktop_id);
    }

    static std::wstring BuildWindowsUpgradeCommand(const std::wstring& exact_name)
    {
        const std::wstring winget = SearchExecutable(L"winget.exe");
        if (winget.empty() || exact_name.empty()) return {};
        return QuoteWindowsArgument(winget) + L" upgrade --name " + QuoteWindowsArgument(exact_name) +
            L" --exact --accept-package-agreements --accept-source-agreements";
    }

    static bool BuildLinuxUpgradeCommand(
        const UnifiedAppV16& app,
        std::wstring* command_line,
        std::wstring* package_label)
    {
        if (command_line == nullptr || package_label == nullptr ||
            app.platform != UnifiedAppPlatformV16::Linux || app.distro.empty())
            return false;

        const std::wstring wsl = NativeIntegrationV16::WslExecutable();
        if (wsl.empty()) return false;
        const std::wstring prefix = QuoteWindowsArgument(wsl) + L" -d " +
            QuoteWindowsArgument(app.distro) + L" -- ";

        if (!app.package_manager.empty() || !app.package_id.empty())
        {
            if (app.package_manager.empty() || app.package_id.empty() ||
                !KnownLinuxManager(app.package_manager) || !SafeLinuxToken(app.package_id))
                return false;

            if (_wcsicmp(app.package_manager.c_str(), L"flatpak") == 0)
                *command_line = prefix + L"flatpak update " + QuoteWindowsArgument(app.package_id);
            else if (_wcsicmp(app.package_manager.c_str(), L"snap") == 0)
                *command_line = prefix + L"sudo snap refresh " + QuoteWindowsArgument(app.package_id);
            else
                *command_line = prefix + L"sudo apt install --only-upgrade -- " + QuoteWindowsArgument(app.package_id);

            *package_label = app.package_manager + L":" + app.package_id;
            return true;
        }

        // Apt desktop entries usually do not publish a package id. Resolve the owner
        // at execution time with dpkg-query instead of guessing from the display name.
        if (!SafeLinuxToken(app.desktop_id)) return false;
        const std::wstring desktop_path = L"/usr/share/applications/" + app.desktop_id + L".desktop";
        const std::wstring script =
            L"p=$(dpkg-query -S -- '" + desktop_path +
            L"' 2>/dev/null | head -n1 | cut -d: -f1); "
            L"test -n \"$p\" || { echo 'CloudOS: pacote apt nao identificado com seguranca.' >&2; exit 4; }; "
            L"sudo apt install --only-upgrade -- \"$p\"";
        *command_line = prefix + L"sh -lc " + QuoteWindowsArgument(script);
        *package_label = L"apt:auto:" + app.desktop_id;
        return true;
    }

private:
    static std::wstring SearchExecutable(const wchar_t* name)
    {
        std::array<wchar_t, 32768> path{};
        const DWORD length = SearchPathW(
            nullptr,
            name,
            nullptr,
            static_cast<DWORD>(path.size()),
            path.data(),
            nullptr);
        return length > 0 && length < path.size() ? std::wstring(path.data(), length) : std::wstring{};
    }

    static bool SafeLinuxToken(std::wstring_view value)
    {
        if (value.empty() || value.size() > 256u) return false;
        for (const wchar_t ch : value)
        {
            const bool allowed =
                (ch >= L'a' && ch <= L'z') ||
                (ch >= L'A' && ch <= L'Z') ||
                (ch >= L'0' && ch <= L'9') ||
                ch == L'.' || ch == L'+' || ch == L'-' || ch == L'_' || ch == L':' || ch == L'@';
            if (!allowed) return false;
        }
        return true;
    }

    static bool KnownLinuxManager(const std::wstring& value)
    {
        return _wcsicmp(value.c_str(), L"apt") == 0 ||
            _wcsicmp(value.c_str(), L"snap") == 0 ||
            _wcsicmp(value.c_str(), L"flatpak") == 0;
    }

    static std::wstring QuoteWindowsArgument(const std::wstring& value)
    {
        if (value.empty()) return L"\"\"";
        if (value.find_first_of(L" \t\n\v\"") == std::wstring::npos) return value;

        std::wstring result = L"\"";
        std::size_t backslashes = 0;
        for (const wchar_t ch : value)
        {
            if (ch == L'\\')
            {
                ++backslashes;
                continue;
            }
            if (ch == L'\"')
            {
                result.append(backslashes * 2u + 1u, L'\\');
                result.push_back(L'\"');
                backslashes = 0;
                continue;
            }
            result.append(backslashes, L'\\');
            backslashes = 0;
            result.push_back(ch);
        }
        result.append(backslashes * 2u, L'\\');
        result.push_back(L'\"');
        return result;
    }
};
} // namespace CloudOS
