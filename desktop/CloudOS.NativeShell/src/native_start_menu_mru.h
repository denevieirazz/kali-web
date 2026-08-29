#pragma once

#include <windows.h>
#include <knownfolders.h>
#include <shlobj.h>

#include <algorithm>
#include <cstdint>
#include <limits>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace CloudOS
{
struct AppUsageStats final
{
    std::wstring app_id;
    std::uint32_t launch_count{0};
    std::uint64_t last_launch_time{0};
};

class StartMenuMRUTracker final
{
public:
    static StartMenuMRUTracker& Instance()
    {
        static StartMenuMRUTracker instance;
        return instance;
    }

    void RecordLaunch(const wchar_t* app_id)
    {
        if (app_id == nullptr || *app_id == L'\0')
        {
            return;
        }

        FILETIME file_time{};
        GetSystemTimeAsFileTime(&file_time);
        const std::uint64_t now =
            (static_cast<std::uint64_t>(file_time.dwHighDateTime) << 32u) |
            static_cast<std::uint64_t>(file_time.dwLowDateTime);

        std::scoped_lock lock(mutex_);
        auto& stats = usage_map_[app_id];
        stats.app_id = app_id;
        if (stats.launch_count != (std::numeric_limits<std::uint32_t>::max)())
        {
            ++stats.launch_count;
        }
        stats.last_launch_time = now;
        SaveLocked();
    }

    std::uint32_t GetLaunchCount(const wchar_t* app_id) const
    {
        if (app_id == nullptr)
        {
            return 0;
        }

        std::scoped_lock lock(mutex_);
        const auto iterator = usage_map_.find(app_id);
        return iterator != usage_map_.end() ? iterator->second.launch_count : 0;
    }

    std::vector<std::wstring> GetTopApps(std::size_t limit = 6) const
    {
        std::scoped_lock lock(mutex_);

        std::vector<AppUsageStats> list;
        list.reserve(usage_map_.size());
        for (const auto& entry : usage_map_)
        {
            list.push_back(entry.second);
        }

        std::sort(
            list.begin(),
            list.end(),
            [](const AppUsageStats& first, const AppUsageStats& second)
            {
                if (first.launch_count != second.launch_count)
                {
                    return first.launch_count > second.launch_count;
                }
                return first.last_launch_time > second.last_launch_time;
            });

        std::vector<std::wstring> result;
        const std::size_t count = std::min(limit, list.size());
        result.reserve(count);
        for (std::size_t index = 0; index < count; ++index)
        {
            result.push_back(list[index].app_id);
        }
        return result;
    }

private:
    StartMenuMRUTracker()
    {
        PWSTR local_app_data = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(
                FOLDERID_LocalAppData,
                KF_FLAG_DEFAULT,
                nullptr,
                &local_app_data)) &&
            local_app_data != nullptr)
        {
            storage_directory_ = local_app_data;
            CoTaskMemFree(local_app_data);

            storage_directory_ += L"\\CloudOS";
            (void)CreateDirectoryW(storage_directory_.c_str(), nullptr);
            storage_path_ = storage_directory_ + L"\\start_mru.dat";
            Load();
        }
        else if (local_app_data != nullptr)
        {
            CoTaskMemFree(local_app_data);
        }
    }

    static bool ReadExact(HANDLE file, void* buffer, DWORD bytes)
    {
        DWORD bytes_read = 0;
        return ReadFile(file, buffer, bytes, &bytes_read, nullptr) != FALSE &&
            bytes_read == bytes;
    }

    static bool WriteExact(HANDLE file, const void* buffer, DWORD bytes)
    {
        DWORD bytes_written = 0;
        return WriteFile(file, buffer, bytes, &bytes_written, nullptr) != FALSE &&
            bytes_written == bytes;
    }

    void Load()
    {
        if (storage_path_.empty())
        {
            return;
        }

        HANDLE file = CreateFileW(
            storage_path_.c_str(),
            GENERIC_READ,
            FILE_SHARE_READ,
            nullptr,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
            nullptr);
        if (file == INVALID_HANDLE_VALUE)
        {
            return;
        }

        std::uint32_t count = 0;
        if (!ReadExact(file, &count, sizeof(count)) || count > 512u)
        {
            CloseHandle(file);
            return;
        }

        for (std::uint32_t index = 0; index < count; ++index)
        {
            std::uint32_t id_length = 0;
            if (!ReadExact(file, &id_length, sizeof(id_length)) ||
                id_length == 0 ||
                id_length > 128u)
            {
                break;
            }

            std::wstring id(id_length, L'\0');
            const DWORD id_bytes =
                static_cast<DWORD>(id_length * sizeof(wchar_t));
            if (!ReadExact(file, id.data(), id_bytes))
            {
                break;
            }

            std::uint32_t launches = 0;
            std::uint64_t last_time = 0;
            if (!ReadExact(file, &launches, sizeof(launches)) ||
                !ReadExact(file, &last_time, sizeof(last_time)))
            {
                break;
            }

            usage_map_[id] = AppUsageStats{id, launches, last_time};
        }

        CloseHandle(file);
    }

    void SaveLocked() const
    {
        if (storage_path_.empty() || storage_directory_.empty())
        {
            return;
        }

        const std::wstring temporary_path = storage_path_ + L".tmp";
        HANDLE file = CreateFileW(
            temporary_path.c_str(),
            GENERIC_WRITE,
            0,
            nullptr,
            CREATE_ALWAYS,
            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH,
            nullptr);
        if (file == INVALID_HANDLE_VALUE)
        {
            return;
        }

        std::uint32_t count = 0;
        for (const auto& entry : usage_map_)
        {
            if (!entry.second.app_id.empty() &&
                entry.second.app_id.size() <= 128u &&
                count < 512u)
            {
                ++count;
            }
        }

        bool success = WriteExact(file, &count, sizeof(count));
        std::uint32_t written_entries = 0;
        for (const auto& entry : usage_map_)
        {
            if (!success || written_entries >= count)
            {
                break;
            }

            const AppUsageStats& stats = entry.second;
            if (stats.app_id.empty() || stats.app_id.size() > 128u)
            {
                continue;
            }

            const std::uint32_t id_length =
                static_cast<std::uint32_t>(stats.app_id.size());
            const DWORD id_bytes =
                static_cast<DWORD>(id_length * sizeof(wchar_t));

            success =
                WriteExact(file, &id_length, sizeof(id_length)) &&
                WriteExact(file, stats.app_id.data(), id_bytes) &&
                WriteExact(file, &stats.launch_count, sizeof(stats.launch_count)) &&
                WriteExact(file, &stats.last_launch_time, sizeof(stats.last_launch_time));

            if (success)
            {
                ++written_entries;
            }
        }

        if (success)
        {
            (void)FlushFileBuffers(file);
        }
        CloseHandle(file);

        if (!success ||
            !MoveFileExW(
                temporary_path.c_str(),
                storage_path_.c_str(),
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        {
            (void)DeleteFileW(temporary_path.c_str());
        }
    }

    mutable std::mutex mutex_;
    std::wstring storage_directory_;
    std::wstring storage_path_;
    std::unordered_map<std::wstring, AppUsageStats> usage_map_;
};
} // namespace CloudOS
