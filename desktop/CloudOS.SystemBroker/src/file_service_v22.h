#pragma once

#include "job_manager_v21.h"
#include "protocol_v21.h"

#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>

#include <atomic>
#include <chrono>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

namespace CloudOS
{

enum class LocationKind
{
    Windows,
    Wsl,
    Network,
    CloudOS,
    Virtual
};

enum class FileKind
{
    Folder,
    Text,
    Image,
    Audio,
    Video,
    Document,
    Archive,
    Executable,
    Code,
    Unknown
};

enum class FileSortField
{
    Name,
    Type,
    Size,
    Modified
};

struct FileSortOptions
{
    FileSortField field{FileSortField::Name};
    bool ascending{true};
    bool directories_first{true};
};

struct FileFilterOptions
{
    bool folders_only{false};
    bool files_only{false};
    bool show_hidden{false};
    std::string extension;
    std::string search_text;
};

struct CloudFileItemMetadata
{
    std::string id;
    std::string name;
    std::string display_name;
    std::string path;
    std::string canonical_path;
    LocationKind location_kind{LocationKind::Windows};
    FileKind file_kind{FileKind::Unknown};
    std::string extension;
    int64_t size{0};
    std::string modified_time;
    std::string created_time;
    bool is_directory{false};
    bool is_hidden{false};
    bool is_readonly{false};
    bool is_system{false};
    bool is_symlink{false};
    std::string distro;
    std::string mime_or_type;
    std::string icon_key;
    bool can_rename{true};
    bool can_delete{true};
    bool can_open{true};
    bool can_open_with{true};
    bool can_copy{true};
    bool can_move{true};
};

struct DriveInfo
{
    std::string letter_or_path;
    std::string label;
    std::string filesystem;
    uint64_t total_bytes{0};
    uint64_t free_bytes{0};
    bool is_removable{false};
    bool is_ready{false};
    std::string drive_type;
};

struct KnownFolderInfo
{
    std::string id;
    std::string name;
    std::string path;
    std::string icon_key;
};

struct OpenWithAppInfo
{
    std::string app_id;
    std::string name;
    std::string platform; // "windows" or "linux"
    std::string distro;
    std::string icon_key;
    bool is_recommended{false};
    bool is_default{false};
    std::string executable_path;
};

class FileServiceV22 final
{
public:
    static FileServiceV22& Instance();

    FileServiceV22();
    ~FileServiceV22();

    FileServiceV22(const FileServiceV22&) = delete;
    FileServiceV22& operator=(const FileServiceV22&) = delete;

    // Core Directory and Metadata APIs
    JsonObject ListDirectory(
        const std::string& path_or_target,
        size_t page_size = 200,
        const std::string& continuation_token = "",
        const FileSortOptions& sort = {},
        const FileFilterOptions& filter = {});

    JsonObject GetMetadata(const std::string& path_or_id);
    JsonObject GetDrives();
    JsonObject GetKnownFolders();
    JsonObject ResolvePath(const std::string& path_or_target);

    // Operations
    JsonObject CreateFolder(const std::string& parent_path, const std::string& folder_name);
    JsonObject RenameItem(const std::string& item_path, const std::string& new_name);
    JsonObject DeleteItems(const std::vector<std::string>& paths, bool permanent);

    // Asynchronous Jobs via JobManagerV21
    std::string StartCopyJob(
        const std::vector<std::string>& sources,
        const std::string& destination,
        const std::string& overwrite_policy = "ask");

    std::string StartMoveJob(
        const std::vector<std::string>& sources,
        const std::string& destination,
        const std::string& overwrite_policy = "ask");

    std::string StartSearchJob(
        const std::string& root_path,
        const std::string& query,
        bool recursive = true,
        size_t max_results = 500);

    // Open & Open With
    JsonObject OpenDefault(const std::string& path_or_id);
    JsonObject GetOpenWithList(const std::string& path_or_id);
    JsonObject LaunchOpenWith(
        const std::string& path_or_id,
        const std::string& app_id,
        const std::string& platform,
        const std::string& distro = "");

    // Path & Distro Mapping Helpers
    bool TryMapWindowsPathToLinux(
        const std::string& distro,
        const std::wstring& windows_path,
        std::wstring* out_linux_path);

    bool IsValidFileName(const std::wstring& name, std::string* out_reason = nullptr);
    std::wstring CanonicalizePath(const std::wstring& input);

private:
    std::wstring ResolveVirtualTarget(const std::string& target);
    CloudFileItemMetadata BuildMetadataFromFindData(
        const std::wstring& parent_dir,
        const WIN32_FIND_DATAW& fd,
        LocationKind location_kind,
        const std::string& distro);

    CloudFileItemMetadata BuildMetadataForPath(const std::wstring& full_path);

    bool ExecuteIFileOperation(
        UINT operation_type, // 1: Copy, 2: Move, 3: Delete, 4: Rename
        const std::vector<std::wstring>& sources,
        const std::wstring& destination,
        bool allow_undo,
        std::string* out_error);

    FileKind DetectFileKind(const std::wstring& extension, bool is_directory);
    std::string ResolveIconKey(FileKind kind, const std::wstring& extension, bool is_directory);

    std::mutex mutex_;
    std::atomic_uint64_t operations_generation_{1};
};

} // namespace CloudOS
