#include "file_service_v21.h"
#include "wsl_service_v21.h"

#include <Windows.h>
#include <objbase.h>
#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <array>
#include <filesystem>
#include <iomanip>
#include <sstream>

namespace CloudOS
{
namespace
{
namespace fs = std::filesystem;
constexpr std::size_t kMaxItems = 500;

std::string WideToUtf8(const std::wstring& value)
{
    if (value.empty()) return {};
    const int required = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0) return {};
    std::string output(static_cast<std::size_t>(required), '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            output.data(),
            required,
            nullptr,
            nullptr) != required)
    {
        return {};
    }
    return output;
}

std::wstring Utf8ToWide(const std::string& value)
{
    if (value.empty()) return {};
    const int required = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (required <= 0) return {};
    std::wstring output(static_cast<std::size_t>(required), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            output.data(),
            required) != required)
    {
        return {};
    }
    return output;
}

std::wstring KnownFolder(REFKNOWNFOLDERID id)
{
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(id, KF_FLAG_DEFAULT, nullptr, &raw)) || raw == nullptr)
    {
        return {};
    }
    std::wstring result(raw);
    CoTaskMemFree(raw);
    return result;
}

std::wstring SystemVolumeRoot()
{
    std::array<wchar_t, MAX_PATH> windows{};
    const UINT length = GetWindowsDirectoryW(windows.data(), static_cast<UINT>(windows.size()));
    if (length == 0 || length >= windows.size()) return L"C:\\";
    fs::path path(windows.data());
    return path.root_path().empty() ? L"C:\\" : path.root_path().wstring();
}

std::wstring CloudDriveRoot()
{
    std::array<wchar_t, 32768> override_path{};
    const DWORD length = GetEnvironmentVariableW(
        L"CLOUDOS_DRIVE_DIR",
        override_path.data(),
        static_cast<DWORD>(override_path.size()));
    if (length > 0 && length < override_path.size())
    {
        return fs::path(override_path.data()).lexically_normal().wstring();
    }

    const std::wstring local = KnownFolder(FOLDERID_LocalAppData);
    if (local.empty()) return {};
    return (fs::path(local) / L"CloudOS" / L"Drive").lexically_normal().wstring();
}

std::wstring WslRoot()
{
    const auto distros = WslServiceV21::Instance().GetDistributions();
    if (distros.empty()) return {};

    const int required = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        distros.front().data(),
        static_cast<int>(distros.front().size()),
        nullptr,
        0);
    if (required <= 0) return {};
    std::wstring distro(static_cast<std::size_t>(required), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            distros.front().data(),
            static_cast<int>(distros.front().size()),
            distro.data(),
            required) != required)
    {
        return {};
    }
    return L"\\\\wsl.localhost\\" + distro + L"\\";
}

std::string FormatSize(ULONGLONG bytes)
{
    static constexpr const char* units[] = {"B", "KB", "MB", "GB", "TB"};
    double value = static_cast<double>(bytes);
    std::size_t unit = 0;
    while (value >= 1024.0 && unit + 1 < std::size(units))
    {
        value /= 1024.0;
        ++unit;
    }

    std::ostringstream out;
    if (unit == 0)
    {
        out << static_cast<unsigned long long>(bytes) << ' ' << units[unit];
    }
    else
    {
        out << std::fixed << std::setprecision(value >= 10.0 ? 0 : 1)
            << value << ' ' << units[unit];
    }
    return out.str();
}

std::string FormatModified(const FILETIME& utc)
{
    FILETIME local{};
    SYSTEMTIME system{};
    if (!FileTimeToLocalFileTime(&utc, &local) || !FileTimeToSystemTime(&local, &system))
    {
        return {};
    }
    char buffer[32]{};
    sprintf_s(
        buffer,
        "%04u-%02u-%02u %02u:%02u",
        static_cast<unsigned>(system.wYear),
        static_cast<unsigned>(system.wMonth),
        static_cast<unsigned>(system.wDay),
        static_cast<unsigned>(system.wHour),
        static_cast<unsigned>(system.wMinute));
    return buffer;
}

std::string ExtensionOf(const std::wstring& name)
{
    const fs::path path(name);
    std::wstring extension = path.extension().wstring();
    if (!extension.empty() && extension.front() == L'.') extension.erase(extension.begin());
    return WideToUtf8(extension);
}

FileItemV21 VirtualFolder(
    const std::string& name,
    const std::wstring& path,
    const std::string& source)
{
    FileItemV21 item;
    item.name = name;
    item.path = WideToUtf8(path);
    item.is_folder = true;
    item.size_formatted = "Pasta";
    item.modified_formatted = "";
    item.source = source;
    return item;
}

bool EnumerateDirectory(
    const std::wstring& directory,
    const std::string& source,
    std::vector<FileItemV21>& items,
    std::string& error)
{
    if (directory.empty())
    {
        error = "Location is unavailable on this system";
        return false;
    }

    std::wstring search = directory;
    if (!search.empty() && search.back() != L'\\' && search.back() != L'/') search += L'\\';
    search += L"*";

    WIN32_FIND_DATAW data{};
    HANDLE find = FindFirstFileW(search.c_str(), &data);
    if (find == INVALID_HANDLE_VALUE)
    {
        const DWORD code = GetLastError();
        if (code == ERROR_FILE_NOT_FOUND)
        {
            items.clear();
            return true;
        }
        error = "Unable to enumerate the selected Files capability";
        return false;
    }

    items.clear();
    do
    {
        if (wcscmp(data.cFileName, L".") == 0 || wcscmp(data.cFileName, L"..") == 0)
        {
            continue;
        }
        if ((data.dwFileAttributes & (FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM)) != 0)
        {
            continue;
        }

        FileItemV21 item;
        item.name = WideToUtf8(data.cFileName);
        fs::path full = fs::path(directory) / data.cFileName;
        item.path = WideToUtf8(full.lexically_normal().wstring());
        item.is_folder = (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        const ULONGLONG size =
            (static_cast<ULONGLONG>(data.nFileSizeHigh) << 32u) |
            static_cast<ULONGLONG>(data.nFileSizeLow);
        item.size_formatted = item.is_folder ? "Pasta" : FormatSize(size);
        item.modified_formatted = FormatModified(data.ftLastWriteTime);
        item.source = source;
        item.extension = item.is_folder ? "" : ExtensionOf(data.cFileName);
        items.push_back(std::move(item));
    }
    while (items.size() < kMaxItems && FindNextFileW(find, &data));

    FindClose(find);

    std::stable_sort(
        items.begin(),
        items.end(),
        [](const FileItemV21& left, const FileItemV21& right)
        {
            if (left.is_folder != right.is_folder) return left.is_folder > right.is_folder;
            return left.name < right.name;
        });
    return true;
}
} // namespace

JsonObject FileItemV21::ToJsonObject() const
{
    JsonObject object;
    object["name"] = JsonValue(name);
    object["path"] = JsonValue(path);
    object["isFolder"] = JsonValue(is_folder);
    object["sizeFormatted"] = JsonValue(size_formatted);
    object["modifiedFormatted"] = JsonValue(modified_formatted);
    object["source"] = JsonValue(source);
    object["extension"] = JsonValue(extension);
    object["entryId"] = JsonValue(entry_id);
    return object;
}

FileServiceV21& FileServiceV21::Instance()
{
    static FileServiceV21 service;
    return service;
}

bool FileServiceV21::IsAllowedLocation(const std::string& location) noexcept
{
    return location == "home" ||
        location == "desktop" ||
        location == "documents" ||
        location == "downloads" ||
        location == "cloud-drive" ||
        location == "windows-c" ||
        location == "ubuntu-wsl";
}

void FileServiceV21::CleanupExpiredLocked(Clock::time_point now)
{
    for (auto it = capabilities_.begin(); it != capabilities_.end();)
    {
        if (it->second.expires_at <= now)
            it = capabilities_.erase(it);
        else
            ++it;
    }
    if (capabilities_.size() >= kMaxCapabilities)
    {
        capabilities_.clear();
    }
}

std::string FileServiceV21::IssueCapability(
    const std::wstring& path,
    bool is_folder)
{
    if (path.empty()) return {};

    GUID guid{};
    if (FAILED(CoCreateGuid(&guid))) return {};

    wchar_t guid_text[40]{};
    if (StringFromGUID2(guid, guid_text, static_cast<int>(std::size(guid_text))) <= 0)
        return {};

    const std::string entry_id = "f21:" + WideToUtf8(guid_text);
    if (entry_id.empty()) return {};

    const auto now = Clock::now();
    std::lock_guard<std::mutex> lock(capabilities_mutex_);
    CleanupExpiredLocked(now);
    capabilities_[entry_id] = EntryCapability{
        fs::path(path).lexically_normal().wstring(),
        is_folder,
        now + kCapabilityLifetime,
    };
    return entry_id;
}

void FileServiceV21::AttachCapabilities(std::vector<FileItemV21>& items)
{
    for (FileItemV21& item : items)
    {
        const std::wstring path = Utf8ToWide(item.path);
        item.entry_id = IssueCapability(path, item.is_folder);
    }
}

bool FileServiceV21::ResolveCapability(
    const std::string& entry_id,
    EntryCapability& capability,
    std::string& error)
{
    if (entry_id.empty() || entry_id.size() > 96 || entry_id.rfind("f21:", 0) != 0)
    {
        error = "Invalid Files entry capability";
        return false;
    }

    const auto now = Clock::now();
    std::lock_guard<std::mutex> lock(capabilities_mutex_);
    CleanupExpiredLocked(now);
    const auto it = capabilities_.find(entry_id);
    if (it == capabilities_.end())
    {
        error = "Files entry capability is unknown or expired";
        return false;
    }

    it->second.expires_at = now + kCapabilityLifetime;
    capability = it->second;
    return true;
}

bool FileServiceV21::ListLocation(
    const std::string& location,
    std::vector<FileItemV21>& items,
    std::string& error)
{
    items.clear();
    error.clear();
    if (!IsAllowedLocation(location))
    {
        error = "Location id is not allowlisted by FileServiceV21";
        return false;
    }

    if (location == "home")
    {
        const std::wstring documents = KnownFolder(FOLDERID_Documents);
        const std::wstring downloads = KnownFolder(FOLDERID_Downloads);
        const std::wstring desktop = KnownFolder(FOLDERID_Desktop);
        const std::wstring cloud_drive = CloudDriveRoot();
        const std::wstring wsl = WslRoot();

        if (!documents.empty()) items.push_back(VirtualFolder("Documentos", documents, "windows"));
        if (!downloads.empty()) items.push_back(VirtualFolder("Downloads", downloads, "windows"));
        if (!desktop.empty()) items.push_back(VirtualFolder("Área de Trabalho", desktop, "windows"));
        if (!cloud_drive.empty()) items.push_back(VirtualFolder("CloudOS Drive", cloud_drive, "cloudDrive"));
        items.push_back(VirtualFolder("Disco Local", SystemVolumeRoot(), "windows"));
        if (!wsl.empty()) items.push_back(VirtualFolder("Linux / WSL", wsl, "linux"));
        AttachCapabilities(items);
        return true;
    }

    bool listed = false;
    if (location == "desktop")
        listed = EnumerateDirectory(KnownFolder(FOLDERID_Desktop), "windows", items, error);
    else if (location == "documents")
        listed = EnumerateDirectory(KnownFolder(FOLDERID_Documents), "windows", items, error);
    else if (location == "downloads")
        listed = EnumerateDirectory(KnownFolder(FOLDERID_Downloads), "windows", items, error);
    else if (location == "cloud-drive")
        listed = EnumerateDirectory(CloudDriveRoot(), "cloudDrive", items, error);
    else if (location == "windows-c")
        listed = EnumerateDirectory(SystemVolumeRoot(), "windows", items, error);
    else if (location == "ubuntu-wsl")
        listed = EnumerateDirectory(WslRoot(), "linux", items, error);

    if (!listed)
    {
        if (error.empty()) error = "Unsupported allowlisted location";
        return false;
    }
    AttachCapabilities(items);
    return true;
}

bool FileServiceV21::ListEntry(
    const std::string& entry_id,
    std::vector<FileItemV21>& items,
    std::string& error)
{
    EntryCapability capability;
    if (!ResolveCapability(entry_id, capability, error)) return false;
    if (!capability.is_folder)
    {
        error = "Files entry capability does not reference a folder";
        return false;
    }

    const DWORD attributes = GetFileAttributesW(capability.path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
    {
        error = "Folder capability target is no longer available";
        return false;
    }

    std::string source = "windows";
    if (capability.path.rfind(L"\\\\wsl", 0) == 0) source = "linux";
    const std::wstring cloud_root = CloudDriveRoot();
    if (!cloud_root.empty() && capability.path.rfind(cloud_root, 0) == 0)
        source = "cloudDrive";

    if (!EnumerateDirectory(capability.path, source, items, error)) return false;
    AttachCapabilities(items);
    return true;
}

bool FileServiceV21::OpenEntry(
    const std::string& entry_id,
    std::string& error)
{
    EntryCapability capability;
    if (!ResolveCapability(entry_id, capability, error)) return false;
    if (capability.is_folder)
    {
        error = "Folder capabilities must be navigated with files.listEntry";
        return false;
    }

    const DWORD attributes = GetFileAttributesW(capability.path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
    {
        error = "File capability target is no longer available";
        return false;
    }

    const HINSTANCE result = ShellExecuteW(
        nullptr,
        L"open",
        capability.path.c_str(),
        nullptr,
        nullptr,
        SW_SHOWNORMAL);
    if (reinterpret_cast<intptr_t>(result) <= 32)
    {
        error = "Windows Shell could not open the capability target";
        return false;
    }
    return true;
}

} // namespace CloudOS
