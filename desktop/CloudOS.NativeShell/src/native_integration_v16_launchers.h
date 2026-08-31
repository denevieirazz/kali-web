#pragma once

#include "native_integration_v16.h"

#include <ShlObj.h>
#include <ShObjIdl.h>

#include <cwctype>
#include <filesystem>
#include <mutex>
#include <string>

namespace CloudOS
{
namespace NativeIntegrationV16Detail
{
inline std::wstring KnownFolderV17(REFKNOWNFOLDERID id)
{
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(id, KF_FLAG_DEFAULT, nullptr, &raw)) || raw == nullptr)
        return {};
    std::wstring result(raw);
    CoTaskMemFree(raw);
    return result;
}

inline std::wstring QuoteLauncherArgumentV17(const std::wstring& value)
{
    std::wstring result = L"\"";
    std::size_t backslashes = 0;
    for (wchar_t ch : value)
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

inline std::wstring SafeLinuxShortcutLeafV17(const UnifiedAppV16& app)
{
    std::wstring value = app.distro + L"__" + app.desktop_id;
    for (wchar_t& ch : value)
    {
        if (wcschr(L"\\/:*?\"<>|", ch) != nullptr || std::iswcntrl(ch) != 0)
            ch = L'_';
    }
    if (value.size() > 180u) value.resize(180u);
    return value.empty() ? std::wstring(L"linux-app") : value;
}
} // namespace NativeIntegrationV16Detail

inline std::wstring NativeIntegrationV16::LinuxApplicationsDirectory(const std::wstring& distro)
{
    if (distro.empty()) return {};
    return WslRoot() + L"\\" + distro + L"\\usr\\share\\applications";
}

inline std::wstring NativeIntegrationV16::EnsureLinuxLauncherShortcut(const UnifiedAppV16& app)
{
    if (app.platform != UnifiedAppPlatformV16::Linux || app.distro.empty() || app.desktop_id.empty())
        return {};

    const std::wstring wsl = WslExecutable();
    const std::wstring local = NativeIntegrationV16Detail::KnownFolderV17(FOLDERID_LocalAppData);
    if (wsl.empty() || local.empty()) return {};

    // Desktop and Start may refresh concurrently. Serialize writes to the same
    // managed launcher so a shared .lnk never observes two IPersistFile saves.
    static std::mutex shortcut_mutex;
    std::scoped_lock shortcut_lock(shortcut_mutex);

    const std::filesystem::path directory =
        std::filesystem::path(local) / L"CloudOS" / L"IntegrationV16" / L"LinuxShortcuts";
    std::error_code error;
    std::filesystem::create_directories(directory, error);
    if (error) return {};

    const std::filesystem::path shortcut = directory /
        (NativeIntegrationV16Detail::SafeLinuxShortcutLeafV17(app) + L".lnk");

    const HRESULT com_result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool uninitialize = SUCCEEDED(com_result);

    IShellLinkW* link = nullptr;
    HRESULT result = CoCreateInstance(
        CLSID_ShellLink,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&link));
    if (SUCCEEDED(result) && link != nullptr)
    {
        const std::wstring arguments =
            L"-d " + NativeIntegrationV16Detail::QuoteLauncherArgumentV17(app.distro) +
            L" -- gtk-launch " + NativeIntegrationV16Detail::QuoteLauncherArgumentV17(app.desktop_id);
        (void)link->SetPath(wsl.c_str());
        (void)link->SetArguments(arguments.c_str());
        (void)link->SetDescription(app.name.c_str());
        (void)link->SetIconLocation(wsl.c_str(), 0);

        IPersistFile* persist = nullptr;
        result = link->QueryInterface(IID_PPV_ARGS(&persist));
        if (SUCCEEDED(result) && persist != nullptr)
        {
            result = persist->Save(shortcut.c_str(), TRUE);
            persist->Release();
        }
        link->Release();
    }

    if (uninitialize) CoUninitialize();
    return SUCCEEDED(result) ? shortcut.wstring() : std::wstring{};
}
} // namespace CloudOS
