#pragma once
#include <windows.h>
#include <shlobj.h>
#include <algorithm>
#include <filesystem>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include "native_icon_cache_v12.h"

namespace CloudOS
{
constexpr UINT WM_CLOUDOS_DESKTOP_MODEL_V12 = WM_APP + 0x613;
constexpr UINT WM_CLOUDOS_WIDGETS_V12 = WM_APP + 0x614;
class NativeDesktopModelV12 final
{
public:
    struct Item { std::wstring path, name; };
private:
    std::mutex mutex_; std::vector<Item> items_; std::thread worker_;
    HANDLE stop_{}, refresh_{}; HWND target_{}; std::wstring directory_override_v12_;
    void Reload(const std::wstring& path)
    {
        PerformanceV12::Add(PerformanceV12::FilesystemScan);
        std::vector<Item> next; std::error_code error;
        for (std::filesystem::directory_iterator it(path, error), end; !error && it != end && next.size() < 256; it.increment(error))
        {
            const auto name = it->path().filename().wstring();
            if (name.empty() || name[0] == L'.' || name == L"desktop.ini") continue;
            next.push_back({it->path().wstring(), name});
        }
        std::sort(next.begin(), next.end(), [](const Item& a, const Item& b){ return a.name < b.name; });
        for (const auto& item : next)
        {
            NativeIconCacheV12::Instance().InvalidateReady(item.path);
            NativeIconCacheV12::Instance().Warm(item.path, target_);
        }
        { std::scoped_lock lock(mutex_); items_ = std::move(next); }
        PostMessageW(target_, WM_CLOUDOS_DESKTOP_MODEL_V12, 0, 0);
    }
    void Run()
    {
        const HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        PWSTR known{}; std::wstring path;
        if(!directory_override_v12_.empty()) path=directory_override_v12_;
        else if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Desktop, KF_FLAG_DEFAULT, nullptr, &known)) && known) { path = known; CoTaskMemFree(known); }
        HANDLE directory = path.empty() ? INVALID_HANDLE_VALUE : CreateFileW(path.c_str(), FILE_LIST_DIRECTORY,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, nullptr);
        HANDLE ready = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        OVERLAPPED operation{}; operation.hEvent = ready;
        alignas(DWORD) BYTE buffer[16384]{};
        bool pending = false;
        const auto arm = [&] {
            if(directory==INVALID_HANDLE_VALUE || !ready || pending) return;
            ResetEvent(ready);
            pending=ReadDirectoryChangesW(directory,buffer,sizeof(buffer),FALSE,
                FILE_NOTIFY_CHANGE_FILE_NAME|FILE_NOTIFY_CHANGE_DIR_NAME|FILE_NOTIFY_CHANGE_LAST_WRITE,
                nullptr,&operation,nullptr)!=FALSE;
        };
        arm();
        if(!path.empty()) Reload(path);
        for(;;)
        {
            if(WaitForSingleObject(stop_,0)==WAIT_OBJECT_0) break;
            HANDLE waits[]{stop_, refresh_, ready};
            const DWORD result = WaitForMultipleObjects(pending ? 3u : 2u, waits, FALSE, INFINITE);
            if (result == WAIT_OBJECT_0 || result == WAIT_FAILED) break;
            if (result == WAIT_OBJECT_0 + 2) { DWORD bytes{}; (void)GetOverlappedResult(directory, &operation, &bytes, TRUE); pending = false; arm(); }
            if (!path.empty()) Reload(path);
        }
        if (pending) { CancelIoEx(directory, &operation); DWORD bytes{}; (void)GetOverlappedResult(directory, &operation, &bytes, TRUE); }
        if (directory != INVALID_HANDLE_VALUE) CloseHandle(directory);
        if (ready) CloseHandle(ready);
        if (SUCCEEDED(com)) CoUninitialize();
    }
public:
    ~NativeDesktopModelV12() { Stop(); }
    void Start(HWND target, const std::wstring& directory_override = {})
    {
        directory_override_v12_=directory_override;
        target_ = target; stop_ = CreateEventW(nullptr, TRUE, FALSE, nullptr); refresh_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        if (stop_ && refresh_) worker_ = std::thread([this] { Run(); });
    }
    void Stop()
    { if(stop_) SetEvent(stop_); if(worker_.joinable()) worker_.join(); if(stop_) CloseHandle(stop_); if(refresh_) CloseHandle(refresh_); stop_ = refresh_ = nullptr; }
    void Refresh() { if(refresh_) SetEvent(refresh_); }
    std::vector<Item> Snapshot() { std::scoped_lock lock(mutex_); return items_; }
};
}
