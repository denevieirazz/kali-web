#pragma once

#include <windows.h>
#include <shlobj.h>

#include <algorithm>
#include <cwctype>
#include <filesystem>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include "native_icon_cache_v12.h"
#include "native_integration_v16_launchers.h"
#include "native_start_index.h"

namespace CloudOS
{
constexpr UINT WM_CLOUDOS_DESKTOP_MODEL_V12 = WM_APP + 0x613;
constexpr UINT WM_CLOUDOS_WIDGETS_V12 = WM_APP + 0x614;

class NativeDesktopModelV12 final
{
public:
    enum class ItemKind
    {
        FileSystem,
        LinuxApp,
    };

    struct Item final
    {
        std::wstring path;
        std::wstring name;
        std::wstring icon_source;
        std::wstring distro;
        std::wstring desktop_id;
        ItemKind kind{ItemKind::FileSystem};
    };

private:
    struct Watch final
    {
        HANDLE handle{INVALID_HANDLE_VALUE};
        std::wstring path;
        bool reload_desktop{};
        bool refresh_start_index{};
    };

    std::mutex mutex_;
    std::vector<Item> items_;
    std::thread worker_;
    HANDLE stop_{};
    HANDLE refresh_{};
    HWND target_{};
    std::wstring directory_override_v12_;

    static std::wstring KnownFolder(REFKNOWNFOLDERID id)
    {
        PWSTR raw = nullptr;
        if (FAILED(SHGetKnownFolderPath(id, KF_FLAG_DEFAULT, nullptr, &raw)) || raw == nullptr) return {};
        std::wstring result(raw);
        CoTaskMemFree(raw);
        return result;
    }

    static void AddDirectoryItems(
        const std::wstring& path,
        std::vector<Item>* next,
        std::set<std::wstring>* seen)
    {
        if (path.empty() || next == nullptr || seen == nullptr) return;
        std::error_code error;
        for (std::filesystem::directory_iterator it(path, error), end;
             !error && it != end && next->size() < 224u;
             it.increment(error))
        {
            const auto name = it->path().filename().wstring();
            if (name.empty() || name[0] == L'.' || name == L"desktop.ini") continue;
            std::wstring absolute = it->path().wstring();
            std::wstring key = absolute;
            std::transform(key.begin(), key.end(), key.begin(), [](wchar_t ch)
            {
                return static_cast<wchar_t>(towlower(ch));
            });
            if (!seen->insert(key).second) continue;

            Item item{};
            item.path = std::move(absolute);
            item.name = name;
            item.icon_source = item.path;
            item.kind = ItemKind::FileSystem;
            next->push_back(std::move(item));
        }
    }

    void Reload(const std::wstring& primary, const std::wstring& public_desktop)
    {
        PerformanceV12::Add(PerformanceV12::FilesystemScan);
        std::vector<Item> next;
        std::set<std::wstring> seen;
        AddDirectoryItems(primary, &next, &seen);
        if (directory_override_v12_.empty())
        {
            AddDirectoryItems(public_desktop, &next, &seen);
            for (const UnifiedAppV16& app : NativeIntegrationV16::EnumerateLinuxGuiApps())
            {
                if (next.size() >= 256u) break;
                std::wstring key = L"linux:" + app.distro + L":" + app.desktop_id;
                std::transform(key.begin(), key.end(), key.begin(), [](wchar_t ch)
                {
                    return static_cast<wchar_t>(towlower(ch));
                });
                if (!seen.insert(key).second) continue;
                const std::wstring shortcut = NativeIntegrationV16::EnsureLinuxLauncherShortcut(app);
                if (shortcut.empty()) continue;

                Item item{};
                item.path = shortcut;
                item.name = app.name;
                item.icon_source = shortcut;
                item.distro = app.distro;
                item.desktop_id = app.desktop_id;
                item.kind = ItemKind::LinuxApp;
                next.push_back(std::move(item));
            }
        }

        std::sort(next.begin(), next.end(), [](const Item& left, const Item& right)
        {
            if (left.kind != right.kind) return left.kind < right.kind;
            return _wcsicmp(left.name.c_str(), right.name.c_str()) < 0;
        });

        for (const Item& item : next)
        {
            const std::wstring& source = item.icon_source.empty() ? item.path : item.icon_source;
            if (source.empty()) continue;
            NativeIconCacheV12::Instance().InvalidateReady(source);
            NativeIconCacheV12::Instance().Warm(source, target_);
        }
        {
            std::scoped_lock lock(mutex_);
            items_ = std::move(next);
        }
        PostMessageW(target_, WM_CLOUDOS_DESKTOP_MODEL_V12, 0, 0);
    }

    static void AddWatch(
        const std::wstring& path,
        bool subtree,
        bool reload_desktop,
        bool refresh_start_index,
        std::vector<Watch>* watches)
    {
        if (path.empty() || watches == nullptr || watches->size() >= MAXIMUM_WAIT_OBJECTS - 2u) return;
        HANDLE handle = FindFirstChangeNotificationW(
            path.c_str(),
            subtree ? TRUE : FALSE,
            FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME | FILE_NOTIFY_CHANGE_LAST_WRITE);
        if (handle == INVALID_HANDLE_VALUE) return;
        watches->push_back({handle, path, reload_desktop, refresh_start_index});
    }

    void Run()
    {
        const HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        const std::wstring primary = directory_override_v12_.empty()
            ? KnownFolder(FOLDERID_Desktop)
            : directory_override_v12_;
        const std::wstring public_desktop = directory_override_v12_.empty()
            ? NativeIntegrationV16::PublicDesktopFolder()
            : std::wstring{};

        std::vector<Watch> watches;
        AddWatch(primary, false, true, false, &watches);
        if (directory_override_v12_.empty())
        {
            AddWatch(public_desktop, false, true, false, &watches);
            AddWatch(KnownFolder(FOLDERID_Programs), true, false, true, &watches);
            AddWatch(KnownFolder(FOLDERID_CommonPrograms), true, false, true, &watches);
            for (const std::wstring& distro : NativeIntegrationV16::EnumerateWslDistributions())
            {
                AddWatch(
                    NativeIntegrationV16::LinuxApplicationsDirectory(distro),
                    false,
                    true,
                    true,
                    &watches);
            }
        }

        Reload(primary, public_desktop);
        for (;;)
        {
            if (WaitForSingleObject(stop_, 0) == WAIT_OBJECT_0) break;
            std::vector<HANDLE> wait_handles;
            wait_handles.reserve(watches.size() + 2u);
            wait_handles.push_back(stop_);
            wait_handles.push_back(refresh_);
            for (const Watch& watch : watches) wait_handles.push_back(watch.handle);

            const DWORD result = WaitForMultipleObjects(
                static_cast<DWORD>(wait_handles.size()),
                wait_handles.data(),
                FALSE,
                INFINITE);
            if (result == WAIT_FAILED || result == WAIT_OBJECT_0) break;

            bool reload_desktop = result == WAIT_OBJECT_0 + 1u;
            if (result >= WAIT_OBJECT_0 + 2u && result < WAIT_OBJECT_0 + wait_handles.size())
            {
                const std::size_t watch_index = static_cast<std::size_t>(result - WAIT_OBJECT_0 - 2u);
                if (watch_index < watches.size())
                {
                    Watch& watch = watches[watch_index];
                    (void)FindNextChangeNotification(watch.handle);
                    if (watch.refresh_start_index)
                        NativeStartIndex::Instance().RefreshAsync();
                    reload_desktop = watch.reload_desktop;
                }
            }
            if (reload_desktop)
                Reload(primary, public_desktop);
        }

        for (Watch& watch : watches)
        {
            if (watch.handle != INVALID_HANDLE_VALUE) FindCloseChangeNotification(watch.handle);
            watch.handle = INVALID_HANDLE_VALUE;
        }
        if (SUCCEEDED(com)) CoUninitialize();
    }

public:
    ~NativeDesktopModelV12() { Stop(); }

    void Start(HWND target, const std::wstring& directory_override = {})
    {
        directory_override_v12_ = directory_override;
        target_ = target;
        stop_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        refresh_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        if (stop_ != nullptr && refresh_ != nullptr) worker_ = std::thread([this] { Run(); });
    }

    void Stop()
    {
        if (stop_ != nullptr) SetEvent(stop_);
        if (worker_.joinable()) worker_.join();
        if (stop_ != nullptr) CloseHandle(stop_);
        if (refresh_ != nullptr) CloseHandle(refresh_);
        stop_ = nullptr;
        refresh_ = nullptr;
    }

    void Refresh() { if (refresh_ != nullptr) SetEvent(refresh_); }

    std::vector<Item> Snapshot()
    {
        std::scoped_lock lock(mutex_);
        return items_;
    }
};
} // namespace CloudOS
