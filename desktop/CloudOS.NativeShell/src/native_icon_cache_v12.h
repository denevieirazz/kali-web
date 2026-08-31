#pragma once
#include <windows.h>
#include <shellapi.h>
#include <algorithm>
#include <condition_variable>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <thread>
#include <string>
#include <vector>
#include "native_performance_v12.h"

namespace CloudOS
{
constexpr UINT WM_CLOUDOS_ICON_READY_V12 = WM_APP + 0x612;
class NativeIconCacheV12 final
{
public:
    struct Icon { HICON handle{}; ~Icon() { if (handle) DestroyIcon(handle); } };
private:
    struct Entry { std::shared_ptr<Icon> icon; std::vector<HWND> listeners; bool ready{}; };
    std::mutex mutex_; std::condition_variable condition_; bool stop_{};
    std::map<std::wstring, Entry> entries_; std::deque<std::wstring> pending_; std::thread worker_;
    NativeIconCacheV12() : worker_([this] { Work(); }) {}
    void Work()
    {
        const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        for (;;)
        {
            std::wstring path;
            { std::unique_lock lock(mutex_); condition_.wait(lock, [this]{ return stop_ || !pending_.empty(); }); if (stop_) break; path = std::move(pending_.front()); pending_.pop_front(); }
            SHFILEINFOW info{}; PerformanceV12::IconRead();
            auto icon = std::make_shared<Icon>();
            if (path.starts_with(L"hwnd:"))
            {
                HWND window = reinterpret_cast<HWND>(_wcstoui64(path.c_str()+5, nullptr, 10));
                DWORD_PTR found{};
                SendMessageTimeoutW(window, WM_GETICON, ICON_SMALL2, 0, SMTO_ABORTIFHUNG, 100, &found);
                if (!found) found = static_cast<DWORD_PTR>(GetClassLongPtrW(window, GCLP_HICONSM));
                if (!found) found = static_cast<DWORD_PTR>(GetClassLongPtrW(window, GCLP_HICON));
                if (found) icon->handle = CopyIcon(reinterpret_cast<HICON>(found));
            }
            else if (SHGetFileInfoW(path.c_str(), 0, &info, sizeof(info), SHGFI_ICON | SHGFI_LARGEICON)) icon->handle = info.hIcon;
            std::vector<HWND> listeners;
            { std::scoped_lock lock(mutex_); auto& entry = entries_[path]; entry.icon = std::move(icon); entry.ready = true; listeners.swap(entry.listeners); }
            for (HWND target : listeners) { DWORD pid{}; GetWindowThreadProcessId(target, &pid); if (pid == GetCurrentProcessId()) PostMessageW(target, WM_CLOUDOS_ICON_READY_V12, 0, 0); }
        }
        if (SUCCEEDED(initialized)) CoUninitialize();
    }
public:
    ~NativeIconCacheV12() { { std::scoped_lock lock(mutex_); stop_ = true; } condition_.notify_all(); if(worker_.joinable()) worker_.join(); }
    static NativeIconCacheV12& Instance() { static NativeIconCacheV12 instance; return instance; }
    void InvalidateReady(const std::wstring& path)
    {
        std::scoped_lock lock(mutex_);
        const auto entry = entries_.find(path);
        if (entry != entries_.end() && entry->second.ready) entries_.erase(entry);
    }
    void Warm(const std::wstring& path, HWND target)
    {
        if (path.empty()) return;
        std::scoped_lock lock(mutex_);
        if (entries_.size() >= 512 && !entries_.contains(path))
        {
            for (auto it = entries_.begin(); it != entries_.end(); ++it)
                if (it->second.ready) { entries_.erase(it); break; }
            if (entries_.size() >= 512) return;
        }
        auto [it, inserted] = entries_.try_emplace(path);
        if (inserted) { pending_.push_back(path); condition_.notify_one(); }
        if (!it->second.ready && std::find(it->second.listeners.begin(), it->second.listeners.end(), target) == it->second.listeners.end()) it->second.listeners.push_back(target);
    }
    std::shared_ptr<Icon> Get(const std::wstring& path)
    { std::scoped_lock lock(mutex_); auto found = entries_.find(path); return found == entries_.end() ? nullptr : found->second.icon; }
    static std::wstring WindowKey(HWND window) { return L"hwnd:" + std::to_wstring(reinterpret_cast<UINT_PTR>(window)); }
};
}
