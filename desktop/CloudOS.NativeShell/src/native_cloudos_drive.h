#pragma once

#include <Windows.h>

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace CloudOS
{
struct CloudOSDriveEntry final
{
    std::wstring name;
    bool directory{};
    bool reparse_point{};
    unsigned long long size{};
    FILETIME modified{};
};

struct CloudOSDriveTrashEntry final
{
    std::wstring id;
    std::wstring stored_name;
    std::wstring original_name;
    std::vector<std::wstring> original_path;
    std::wstring deleted_at;
    bool directory{};
    unsigned long long size{};
};

class NativeCloudOSDrive final
{
public:
    static bool EnsureReady(std::wstring* error = nullptr);

    [[nodiscard]] static std::wstring Root();
    [[nodiscard]] static std::wstring HomeRoot();
    [[nodiscard]] static std::wstring ProjectsRoot();
    [[nodiscard]] static std::wstring TrashRoot();

    [[nodiscard]] static bool IsPathInside(const std::wstring& absolute_path);
    static bool SegmentsFromAbsolutePath(
        const std::wstring& absolute_path,
        std::vector<std::wstring>* segments,
        std::wstring* error = nullptr);
    [[nodiscard]] static std::wstring AbsolutePath(
        const std::vector<std::wstring>& segments);

    static bool List(
        const std::vector<std::wstring>& segments,
        std::vector<CloudOSDriveEntry>* entries,
        std::wstring* error = nullptr);

    static bool Read(
        const std::vector<std::wstring>& segments,
        unsigned long long offset,
        std::size_t maximum_bytes,
        std::vector<std::uint8_t>* data,
        bool* eof,
        unsigned long long* total_size,
        std::wstring* error = nullptr);

    static bool Write(
        const std::vector<std::wstring>& segments,
        unsigned long long offset,
        const void* data,
        std::size_t size,
        bool truncate,
        unsigned long long* resulting_size = nullptr,
        std::wstring* error = nullptr);

    static bool Mkdir(
        const std::vector<std::wstring>& segments,
        std::wstring* error = nullptr);

    static bool Move(
        const std::vector<std::wstring>& source,
        const std::vector<std::wstring>& destination,
        std::wstring* error = nullptr);

    static bool Copy(
        const std::vector<std::wstring>& source,
        const std::vector<std::wstring>& destination,
        std::wstring* error = nullptr);

    static bool Trash(
        const std::vector<std::wstring>& segments,
        CloudOSDriveTrashEntry* entry = nullptr,
        std::wstring* error = nullptr);

    static bool ListTrash(
        std::vector<CloudOSDriveTrashEntry>* entries,
        std::wstring* error = nullptr);

    static bool RestoreTrash(
        const std::wstring& id,
        std::wstring* error = nullptr);

    static bool DeleteTrash(
        const std::wstring& id,
        std::wstring* error = nullptr);

    static bool EmptyTrash(
        std::size_t* deleted_count = nullptr,
        std::wstring* error = nullptr);
};

} // namespace CloudOS
