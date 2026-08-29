#pragma once

#include <windows.h>
#include <shlobj.h>
#include <string>
#include <unordered_map>
#include <vector>
#include <algorithm>
#include <fstream>

namespace CloudOS
{
struct AppUsageStats final
{
    std::wstring app_id;
    int launch_count{0};
    uint64_t last_launch_time{0};
};

class StartMenuMRUTracker final
{
public:
    static StartMenuMRUTracker& Instance()
    {
        static StartMenuMRUTracker instance;
        return instance;
    }

    void Initialize()
    {
        wchar_t app_data[MAX_PATH]{};
        if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, app_data)))
        {
            storage_path_ = std::wstring(app_data) + L"\\CloudOS";
            CreateDirectoryW(storage_path_.c_str(), nullptr);
            storage_path_ += L"\\start_mru.dat";
            Load();
        }
    }

    void RecordLaunch(const wchar_t* app_id)
    {
        if (app_id == nullptr || *app_id == L'\0') return;
        FILETIME ft{};
        GetSystemTimeAsFileTime(&ft);
        uint64_t now = (static_cast<uint64_t>(ft.dwHighDateTime) << 32) | ft.dwLowDateTime;

        auto& stats = usage_map_[app_id];
        stats.app_id = app_id;
        stats.launch_count++;
        stats.last_launch_time = now;
        Save();
    }

    int GetLaunchCount(const wchar_t* app_id) const
    {
        auto it = usage_map_.find(app_id);
        return it != usage_map_.end() ? it->second.launch_count : 0;
    }

    std::vector<std::wstring> GetTopApps(std::size_t limit = 6) const
    {
        std::vector<AppUsageStats> list;
        list.reserve(usage_map_.size());
        for (const auto& [id, stats] : usage_map_)
        {
            list.push_back(stats);
        }

        std::sort(list.begin(), list.end(), [](const AppUsageStats& a, const AppUsageStats& b) {
            if (a.launch_count != b.launch_count) return a.launch_count > b.launch_count;
            return a.last_launch_time > b.last_launch_time;
        });

        std::vector<std::wstring> result;
        for (std::size_t i = 0; i < std::min(limit, list.size()); ++i)
        {
            result.push_back(list[i].app_id);
        }
        return result;
    }

private:
    StartMenuMRUTracker() { Initialize(); }

    void Load()
    {
        if (storage_path_.empty()) return;
        HANDLE file = CreateFileW(storage_path_.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file == INVALID_HANDLE_VALUE) return;

        DWORD bytes_read = 0;
        uint32_t count = 0;
        if (ReadFile(file, &count, sizeof(count), &bytes_read, nullptr) && bytes_read == sizeof(count))
        {
            for (uint32_t i = 0; i < count; ++i)
            {
                uint32_t id_len = 0;
                if (!ReadFile(file, &id_len, sizeof(id_len), &bytes_read, nullptr) || id_len > 256) break;
                std::wstring id(id_len, L'\0');
                if (!ReadFile(file, id.data(), id_len * sizeof(wchar_t), &bytes_read, nullptr)) break;

                int launches = 0;
                uint64_t last_time = 0;
                (void)ReadFile(file, &launches, sizeof(launches), &bytes_read, nullptr);
                (void)ReadFile(file, &last_time, sizeof(last_time), &bytes_read, nullptr);

                usage_map_[id] = AppUsageStats{id, launches, last_time};
            }
        }
        CloseHandle(file);
    }

    void Save() const
    {
        if (storage_path_.empty()) return;
        HANDLE file = CreateFileW(storage_path_.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file == INVALID_HANDLE_VALUE) return;

        DWORD bytes_written = 0;
        uint32_t count = static_cast<uint32_t>(usage_map_.size());
        (void)WriteFile(file, &count, sizeof(count), &bytes_written, nullptr);

        for (const auto& [id, stats] : usage_map_)
        {
            uint32_t id_len = static_cast<uint32_t>(id.size());
            (void)WriteFile(file, &id_len, sizeof(id_len), &bytes_written, nullptr);
            (void)WriteFile(file, id.data(), id_len * sizeof(wchar_t), &bytes_written, nullptr);
            (void)WriteFile(file, &stats.launch_count, sizeof(stats.launch_count), &bytes_written, nullptr);
            (void)WriteFile(file, &stats.last_launch_time, sizeof(stats.last_launch_time), &bytes_written, nullptr);
        }
        CloseHandle(file);
    }

    std::wstring storage_path_;
    std::unordered_map<std::wstring, AppUsageStats> usage_map_;
};
} // namespace CloudOS
