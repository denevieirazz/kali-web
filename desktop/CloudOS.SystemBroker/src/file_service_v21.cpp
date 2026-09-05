#include "file_service_v21.h"
#include "job_manager_v21.h"
#include "wsl_service_v21.h"

#include <Windows.h>
#include <objbase.h>
#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <array>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>

namespace CloudOS
{
namespace
{
namespace fs = std::filesystem;
constexpr std::size_t kMaxItems = 25000;

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

JsonObject DriveItemV21::ToJsonObject() const
{
    JsonObject object;
    object["mountPath"] = JsonValue(mount_path);
    object["label"] = JsonValue(label);
    object["driveType"] = JsonValue(drive_type);
    object["totalBytes"] = JsonValue(static_cast<int64_t>(total_bytes));
    object["freeBytes"] = JsonValue(static_cast<int64_t>(free_bytes));
    object["totalFormatted"] = JsonValue(total_formatted);
    object["freeFormatted"] = JsonValue(free_formatted);
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
        location == "ubuntu-wsl" ||
        location.rfind("drive:", 0) == 0 ||
        location.rfind("wsl:", 0) == 0;
}

bool FileServiceV21::IsProtectedSystemPath(const std::wstring& path)
{
    if (path.empty()) return true;

    fs::path p = fs::path(path).lexically_normal();
    std::wstring normal = p.wstring();

    if (p.parent_path() == p || p.relative_path().empty() || normal.length() <= 3)
    {
        return true;
    }

    std::wstring winDir = KnownFolder(FOLDERID_Windows);
    if (!winDir.empty())
    {
        std::wstring normalWin = fs::path(winDir).lexically_normal().wstring();
        if (_wcsicmp(normal.c_str(), normalWin.c_str()) == 0 ||
            (_wcsnicmp(normal.c_str(), normalWin.c_str(), normalWin.length()) == 0 &&
             (normal[normalWin.length()] == L'\\' || normal[normalWin.length()] == L'/')))
        {
            return true;
        }
    }

    std::wstring progFiles = KnownFolder(FOLDERID_ProgramFiles);
    if (!progFiles.empty())
    {
        std::wstring normalProg = fs::path(progFiles).lexically_normal().wstring();
        if (_wcsicmp(normal.c_str(), normalProg.c_str()) == 0 ||
            (_wcsnicmp(normal.c_str(), normalProg.c_str(), normalProg.length()) == 0 &&
             (normal[normalProg.length()] == L'\\' || normal[normalProg.length()] == L'/')))
        {
            return true;
        }
    }

    std::wstring progFilesX86 = KnownFolder(FOLDERID_ProgramFilesX86);
    if (!progFilesX86.empty())
    {
        std::wstring normalProg = fs::path(progFilesX86).lexically_normal().wstring();
        if (_wcsicmp(normal.c_str(), normalProg.c_str()) == 0 ||
            (_wcsnicmp(normal.c_str(), normalProg.c_str(), normalProg.length()) == 0 &&
             (normal[normalProg.length()] == L'\\' || normal[normalProg.length()] == L'/')))
        {
            return true;
        }
    }

    std::wstring userProfiles = KnownFolder(FOLDERID_UserProfiles);
    if (!userProfiles.empty())
    {
        std::wstring normalUsers = fs::path(userProfiles).lexically_normal().wstring();
        if (_wcsicmp(normal.c_str(), normalUsers.c_str()) == 0)
        {
            return true;
        }
    }

    return false;
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

bool FileServiceV21::ResolveCapability(
    const std::string& entry_id,
    EntryCapability& capability,
    std::string& error)
{
    if (entry_id.empty())
    {
        error = "Empty capability token";
        return false;
    }

    const auto now = Clock::now();
    std::lock_guard<std::mutex> lock(capabilities_mutex_);
    CleanupExpiredLocked(now);
    const auto it = capabilities_.find(entry_id);
    if (it == capabilities_.end())
    {
        error = "Capability token expired or invalid";
        return false;
    }

    capability = it->second;
    return true;
}

void FileServiceV21::AttachCapabilities(std::vector<FileItemV21>& items)
{
    for (auto& item : items)
    {
        item.entry_id = IssueCapability(Utf8ToWide(item.path), item.is_folder);
    }
}

bool FileServiceV21::ListLocation(
    const std::string& location,
    std::vector<FileItemV21>& items,
    std::string& error)
{
    items.clear();
    error.clear();

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
    else if (location.rfind("drive:", 0) == 0)
    {
        std::string drive_spec = location.substr(6);
        std::wstring drive_path = Utf8ToWide(drive_spec);
        if (drive_path.length() >= 1)
        {
            if (drive_path.length() == 1) drive_path += L":\\";
            else if (drive_path.length() == 2 && drive_path[1] == L':') drive_path += L"\\";
            else if (drive_path.back() != L'\\' && drive_path.back() != L'/') drive_path += L"\\";
            listed = EnumerateDirectory(drive_path, "windows", items, error);
        }
    }
    else if (location.rfind("wsl:", 0) == 0)
    {
        std::string distro = location.substr(4);
        std::wstring wsl_path = L"\\\\wsl.localhost\\" + Utf8ToWide(distro) + L"\\";
        listed = EnumerateDirectory(wsl_path, "linux", items, error);
    }

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

bool FileServiceV21::CreateFolder(
    const std::string& parent_entry_id,
    const std::string& name,
    FileItemV21& out_created_item,
    std::string& error)
{
    EntryCapability parent_cap;
    if (!ResolveCapability(parent_entry_id, parent_cap, error))
    {
        return false;
    }
    if (!parent_cap.is_folder)
    {
        error = "O destino especificado não é uma pasta";
        return false;
    }

    if (name.empty() || name.find('\\') != std::string::npos || name.find('/') != std::string::npos ||
        name == "." || name == ".." || name.find_first_of("<>:\"|?*") != std::string::npos)
    {
        error = "Nome de pasta inválido";
        return false;
    }

    fs::path target_path = fs::path(parent_cap.path) / Utf8ToWide(name);
    std::error_code ec;
    if (fs::exists(target_path, ec))
    {
        error = "Uma pasta ou arquivo com este nome já existe";
        return false;
    }

    if (!fs::create_directory(target_path, ec) || ec)
    {
        error = "Falha ao criar pasta: " + ec.message();
        return false;
    }

    out_created_item.name = name;
    out_created_item.path = WideToUtf8(target_path.lexically_normal().wstring());
    out_created_item.is_folder = true;
    out_created_item.size_formatted = "Pasta";
    out_created_item.modified_formatted = "Agora";
    out_created_item.source = parent_cap.path.rfind(L"\\\\wsl", 0) == 0 ? "linux" : "windows";
    out_created_item.extension = "";
    out_created_item.entry_id = IssueCapability(target_path.wstring(), true);
    return true;
}

bool FileServiceV21::RenameItem(
    const std::string& entry_id,
    const std::string& new_name,
    FileItemV21& out_renamed_item,
    std::string& error)
{
    EntryCapability cap;
    if (!ResolveCapability(entry_id, cap, error))
    {
        return false;
    }

    if (IsProtectedSystemPath(cap.path))
    {
        error = "Operação bloqueada: não é permitido renomear itens de sistema protegidos";
        return false;
    }

    if (new_name.empty() || new_name.find('\\') != std::string::npos || new_name.find('/') != std::string::npos ||
        new_name == "." || new_name == ".." || new_name.find_first_of("<>:\"|?*") != std::string::npos)
    {
        error = "Novo nome inválido";
        return false;
    }

    fs::path old_path(cap.path);
    fs::path parent_path = old_path.parent_path();
    if (parent_path.empty())
    {
        error = "Não é permitido renomear a raiz do volume";
        return false;
    }

    fs::path target_path = parent_path / Utf8ToWide(new_name);
    std::error_code ec;
    if (fs::exists(target_path, ec))
    {
        error = "Já existe um item com este nome";
        return false;
    }

    fs::rename(old_path, target_path, ec);
    if (ec)
    {
        error = "Falha ao renomear: " + ec.message();
        return false;
    }

    out_renamed_item.name = new_name;
    out_renamed_item.path = WideToUtf8(target_path.lexically_normal().wstring());
    out_renamed_item.is_folder = cap.is_folder;
    out_renamed_item.size_formatted = cap.is_folder ? "Pasta" : "Arquivo";
    out_renamed_item.modified_formatted = "Agora";
    out_renamed_item.source = target_path.wstring().rfind(L"\\\\wsl", 0) == 0 ? "linux" : "windows";
    out_renamed_item.extension = cap.is_folder ? "" : ExtensionOf(target_path.filename().wstring());
    out_renamed_item.entry_id = IssueCapability(target_path.wstring(), cap.is_folder);
    return true;
}

bool FileServiceV21::DeleteItems(
    const std::vector<std::string>& entry_ids,
    bool permanent,
    std::vector<std::string>& deleted_entry_ids,
    std::string& error)
{
    if (entry_ids.empty())
    {
        error = "Nenhum item informado para exclusão";
        return false;
    }

    for (const auto& entry_id : entry_ids)
    {
        EntryCapability cap;
        if (!ResolveCapability(entry_id, cap, error))
        {
            continue;
        }

        if (IsProtectedSystemPath(cap.path))
        {
            error = "Operação bloqueada: não é permitido excluir caminhos de sistema protegidos";
            return false;
        }

        if (!permanent)
        {
            std::wstring double_null = cap.path;
            double_null.push_back(L'\0');

            SHFILEOPSTRUCTW file_op{};
            file_op.wFunc = FO_DELETE;
            file_op.pFrom = double_null.c_str();
            file_op.fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;

            int res = SHFileOperationW(&file_op);
            if (res == 0 && !file_op.fAnyOperationsAborted)
            {
                deleted_entry_ids.push_back(entry_id);
            }
            else
            {
                std::error_code ec;
                fs::remove_all(cap.path, ec);
                if (!ec)
                {
                    deleted_entry_ids.push_back(entry_id);
                }
            }
        }
        else
        {
            std::error_code ec;
            fs::remove_all(cap.path, ec);
            if (!ec)
            {
                deleted_entry_ids.push_back(entry_id);
            }
        }
    }

    return !deleted_entry_ids.empty();
}

bool FileServiceV21::CopyOrMoveItemsAsync(
    const std::string& type,
    const std::vector<std::string>& source_entry_ids,
    const std::string& destination_entry_id,
    const std::string& conflict_strategy,
    std::string& out_job_id,
    std::string& error)
{
    EntryCapability dest_cap;
    if (!ResolveCapability(destination_entry_id, dest_cap, error))
    {
        return false;
    }
    if (!dest_cap.is_folder)
    {
        error = "O destino selecionado não é uma pasta";
        return false;
    }

    std::vector<std::wstring> source_paths;
    for (const auto& sid : source_entry_ids)
    {
        EntryCapability src_cap;
        if (ResolveCapability(sid, src_cap, error))
        {
            source_paths.push_back(src_cap.path);
        }
    }

    if (source_paths.empty())
    {
        error = "Nenhum arquivo de origem válido encontrado";
        return false;
    }

    const bool is_move = (type == "move");
    const std::wstring dest_path = dest_cap.path;
    const std::string strategy = conflict_strategy.empty() ? "replace" : conflict_strategy;

    out_job_id = JobManagerV21::Instance().SubmitJob(
        is_move ? "file_move" : "file_copy",
        [source_paths, dest_path, is_move, strategy](
            std::atomic_bool& cancel_flag,
            std::function<void(double)> progress_cb,
            std::string& err) -> bool
        {
            uint64_t total_bytes = 0;
            for (const auto& src : source_paths)
            {
                std::error_code ec;
                if (fs::is_regular_file(src, ec))
                {
                    total_bytes += fs::file_size(src, ec);
                }
            }

            uint64_t bytes_copied = 0;
            const size_t total_items = source_paths.size();
            size_t items_processed = 0;

            for (const auto& src : source_paths)
            {
                if (cancel_flag.load())
                {
                    err = "Operação cancelada pelo usuário";
                    return false;
                }

                fs::path sp(src);
                fs::path dp = fs::path(dest_path) / sp.filename();

                std::error_code exists_ec;
                if (fs::exists(dp, exists_ec))
                {
                    if (strategy == "skip")
                    {
                        items_processed++;
                        continue;
                    }
                    else if (strategy == "keep_both" || strategy == "keepBoth")
                    {
                        auto stem = sp.stem().wstring();
                        auto ext = sp.extension().wstring();
                        int counter = 1;
                        while (fs::exists(dp, exists_ec))
                        {
                            std::wstring candidate = stem + L" (" + std::to_wstring(counter++) + L")" + ext;
                            dp = fs::path(dest_path) / candidate;
                        }
                    }
                }

                if (fs::is_regular_file(sp, exists_ec))
                {
                    std::ifstream in_file(sp, std::ios::binary);
                    if (!in_file)
                    {
                        err = "Erro ao abrir origem: " + WideToUtf8(sp.filename().wstring());
                        return false;
                    }

                    std::ofstream out_file(dp, std::ios::binary | std::ios::trunc);
                    if (!out_file)
                    {
                        err = "Erro ao criar destino: " + WideToUtf8(dp.filename().wstring());
                        return false;
                    }

                    constexpr size_t kChunkSize = 1024 * 1024; // 1 MB
                    std::vector<char> buffer(kChunkSize);
                    bool was_cancelled = false;

                    while (in_file)
                    {
                        if (cancel_flag.load())
                        {
                            was_cancelled = true;
                            break;
                        }

                        in_file.read(buffer.data(), buffer.size());
                        const std::streamsize bytes_read = in_file.gcount();
                        if (bytes_read > 0)
                        {
                            out_file.write(buffer.data(), bytes_read);
                            bytes_copied += bytes_read;
                            if (total_bytes > 0 && progress_cb)
                            {
                                double p = (static_cast<double>(bytes_copied) / static_cast<double>(total_bytes)) * 100.0;
                                progress_cb(p);
                            }
                        }
                    }

                    in_file.close();
                    out_file.close();

                    if (was_cancelled)
                    {
                        std::error_code rm_ec;
                        fs::remove(dp, rm_ec);
                        err = "Operação cancelada pelo usuário";
                        return false;
                    }

                    if (is_move)
                    {
                        std::error_code rm_ec;
                        fs::remove(sp, rm_ec);
                    }
                }
                else
                {
                    std::error_code ec;
                    if (is_move)
                    {
                        fs::rename(sp, dp, ec);
                        if (ec)
                        {
                            fs::copy(sp, dp, fs::copy_options::recursive | fs::copy_options::overwrite_existing, ec);
                            if (!ec) fs::remove_all(sp, ec);
                        }
                    }
                    else
                    {
                        fs::copy(sp, dp, fs::copy_options::recursive | fs::copy_options::overwrite_existing, ec);
                    }

                    if (ec)
                    {
                        err = "Erro ao processar " + WideToUtf8(sp.filename().wstring()) + ": " + ec.message();
                        return false;
                    }
                }

                items_processed++;
                if (total_bytes == 0 && progress_cb)
                {
                    progress_cb((static_cast<double>(items_processed) / static_cast<double>(total_items)) * 100.0);
                }
            }

            return true;
        });

    return !out_job_id.empty();
}

bool FileServiceV21::ListDrives(std::vector<DriveItemV21>& out_drives, std::string& error)
{
    out_drives.clear();
    error.clear();

    std::array<wchar_t, 512> buffer{};
    DWORD len = GetLogicalDriveStringsW(static_cast<DWORD>(buffer.size()), buffer.data());
    if (len == 0 || len > buffer.size())
    {
        error = "Falha ao obter lista de unidades";
        return false;
    }

    const wchar_t* p = buffer.data();
    while (*p != L'\0')
    {
        std::wstring drive = p;
        p += drive.length() + 1;

        UINT type = GetDriveTypeW(drive.c_str());
        if (type == DRIVE_NO_ROOT_DIR || type == DRIVE_UNKNOWN)
        {
            continue;
        }

        std::string drive_type = "fixed";
        if (type == DRIVE_REMOVABLE) drive_type = "removable";
        else if (type == DRIVE_CDROM) drive_type = "cdrom";
        else if (type == DRIVE_REMOTE) drive_type = "network";

        wchar_t vol_name[MAX_PATH + 1]{};
        GetVolumeInformationW(drive.c_str(), vol_name, ARRAYSIZE(vol_name), nullptr, nullptr, nullptr, nullptr, 0);

        std::string label = WideToUtf8(vol_name);
        if (label.empty())
        {
            label = (type == DRIVE_REMOVABLE) ? "Unidade USB" : "Disco Local";
        }
        label += " (" + WideToUtf8(drive.substr(0, 2)) + ")";

        ULARGE_INTEGER free_avail{}, total_bytes{}, total_free{};
        GetDiskFreeSpaceExW(drive.c_str(), &free_avail, &total_bytes, &total_free);

        DriveItemV21 item;
        item.mount_path = WideToUtf8(drive);
        item.label = label;
        item.drive_type = drive_type;
        item.total_bytes = total_bytes.QuadPart;
        item.free_bytes = free_avail.QuadPart;
        item.total_formatted = FormatSize(total_bytes.QuadPart);
        item.free_formatted = FormatSize(free_avail.QuadPart);
        item.entry_id = IssueCapability(drive, true);

        out_drives.push_back(std::move(item));
    }

    const auto distros = WslServiceV21::Instance().GetDistroDetails();
    for (const auto& distro : distros)
    {
        std::wstring wslPath = L"\\\\wsl.localhost\\" + Utf8ToWide(distro.name);
        if (GetFileAttributesW(wslPath.c_str()) != INVALID_FILE_ATTRIBUTES)
        {
            DriveItemV21 item;
            item.mount_path = WideToUtf8(wslPath);
            item.label = distro.name + " (WSL Linux)";
            item.drive_type = "wsl";
            item.total_bytes = 0;
            item.free_bytes = 0;
            item.total_formatted = "WSL2 VHDX";
            item.free_formatted = distro.state;
            item.entry_id = IssueCapability(wslPath, true);
            out_drives.push_back(std::move(item));
        }
    }

    return true;
}

} // namespace CloudOS
