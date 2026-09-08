#include "file_service_v22.h"
#include "app_service_v21.h"
#include "event_bus_v21.h"
#include "wsl_service_v21.h"

#include <algorithm>
#include <array>
#include <cwctype>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <unordered_set>

namespace CloudOS
{

namespace
{

std::string Utf16ToUtf8(std::wstring_view wstr)
{
    if (wstr.empty()) return {};
    int size = WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), nullptr, 0, nullptr, nullptr);
    if (size <= 0) return {};
    std::string result(static_cast<size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), result.data(), size, nullptr, nullptr);
    return result;
}

std::wstring Utf8ToUtf16(std::string_view str)
{
    if (str.empty()) return {};
    int size = MultiByteToWideChar(CP_UTF8, 0, str.data(), static_cast<int>(str.size()), nullptr, 0);
    if (size <= 0) return {};
    std::wstring result(static_cast<size_t>(size), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, str.data(), static_cast<int>(str.size()), result.data(), size);
    return result;
}

std::string FileTimeToIsoUtc(const FILETIME& ft)
{
    SYSTEMTIME stUtc;
    if (!FileTimeToSystemTime(&ft, &stUtc))
    {
        return "1970-01-01T00:00:00Z";
    }
    char buf[64];
    snprintf(
        buf,
        sizeof(buf),
        "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
        stUtc.wYear,
        stUtc.wMonth,
        stUtc.wDay,
        stUtc.wHour,
        stUtc.wMinute,
        stUtc.wSecond,
        stUtc.wMilliseconds);
    return std::string(buf);
}

std::string FormatBytes(uint64_t bytes)
{
    constexpr uint64_t KB = 1024;
    constexpr uint64_t MB = KB * 1024;
    constexpr uint64_t GB = MB * 1024;
    constexpr uint64_t TB = GB * 1024;

    char buf[32];
    if (bytes >= TB)
        snprintf(buf, sizeof(buf), "%.2f TB", static_cast<double>(bytes) / TB);
    else if (bytes >= GB)
        snprintf(buf, sizeof(buf), "%.2f GB", static_cast<double>(bytes) / GB);
    else if (bytes >= MB)
        snprintf(buf, sizeof(buf), "%.1f MB", static_cast<double>(bytes) / MB);
    else if (bytes >= KB)
        snprintf(buf, sizeof(buf), "%.1f KB", static_cast<double>(bytes) / KB);
    else
        snprintf(buf, sizeof(buf), "%llu B", static_cast<unsigned long long>(bytes));
    return std::string(buf);
}

std::string GenerateItemId(const std::wstring& path)
{
    // Generate deterministic 64-bit hex hash
    std::wstring lower = path;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::towlower);
    uint64_t hash = 14695981039346656037ull;
    for (wchar_t ch : lower)
    {
        hash ^= static_cast<uint64_t>(ch);
        hash *= 1099511628211ull;
    }
    char buf[32];
    snprintf(buf, sizeof(buf), "file-%016llx", static_cast<unsigned long long>(hash));
    return std::string(buf);
}

bool StartsWithInsensitive(std::wstring_view str, std::wstring_view prefix)
{
    if (str.size() < prefix.size()) return false;
    return _wcsnicmp(str.data(), prefix.data(), prefix.size()) == 0;
}

std::wstring QuoteWindowsArgument(std::wstring_view arg)
{
    std::wstring result = L"\"";
    size_t backslashes = 0;
    for (wchar_t ch : arg)
    {
        if (ch == L'\\')
        {
            ++backslashes;
            continue;
        }
        if (ch == L'"')
        {
            result.append(backslashes * 2 + 1, L'\\');
            result.push_back(L'"');
            backslashes = 0;
            continue;
        }
        result.append(backslashes, L'\\');
        backslashes = 0;
        result.push_back(ch);
    }
    result.append(backslashes * 2, L'\\');
    result.push_back(L'"');
    return result;
}

bool RunProcessCapture(
    const std::wstring& executable,
    const std::vector<std::wstring>& arguments,
    DWORD timeout_ms,
    std::string* out_text)
{
    if (out_text) out_text->clear();

    HANDLE read_pipe = nullptr;
    HANDLE write_pipe = nullptr;
    SECURITY_ATTRIBUTES sa{sizeof(sa), nullptr, TRUE};
    if (!CreatePipe(&read_pipe, &write_pipe, &sa, 0)) return false;
    if (!SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0))
    {
        CloseHandle(read_pipe);
        CloseHandle(write_pipe);
        return false;
    }

    std::wstring command_line = QuoteWindowsArgument(executable);
    for (const auto& argument : arguments)
    {
        command_line.push_back(L' ');
        command_line += QuoteWindowsArgument(argument);
    }
    std::vector<wchar_t> mutable_command(command_line.begin(), command_line.end());
    mutable_command.push_back(L'\0');

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    startup.hStdOutput = write_pipe;
    startup.hStdError = write_pipe;
    startup.wShowWindow = SW_HIDE;

    PROCESS_INFORMATION process{};
    const BOOL created = CreateProcessW(
        executable.c_str(),
        mutable_command.data(),
        nullptr,
        nullptr,
        TRUE,
        CREATE_NO_WINDOW,
        nullptr,
        nullptr,
        &startup,
        &process);
    CloseHandle(write_pipe);
    if (!created)
    {
        CloseHandle(read_pipe);
        return false;
    }

    const DWORD wait_result = WaitForSingleObject(process.hProcess, timeout_ms);
    if (wait_result == WAIT_TIMEOUT)
    {
        TerminateProcess(process.hProcess, ERROR_TIMEOUT);
        WaitForSingleObject(process.hProcess, 1000);
    }

    std::string output;
    std::array<char, 512> buffer{};
    DWORD bytes_read = 0;
    while (output.size() < 4096 &&
           ReadFile(read_pipe, buffer.data(), static_cast<DWORD>(buffer.size()), &bytes_read, nullptr) &&
           bytes_read > 0)
    {
        output.append(buffer.data(), bytes_read);
    }

    DWORD exit_code = ERROR_GEN_FAILURE;
    GetExitCodeProcess(process.hProcess, &exit_code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    CloseHandle(read_pipe);

    if (out_text) *out_text = std::move(output);
    return wait_result == WAIT_OBJECT_0 && exit_code == 0;
}

bool IsSameOrDescendantPath(const std::wstring& candidate, const std::wstring& ancestor)
{
    if (_wcsicmp(candidate.c_str(), ancestor.c_str()) == 0) return true;
    if (candidate.size() <= ancestor.size()) return false;
    if (_wcsnicmp(candidate.c_str(), ancestor.c_str(), ancestor.size()) != 0) return false;
    return ancestor.back() == L'\\' || candidate[ancestor.size()] == L'\\';
}

DWORD CALLBACK CopyProgressCallback(
    LARGE_INTEGER,
    LARGE_INTEGER,
    LARGE_INTEGER,
    LARGE_INTEGER,
    DWORD,
    DWORD,
    HANDLE,
    HANDLE,
    LPVOID context)
{
    const auto* cancelled = static_cast<const std::atomic_bool*>(context);
    return cancelled && cancelled->load() ? PROGRESS_CANCEL : PROGRESS_CONTINUE;
}

bool CopyPathRecursive(
    const std::wstring& source,
    const std::wstring& destination,
    const std::string& overwrite_policy,
    std::atomic_bool& cancel_flag,
    std::string* out_error)
{
    if (cancel_flag.load())
    {
        if (out_error) *out_error = "cancelled";
        return false;
    }

    const DWORD source_attributes = GetFileAttributesW(source.c_str());
    if (source_attributes == INVALID_FILE_ATTRIBUTES)
    {
        if (out_error) *out_error = "source_not_found";
        return false;
    }

    if ((source_attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
    {
        if ((source_attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
        {
            if (out_error) *out_error = "directory_reparse_point_not_followed";
            return false;
        }

        const DWORD destination_attributes = GetFileAttributesW(destination.c_str());
        if (destination_attributes == INVALID_FILE_ATTRIBUTES)
        {
            if (!CreateDirectoryW(destination.c_str(), nullptr))
            {
                if (out_error) *out_error = "create_destination_directory_failed:" + std::to_string(GetLastError());
                return false;
            }
        }
        else if ((destination_attributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
        {
            if (out_error) *out_error = "destination_type_conflict";
            return false;
        }
        else if (overwrite_policy == "ask")
        {
            if (out_error) *out_error = "destination_exists";
            return false;
        }

        std::wstring pattern = source;
        if (pattern.back() != L'\\') pattern.push_back(L'\\');
        pattern.push_back(L'*');
        WIN32_FIND_DATAW find_data{};
        HANDLE find = FindFirstFileExW(
            pattern.c_str(), FindExInfoBasic, &find_data, FindExSearchNameMatch, nullptr, FIND_FIRST_EX_LARGE_FETCH);
        if (find == INVALID_HANDLE_VALUE)
        {
            const DWORD error = GetLastError();
            if (error == ERROR_FILE_NOT_FOUND) return true;
            if (out_error) *out_error = "enumerate_source_failed:" + std::to_string(error);
            return false;
        }

        bool ok = true;
        do
        {
            if (wcscmp(find_data.cFileName, L".") == 0 || wcscmp(find_data.cFileName, L"..") == 0) continue;
            std::wstring child_source = source + (source.back() == L'\\' ? L"" : L"\\") + find_data.cFileName;
            std::wstring child_destination = destination + (destination.back() == L'\\' ? L"" : L"\\") + find_data.cFileName;
            if (!CopyPathRecursive(child_source, child_destination, overwrite_policy, cancel_flag, out_error))
            {
                ok = false;
                break;
            }
        } while (FindNextFileW(find, &find_data));
        FindClose(find);
        return ok;
    }

    const DWORD destination_attributes = GetFileAttributesW(destination.c_str());
    if (destination_attributes != INVALID_FILE_ATTRIBUTES)
    {
        if (overwrite_policy == "skip") return true;
        if (overwrite_policy == "ask")
        {
            if (out_error) *out_error = "destination_exists";
            return false;
        }
        if ((destination_attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
        {
            if (out_error) *out_error = "destination_type_conflict";
            return false;
        }
    }

    std::wstring temporary = destination + L".cloudos-copy-" + std::to_wstring(GetCurrentProcessId()) + L"-" +
        std::to_wstring(GetTickCount64());
    BOOL cancel = FALSE;
    if (!CopyFileExW(
            source.c_str(),
            temporary.c_str(),
            CopyProgressCallback,
            &cancel_flag,
            &cancel,
            COPY_FILE_FAIL_IF_EXISTS))
    {
        const DWORD error = GetLastError();
        DeleteFileW(temporary.c_str());
        if (out_error) *out_error = cancel_flag.load() ? "cancelled" : "copy_failed:" + std::to_string(error);
        return false;
    }

    DWORD move_flags = MOVEFILE_WRITE_THROUGH;
    if (overwrite_policy == "replace") move_flags |= MOVEFILE_REPLACE_EXISTING;
    if (!MoveFileExW(temporary.c_str(), destination.c_str(), move_flags))
    {
        const DWORD error = GetLastError();
        DeleteFileW(temporary.c_str());
        if (out_error) *out_error = "commit_copy_failed:" + std::to_string(error);
        return false;
    }
    return true;
}

bool FindExecutable(const wchar_t* name, std::wstring* out_path)
{
    if (!out_path) return false;
    std::array<wchar_t, 32768> path{};
    const DWORD length = SearchPathW(nullptr, name, nullptr, static_cast<DWORD>(path.size()), path.data(), nullptr);
    if (length == 0 || length >= path.size()) return false;
    out_path->assign(path.data(), length);
    return true;
}

bool IsAllowedWslOpenWithCommand(const std::string& command)
{
    static const std::unordered_set<std::string> allowed = {
        "code", "gedit", "gimp", "kate", "mousepad", "vim", "xed"
    };
    return allowed.find(command) != allowed.end();
}

bool IsWslCommandAvailable(const std::string& distro, const std::string& command)
{
    if (!IsAllowedWslOpenWithCommand(command)) return false;
    std::string output;
    return RunProcessCapture(
        L"wsl.exe",
        {L"-d", Utf8ToUtf16(distro), L"--", L"which", Utf8ToUtf16(command)},
        4000,
        &output) && !output.empty();
}

} // namespace

FileServiceV22& FileServiceV22::Instance()
{
    static FileServiceV22 instance;
    return instance;
}

FileServiceV22::FileServiceV22()
{
}

FileServiceV22::~FileServiceV22()
{
}

std::wstring FileServiceV22::CanonicalizePath(const std::wstring& input)
{
    if (input.empty()) return L"";

    std::wstring cleaned = input;
    // Normalize forward slashes to backslashes
    std::replace(cleaned.begin(), cleaned.end(), L'/', L'\\');

    // Handle \\?\ extended path prefix if present
    bool has_extended_prefix = false;
    if (cleaned.rfind(L"\\\\?\\", 0) == 0)
    {
        has_extended_prefix = true;
        cleaned = cleaned.substr(4);
    }

    std::vector<wchar_t> buffer(32768);
    DWORD len = GetFullPathNameW(cleaned.c_str(), static_cast<DWORD>(buffer.size()), buffer.data(), nullptr);
    if (len > 0 && len < buffer.size())
    {
        std::wstring result(buffer.data(), len);
        // Remove trailing backslash if not a root directory (like C:\)
        if (result.size() > 3 && result.back() == L'\\')
        {
            result.pop_back();
        }
        return result;
    }

    return cleaned;
}

bool FileServiceV22::IsValidFileName(const std::wstring& name, std::string* out_reason)
{
    if (name.empty())
    {
        if (out_reason) *out_reason = "File name cannot be empty";
        return false;
    }

    if (name.size() > 255)
    {
        if (out_reason) *out_reason = "File name exceeds 255 characters";
        return false;
    }

    if (name == L"." || name == L"..")
    {
        if (out_reason) *out_reason = "File name cannot be '.' or '..'";
        return false;
    }

    // Check invalid characters
    static const std::wstring invalid_chars = L"\\/:*?\"<>|";
    for (wchar_t ch : name)
    {
        if (ch < 32 || invalid_chars.find(ch) != std::wstring::npos)
        {
            if (out_reason) *out_reason = "File name contains invalid characters (\\ / : * ? \" < > | or control characters)";
            return false;
        }
    }

    // Trailing dot or space is invalid on Windows
    if (name.back() == L'.' || name.back() == L' ')
    {
        if (out_reason) *out_reason = "File name cannot end with a dot or space";
        return false;
    }

    // Reserved DOS device names
    static const std::array<std::wstring, 22> reserved = {
        L"CON", L"PRN", L"AUX", L"NUL",
        L"COM1", L"COM2", L"COM3", L"COM4", L"COM5", L"COM6", L"COM7", L"COM8", L"COM9",
        L"LPT1", L"LPT2", L"LPT3", L"LPT4", L"LPT5", L"LPT6", L"LPT7", L"LPT8", L"LPT9"
    };

    std::wstring base_name = name;
    size_t dot_pos = base_name.find(L'.');
    if (dot_pos != std::wstring::npos)
    {
        base_name = base_name.substr(0, dot_pos);
    }
    std::transform(base_name.begin(), base_name.end(), base_name.begin(), ::towupper);

    for (const auto& res : reserved)
    {
        if (base_name == res)
        {
            if (out_reason) *out_reason = "File name is a reserved Windows system device name";
            return false;
        }
    }

    return true;
}

std::wstring FileServiceV22::ResolveVirtualTarget(const std::string& target)
{
    std::string lower = target;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) -> char { return static_cast<char>(std::tolower(c)); });

    if (lower.empty() || lower == "home" || lower == "desktop://home")
    {
        PWSTR path = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Profile, 0, nullptr, &path)) && path)
        {
            std::wstring res(path);
            CoTaskMemFree(path);
            return res;
        }
    }
    else if (lower == "desktop" || lower == "desktop://desktop")
    {
        PWSTR path = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Desktop, 0, nullptr, &path)) && path)
        {
            std::wstring res(path);
            CoTaskMemFree(path);
            return res;
        }
    }
    else if (lower == "documents" || lower == "desktop://documents")
    {
        PWSTR path = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Documents, 0, nullptr, &path)) && path)
        {
            std::wstring res(path);
            CoTaskMemFree(path);
            return res;
        }
    }
    else if (lower == "downloads" || lower == "desktop://downloads")
    {
        PWSTR path = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Downloads, 0, nullptr, &path)) && path)
        {
            std::wstring res(path);
            CoTaskMemFree(path);
            return res;
        }
    }
    else if (lower == "pictures" || lower == "desktop://pictures")
    {
        PWSTR path = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Pictures, 0, nullptr, &path)) && path)
        {
            std::wstring res(path);
            CoTaskMemFree(path);
            return res;
        }
    }
    else if (lower == "videos" || lower == "desktop://videos")
    {
        PWSTR path = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Videos, 0, nullptr, &path)) && path)
        {
            std::wstring res(path);
            CoTaskMemFree(path);
            return res;
        }
    }
    else if (lower == "music" || lower == "desktop://music")
    {
        PWSTR path = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Music, 0, nullptr, &path)) && path)
        {
            std::wstring res(path);
            CoTaskMemFree(path);
            return res;
        }
    }
    else if (lower.rfind("wsl:", 0) == 0)
    {
        std::string distro = target.substr(4);
        if (distro.empty()) distro = "Ubuntu";
        return L"\\\\wsl.localhost\\" + Utf8ToUtf16(distro);
    }

    return Utf8ToUtf16(target);
}

FileKind FileServiceV22::DetectFileKind(const std::wstring& extension, bool is_directory)
{
    if (is_directory) return FileKind::Folder;
    if (extension.empty()) return FileKind::Unknown;

    std::wstring ext = extension;
    std::transform(ext.begin(), ext.end(), ext.begin(), ::towlower);

    if (ext == L".txt" || ext == L".md" || ext == L".log" || ext == L".ini" || ext == L".cfg" || ext == L".rtf")
        return FileKind::Text;
    if (ext == L".png" || ext == L".jpg" || ext == L".jpeg" || ext == L".gif" || ext == L".bmp" || ext == L".ico" || ext == L".webp" || ext == L".svg")
        return FileKind::Image;
    if (ext == L".mp3" || ext == L".wav" || ext == L".flac" || ext == L".ogg" || ext == L".m4a" || ext == L".aac")
        return FileKind::Audio;
    if (ext == L".mp4" || ext == L".mkv" || ext == L".avi" || ext == L".mov" || ext == L".wmv" || ext == L".webm")
        return FileKind::Video;
    if (ext == L".pdf" || ext == L".doc" || ext == L".docx" || ext == L".xls" || ext == L".xlsx" || ext == L".ppt" || ext == L".pptx")
        return FileKind::Document;
    if (ext == L".zip" || ext == L".tar" || ext == L".gz" || ext == L".7z" || ext == L".rar" || ext == L".bz2" || ext == L".xz")
        return FileKind::Archive;
    if (ext == L".exe" || ext == L".msi" || ext == L".bat" || ext == L".cmd" || ext == L".ps1" || ext == L".vbs" || ext == L".sh")
        return FileKind::Executable;
    if (ext == L".dart" || ext == L".cpp" || ext == L".c" || ext == L".h" || ext == L".hpp" || ext == L".cs" || ext == L".py" || ext == L".js" || ext == L".ts" || ext == L".html" || ext == L".css" || ext == L".json" || ext == L".yaml" || ext == L".yml" || ext == L".xml" || ext == L".sql")
        return FileKind::Code;

    return FileKind::Unknown;
}

std::string FileServiceV22::ResolveIconKey(FileKind kind, const std::wstring& extension, bool is_directory)
{
    (void)extension;
    if (is_directory) return "folder";
    switch (kind)
    {
    case FileKind::Text: return "file_text";
    case FileKind::Image: return "file_image";
    case FileKind::Audio: return "file_audio";
    case FileKind::Video: return "file_video";
    case FileKind::Document: return "file_document";
    case FileKind::Archive: return "file_archive";
    case FileKind::Executable: return "file_executable";
    case FileKind::Code: return "file_code";
    default: return "file_generic";
    }
}

CloudFileItemMetadata FileServiceV22::BuildMetadataFromFindData(
    const std::wstring& parent_dir,
    const WIN32_FIND_DATAW& fd,
    LocationKind location_kind,
    const std::string& distro)
{
    CloudFileItemMetadata meta;
    meta.name = Utf16ToUtf8(fd.cFileName);
    meta.display_name = meta.name;

    std::wstring full_path = parent_dir;
    if (full_path.back() != L'\\') full_path += L'\\';
    full_path += fd.cFileName;

    meta.path = Utf16ToUtf8(full_path);
    meta.canonical_path = Utf16ToUtf8(CanonicalizePath(full_path));
    meta.id = GenerateItemId(full_path);
    meta.location_kind = location_kind;
    meta.distro = distro;

    meta.is_directory = (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    meta.is_hidden = (fd.dwFileAttributes & FILE_ATTRIBUTE_HIDDEN) != 0 || (!meta.name.empty() && meta.name[0] == '.');
    meta.is_readonly = (fd.dwFileAttributes & FILE_ATTRIBUTE_READONLY) != 0;
    meta.is_system = (fd.dwFileAttributes & FILE_ATTRIBUTE_SYSTEM) != 0;
    meta.is_symlink = (fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;

    if (!meta.is_directory)
    {
        meta.size = (static_cast<int64_t>(fd.nFileSizeHigh) << 32) | fd.nFileSizeLow;
        std::wstring ext;
        const wchar_t* dot = wcsrchr(fd.cFileName, L'.');
        if (dot) ext = dot;
        meta.extension = Utf16ToUtf8(ext);
        meta.file_kind = DetectFileKind(ext, false);
    }
    else
    {
        meta.size = 0;
        meta.file_kind = FileKind::Folder;
    }

    meta.modified_time = FileTimeToIsoUtc(fd.ftLastWriteTime);
    meta.created_time = FileTimeToIsoUtc(fd.ftCreationTime);
    meta.icon_key = ResolveIconKey(meta.file_kind, Utf8ToUtf16(meta.extension), meta.is_directory);

    return meta;
}

CloudFileItemMetadata FileServiceV22::BuildMetadataForPath(const std::wstring& full_path)
{
    CloudFileItemMetadata meta;
    std::wstring canonical = CanonicalizePath(full_path);
    meta.path = Utf16ToUtf8(canonical);
    meta.canonical_path = meta.path;
    meta.id = GenerateItemId(canonical);

    // Check location kind
    if (StartsWithInsensitive(canonical, L"\\\\wsl.localhost\\") || StartsWithInsensitive(canonical, L"\\\\wsl$\\"))
    {
        meta.location_kind = LocationKind::Wsl;
        size_t prefix_len = StartsWithInsensitive(canonical, L"\\\\wsl.localhost\\") ? 16 : 7;
        size_t slash = canonical.find_first_of(L"\\/", prefix_len);
        meta.distro = Utf16ToUtf8(canonical.substr(prefix_len, slash == std::wstring::npos ? std::wstring::npos : slash - prefix_len));
    }
    else if (StartsWithInsensitive(canonical, L"\\\\"))
    {
        meta.location_kind = LocationKind::Network;
    }
    else
    {
        meta.location_kind = LocationKind::Windows;
    }

    WIN32_FILE_ATTRIBUTE_DATA attr{};
    if (GetFileAttributesExW(canonical.c_str(), GetFileExInfoStandard, &attr))
    {
        meta.is_directory = (attr.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        meta.is_hidden = (attr.dwFileAttributes & FILE_ATTRIBUTE_HIDDEN) != 0;
        meta.is_readonly = (attr.dwFileAttributes & FILE_ATTRIBUTE_READONLY) != 0;
        meta.is_system = (attr.dwFileAttributes & FILE_ATTRIBUTE_SYSTEM) != 0;
        meta.is_symlink = (attr.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;

        if (!meta.is_directory)
        {
            meta.size = (static_cast<int64_t>(attr.nFileSizeHigh) << 32) | attr.nFileSizeLow;
        }

        meta.modified_time = FileTimeToIsoUtc(attr.ftLastWriteTime);
        meta.created_time = FileTimeToIsoUtc(attr.ftCreationTime);
    }

    const wchar_t* last_slash = wcsrchr(canonical.c_str(), L'\\');
    if (last_slash && *(last_slash + 1) != L'\0')
    {
        meta.name = Utf16ToUtf8(last_slash + 1);
    }
    else
    {
        meta.name = meta.path;
    }
    meta.display_name = meta.name;

    const wchar_t* dot = wcsrchr(canonical.c_str(), L'.');
    if (dot && !meta.is_directory)
    {
        meta.extension = Utf16ToUtf8(dot);
        meta.file_kind = DetectFileKind(dot, false);
    }
    else
    {
        meta.file_kind = meta.is_directory ? FileKind::Folder : FileKind::Unknown;
    }

    meta.icon_key = ResolveIconKey(meta.file_kind, Utf8ToUtf16(meta.extension), meta.is_directory);
    return meta;
}

JsonObject FileServiceV22::ListDirectory(
    const std::string& path_or_target,
    size_t page_size,
    const std::string& continuation_token,
    const FileSortOptions& sort,
    const FileFilterOptions& filter)
{
    std::wstring resolved_dir = ResolveVirtualTarget(path_or_target);
    resolved_dir = CanonicalizePath(resolved_dir);

    JsonObject result;
    result["path"] = JsonValue(Utf16ToUtf8(resolved_dir));
    result["canonicalPath"] = JsonValue(Utf16ToUtf8(resolved_dir));

    // Detect location kind and distro
    LocationKind location_kind = LocationKind::Windows;
    std::string distro;
    if (StartsWithInsensitive(resolved_dir, L"\\\\wsl.localhost\\") || StartsWithInsensitive(resolved_dir, L"\\\\wsl$\\"))
    {
        location_kind = LocationKind::Wsl;
        size_t prefix_len = StartsWithInsensitive(resolved_dir, L"\\\\wsl.localhost\\") ? 16 : 7;
        size_t slash = resolved_dir.find_first_of(L"\\/", prefix_len);
        distro = Utf16ToUtf8(resolved_dir.substr(prefix_len, slash == std::wstring::npos ? std::wstring::npos : slash - prefix_len));
    }
    else if (StartsWithInsensitive(resolved_dir, L"\\\\"))
    {
        location_kind = LocationKind::Network;
    }

    result["locationKind"] = JsonValue(
        location_kind == LocationKind::Wsl ? "wsl" :
        location_kind == LocationKind::Network ? "network" : "windows");
    result["distro"] = JsonValue(distro);

    // Parent path
    const wchar_t* last_slash = wcsrchr(resolved_dir.c_str(), L'\\');
    if (last_slash && last_slash != resolved_dir.c_str() && *(last_slash - 1) != L':')
    {
        result["parentPath"] = JsonValue(Utf16ToUtf8(resolved_dir.substr(0, last_slash - resolved_dir.c_str())));
    }
    else if (last_slash && last_slash != resolved_dir.c_str() && *(last_slash - 1) == L':')
    {
        result["parentPath"] = JsonValue(Utf16ToUtf8(resolved_dir.substr(0, last_slash - resolved_dir.c_str() + 1)));
    }
    else
    {
        result["parentPath"] = JsonValue("");
    }

    std::wstring search_pattern = resolved_dir;
    if (search_pattern.back() != L'\\') search_pattern += L'\\';
    search_pattern += L"*";

    WIN32_FIND_DATAW fd{};
    HANDLE find_handle = FindFirstFileExW(
        search_pattern.c_str(),
        FindExInfoBasic,
        &fd,
        FindExSearchNameMatch,
        nullptr,
        FIND_FIRST_EX_LARGE_FETCH);

    if (find_handle == INVALID_HANDLE_VALUE)
    {
        DWORD err = GetLastError();
        result["items"] = JsonValue(JsonArray{});
        result["totalItems"] = JsonValue(0);
        result["hasMore"] = JsonValue(false);
        result["error"] = JsonValue(err == ERROR_ACCESS_DENIED ? "access_denied" : "directory_not_found");
        return result;
    }

    std::vector<CloudFileItemMetadata> all_items;
    all_items.reserve(500);

    do
    {
        if (wcscmp(fd.cFileName, L".") == 0 || wcscmp(fd.cFileName, L"..") == 0)
        {
            continue;
        }

        CloudFileItemMetadata meta = BuildMetadataFromFindData(resolved_dir, fd, location_kind, distro);

        // Apply filters
        if (!filter.show_hidden && meta.is_hidden) continue;
        if (filter.folders_only && !meta.is_directory) continue;
        if (filter.files_only && meta.is_directory) continue;
        if (!filter.extension.empty() && meta.extension != filter.extension) continue;
        if (!filter.search_text.empty())
        {
            std::string item_lower = meta.name;
            std::string search_lower = filter.search_text;
            std::transform(item_lower.begin(), item_lower.end(), item_lower.begin(), [](unsigned char c) -> char { return static_cast<char>(std::tolower(c)); });
            std::transform(search_lower.begin(), search_lower.end(), search_lower.begin(), [](unsigned char c) -> char { return static_cast<char>(std::tolower(c)); });
            if (item_lower.find(search_lower) == std::string::npos) continue;
        }

        all_items.push_back(std::move(meta));
    } while (FindNextFileW(find_handle, &fd));

    FindClose(find_handle);

    // Apply Sorting
    std::sort(
        all_items.begin(),
        all_items.end(),
        [&sort](const CloudFileItemMetadata& a, const CloudFileItemMetadata& b) {
            if (sort.directories_first && a.is_directory != b.is_directory)
            {
                return a.is_directory; // Directories always first
            }

            int cmp = 0;
            switch (sort.field)
            {
            case FileSortField::Size:
                cmp = (a.size < b.size) ? -1 : ((a.size > b.size) ? 1 : 0);
                break;
            case FileSortField::Modified:
                cmp = a.modified_time.compare(b.modified_time);
                break;
            case FileSortField::Type:
                cmp = a.extension.compare(b.extension);
                break;
            case FileSortField::Name:
            default:
                cmp = _stricmp(a.name.c_str(), b.name.c_str());
                break;
            }

            if (cmp == 0)
            {
                cmp = _stricmp(a.name.c_str(), b.name.c_str());
            }

            return sort.ascending ? (cmp < 0) : (cmp > 0);
        });

    size_t offset = 0;
    if (!continuation_token.empty())
    {
        try { offset = std::stoull(continuation_token); } catch (...) { offset = 0; }
    }

    size_t limit = page_size > 0 ? page_size : 200;
    size_t total = all_items.size();
    size_t end = std::min(offset + limit, total);

    JsonArray items_json;
    for (size_t i = offset; i < end; ++i)
    {
        const auto& item = all_items[i];
        JsonObject obj;
        obj["id"] = JsonValue(item.id);
        obj["name"] = JsonValue(item.name);
        obj["displayName"] = JsonValue(item.display_name);
        obj["path"] = JsonValue(item.path);
        obj["canonicalPath"] = JsonValue(item.canonical_path);
        obj["locationKind"] = JsonValue(
            item.location_kind == LocationKind::Wsl ? "wsl" :
            item.location_kind == LocationKind::Network ? "network" : "windows");
        obj["fileKind"] = JsonValue(
            item.file_kind == FileKind::Folder ? "folder" :
            item.file_kind == FileKind::Text ? "text" :
            item.file_kind == FileKind::Image ? "image" :
            item.file_kind == FileKind::Audio ? "audio" :
            item.file_kind == FileKind::Video ? "video" :
            item.file_kind == FileKind::Document ? "document" :
            item.file_kind == FileKind::Archive ? "archive" :
            item.file_kind == FileKind::Executable ? "executable" :
            item.file_kind == FileKind::Code ? "code" : "unknown");
        obj["extension"] = JsonValue(item.extension);
        obj["size"] = JsonValue(static_cast<double>(item.size));
        obj["sizeFormatted"] = JsonValue(item.is_directory ? "" : FormatBytes(static_cast<uint64_t>(item.size)));
        obj["modifiedTime"] = JsonValue(item.modified_time);
        obj["createdTime"] = JsonValue(item.created_time);
        obj["isDirectory"] = JsonValue(item.is_directory);
        obj["isHidden"] = JsonValue(item.is_hidden);
        obj["isReadOnly"] = JsonValue(item.is_readonly);
        obj["isSystem"] = JsonValue(item.is_system);
        obj["isSymlink"] = JsonValue(item.is_symlink);
        obj["distro"] = JsonValue(item.distro);
        obj["iconKey"] = JsonValue(item.icon_key);
        obj["canRename"] = JsonValue(item.can_rename);
        obj["canDelete"] = JsonValue(item.can_delete);
        obj["canOpen"] = JsonValue(item.can_open);
        obj["canOpenWith"] = JsonValue(item.can_open_with);
        obj["canCopy"] = JsonValue(item.can_copy);
        obj["canMove"] = JsonValue(item.can_move);
        items_json.push_back(JsonValue(obj));
    }

    result["items"] = JsonValue(items_json);
    result["totalItems"] = JsonValue(static_cast<double>(total));
    result["offset"] = JsonValue(static_cast<double>(offset));
    result["limit"] = JsonValue(static_cast<double>(limit));
    result["hasMore"] = JsonValue(end < total);
    if (end < total)
    {
        result["continuationToken"] = JsonValue(std::to_string(end));
    }

    return result;
}

JsonObject FileServiceV22::GetMetadata(const std::string& path_or_id)
{
    std::wstring resolved = ResolveVirtualTarget(path_or_id);
    CloudFileItemMetadata item = BuildMetadataForPath(resolved);

    JsonObject obj;
    obj["id"] = JsonValue(item.id);
    obj["name"] = JsonValue(item.name);
    obj["displayName"] = JsonValue(item.display_name);
    obj["path"] = JsonValue(item.path);
    obj["canonicalPath"] = JsonValue(item.canonical_path);
    obj["locationKind"] = JsonValue(
        item.location_kind == LocationKind::Wsl ? "wsl" :
        item.location_kind == LocationKind::Network ? "network" : "windows");
    obj["fileKind"] = JsonValue(
        item.file_kind == FileKind::Folder ? "folder" :
        item.file_kind == FileKind::Text ? "text" :
        item.file_kind == FileKind::Image ? "image" :
        item.file_kind == FileKind::Audio ? "audio" :
        item.file_kind == FileKind::Video ? "video" :
        item.file_kind == FileKind::Document ? "document" :
        item.file_kind == FileKind::Archive ? "archive" :
        item.file_kind == FileKind::Executable ? "executable" :
        item.file_kind == FileKind::Code ? "code" : "unknown");
    obj["extension"] = JsonValue(item.extension);
    obj["size"] = JsonValue(static_cast<double>(item.size));
    obj["sizeFormatted"] = JsonValue(item.is_directory ? "" : FormatBytes(static_cast<uint64_t>(item.size)));
    obj["modifiedTime"] = JsonValue(item.modified_time);
    obj["createdTime"] = JsonValue(item.created_time);
    obj["isDirectory"] = JsonValue(item.is_directory);
    obj["isHidden"] = JsonValue(item.is_hidden);
    obj["isReadOnly"] = JsonValue(item.is_readonly);
    obj["isSystem"] = JsonValue(item.is_system);
    obj["isSymlink"] = JsonValue(item.is_symlink);
    obj["distro"] = JsonValue(item.distro);
    obj["iconKey"] = JsonValue(item.icon_key);
    obj["canRename"] = JsonValue(item.can_rename);
    obj["canDelete"] = JsonValue(item.can_delete);
    obj["canOpen"] = JsonValue(item.can_open);
    obj["canOpenWith"] = JsonValue(item.can_open_with);
    obj["canCopy"] = JsonValue(item.can_copy);
    obj["canMove"] = JsonValue(item.can_move);
    return obj;
}

JsonObject FileServiceV22::GetDrives()
{
    JsonArray drives_arr;
    std::vector<wchar_t> buffer(512);
    DWORD len = GetLogicalDriveStringsW(static_cast<DWORD>(buffer.size()), buffer.data());

    if (len > 0 && len < buffer.size())
    {
        const wchar_t* p = buffer.data();
        while (*p)
        {
            std::wstring drive = p;
            UINT type = GetDriveTypeW(drive.c_str());

            ULARGE_INTEGER free_bytes_avail, total_num_bytes, total_free_bytes;
            BOOL space_ok = GetDiskFreeSpaceExW(drive.c_str(), &free_bytes_avail, &total_num_bytes, &total_free_bytes);

            wchar_t volume_name[MAX_PATH + 1] = {0};
            wchar_t fs_name[MAX_PATH + 1] = {0};
            GetVolumeInformationW(drive.c_str(), volume_name, MAX_PATH + 1, nullptr, nullptr, nullptr, fs_name, MAX_PATH + 1);

            JsonObject drive_obj;
            std::string drive_str = Utf16ToUtf8(drive);
            if (drive_str.size() > 2 && drive_str.back() == '\\') drive_str.pop_back();

            drive_obj["letter"] = JsonValue(drive_str);
            drive_obj["path"] = JsonValue(Utf16ToUtf8(drive));
            drive_obj["label"] = JsonValue(volume_name[0] ? Utf16ToUtf8(volume_name) : "Disco Local");
            drive_obj["filesystem"] = JsonValue(fs_name[0] ? Utf16ToUtf8(fs_name) : "NTFS");
            drive_obj["isReady"] = JsonValue(space_ok != FALSE);
            drive_obj["isRemovable"] = JsonValue(type == DRIVE_REMOVABLE || type == DRIVE_CDROM);
            drive_obj["driveType"] = JsonValue(
                type == DRIVE_FIXED ? "fixed" :
                type == DRIVE_REMOVABLE ? "removable" :
                type == DRIVE_REMOTE ? "network" :
                type == DRIVE_CDROM ? "cdrom" : "unknown");

            if (space_ok)
            {
                drive_obj["totalBytes"] = JsonValue(static_cast<double>(total_num_bytes.QuadPart));
                drive_obj["freeBytes"] = JsonValue(static_cast<double>(free_bytes_avail.QuadPart));
                drive_obj["totalFormatted"] = JsonValue(FormatBytes(total_num_bytes.QuadPart));
                drive_obj["freeFormatted"] = JsonValue(FormatBytes(free_bytes_avail.QuadPart));
            }
            else
            {
                drive_obj["totalBytes"] = JsonValue(0);
                drive_obj["freeBytes"] = JsonValue(0);
                drive_obj["totalFormatted"] = JsonValue("");
                drive_obj["freeFormatted"] = JsonValue("");
            }

            drives_arr.push_back(JsonValue(drive_obj));
            p += wcslen(p) + 1;
        }
    }

    JsonObject res;
    res["drives"] = JsonValue(drives_arr);
    return res;
}

JsonObject FileServiceV22::GetKnownFolders()
{
    JsonArray arr;
    auto AddFolder = [&arr](const std::string& id, const std::string& name, REFKNOWNFOLDERID folder_id, const std::string& icon) {
        PWSTR path = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(folder_id, 0, nullptr, &path)) && path)
        {
            JsonObject obj;
            obj["id"] = JsonValue(id);
            obj["name"] = JsonValue(name);
            obj["path"] = JsonValue(Utf16ToUtf8(path));
            obj["iconKey"] = JsonValue(icon);
            arr.push_back(JsonValue(obj));
            CoTaskMemFree(path);
        }
    };

    AddFolder("home", "Início", FOLDERID_Profile, "home");
    AddFolder("desktop", "Área de Trabalho", FOLDERID_Desktop, "desktop");
    AddFolder("documents", "Documentos", FOLDERID_Documents, "documents");
    AddFolder("downloads", "Downloads", FOLDERID_Downloads, "downloads");
    AddFolder("pictures", "Imagens", FOLDERID_Pictures, "pictures");
    AddFolder("videos", "Vídeos", FOLDERID_Videos, "videos");
    AddFolder("music", "Músicas", FOLDERID_Music, "music");

    // Add WSL root if available
    std::vector<std::string> distros = WslServiceV21::Instance().GetDistributions();
    for (const auto& d : distros)
    {
        JsonObject wsl_obj;
        wsl_obj["id"] = JsonValue("wsl:" + d);
        wsl_obj["name"] = JsonValue(d + " (WSL)");
        wsl_obj["path"] = JsonValue("\\\\wsl.localhost\\" + d);
        wsl_obj["iconKey"] = JsonValue("linux");
        arr.push_back(JsonValue(wsl_obj));
    }

    JsonObject res;
    res["folders"] = JsonValue(arr);
    return res;
}

JsonObject FileServiceV22::ResolvePath(const std::string& path_or_target)
{
    std::wstring resolved = ResolveVirtualTarget(path_or_target);
    resolved = CanonicalizePath(resolved);

    JsonObject res;
    res["input"] = JsonValue(path_or_target);
    res["resolvedPath"] = JsonValue(Utf16ToUtf8(resolved));
    res["exists"] = JsonValue(GetFileAttributesW(resolved.c_str()) != INVALID_FILE_ATTRIBUTES);
    return res;
}

JsonObject FileServiceV22::CreateFolder(const std::string& parent_path, const std::string& folder_name)
{
    std::wstring wname = Utf8ToUtf16(folder_name);
    std::string invalid_reason;
    if (!IsValidFileName(wname, &invalid_reason))
    {
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue("invalid_name");
        err["message"] = JsonValue(invalid_reason);
        return err;
    }

    std::wstring parent_resolved = CanonicalizePath(ResolveVirtualTarget(parent_path));
    std::wstring target = parent_resolved;
    if (target.back() != L'\\') target += L'\\';
    target += wname;

    if (GetFileAttributesW(target.c_str()) != INVALID_FILE_ATTRIBUTES)
    {
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue("already_exists");
        err["message"] = JsonValue("A file or folder with this name already exists");
        return err;
    }

    if (!CreateDirectoryW(target.c_str(), nullptr))
    {
        DWORD err_code = GetLastError();
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue(err_code == ERROR_ACCESS_DENIED ? "access_denied" : "creation_failed");
        err["message"] = JsonValue("Failed to create directory (Windows error " + std::to_string(err_code) + ")");
        return err;
    }

    operations_generation_++;

    // Notify EventBus
    JsonObject ev_payload;
    ev_payload["action"] = JsonValue("created");
    ev_payload["path"] = JsonValue(Utf16ToUtf8(target));
    ev_payload["parentPath"] = JsonValue(Utf16ToUtf8(parent_resolved));
    EventBusV21::Instance().Publish("files.changed", ev_payload);

    JsonObject res;
    res["ok"] = JsonValue(true);
    res["path"] = JsonValue(Utf16ToUtf8(target));
    res["metadata"] = JsonValue(GetMetadata(Utf16ToUtf8(target)));
    return res;
}

JsonObject FileServiceV22::RenameItem(const std::string& item_path, const std::string& new_name)
{
    std::wstring wname = Utf8ToUtf16(new_name);
    std::string invalid_reason;
    if (!IsValidFileName(wname, &invalid_reason))
    {
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue("invalid_name");
        err["message"] = JsonValue(invalid_reason);
        return err;
    }

    std::wstring source_path = CanonicalizePath(ResolveVirtualTarget(item_path));
    if (GetFileAttributesW(source_path.c_str()) == INVALID_FILE_ATTRIBUTES)
    {
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue("not_found");
        err["message"] = JsonValue("Source file or folder does not exist");
        return err;
    }

    const wchar_t* last_slash = wcsrchr(source_path.c_str(), L'\\');
    if (!last_slash)
    {
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue("invalid_path");
        err["message"] = JsonValue("Cannot rename root directory");
        return err;
    }

    std::wstring target_path = source_path.substr(0, last_slash - source_path.c_str() + 1) + wname;

    // Check if target exists (and is not just a case-only change of the same file)
    if (_wcsicmp(source_path.c_str(), target_path.c_str()) != 0 &&
        GetFileAttributesW(target_path.c_str()) != INVALID_FILE_ATTRIBUTES)
    {
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue("already_exists");
        err["message"] = JsonValue("An item with the target name already exists");
        return err;
    }

    if (!MoveFileExW(source_path.c_str(), target_path.c_str(), MOVEFILE_COPY_ALLOWED))
    {
        DWORD err_code = GetLastError();
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue(err_code == ERROR_ACCESS_DENIED ? "access_denied" : "rename_failed");
        err["message"] = JsonValue("Failed to rename item (Windows error " + std::to_string(err_code) + ")");
        return err;
    }

    operations_generation_++;

    // Notify EventBus
    JsonObject ev_payload;
    ev_payload["action"] = JsonValue("renamed");
    ev_payload["oldPath"] = JsonValue(Utf16ToUtf8(source_path));
    ev_payload["newPath"] = JsonValue(Utf16ToUtf8(target_path));
    EventBusV21::Instance().Publish("files.changed", ev_payload);

    JsonObject res;
    res["ok"] = JsonValue(true);
    res["oldPath"] = JsonValue(Utf16ToUtf8(source_path));
    res["newPath"] = JsonValue(Utf16ToUtf8(target_path));
    return res;
}

bool FileServiceV22::ExecuteIFileOperation(
    UINT operation_type,
    const std::vector<std::wstring>& sources,
    const std::wstring& destination,
    bool allow_undo,
    std::string* out_error)
{
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    bool need_uninit = SUCCEEDED(hr);

    IFileOperation* file_op = nullptr;
    hr = CoCreateInstance(
        CLSID_FileOperation,
        nullptr,
        CLSCTX_ALL,
        IID_PPV_ARGS(&file_op));

    if (FAILED(hr) || !file_op)
    {
        if (need_uninit) CoUninitialize();
        if (out_error) *out_error = "CoCreateInstance CLSID_FileOperation failed";
        return false;
    }

    DWORD flags = FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;
    if (allow_undo) flags |= FOF_ALLOWUNDO;

    hr = file_op->SetOperationFlags(flags);
    if (FAILED(hr))
    {
        file_op->Release();
        if (need_uninit) CoUninitialize();
        if (out_error) *out_error = "SetOperationFlags failed";
        return false;
    }

    IShellItem* dest_item = nullptr;
    if (!destination.empty() && (operation_type == 1 || operation_type == 2))
    {
        hr = SHCreateItemFromParsingName(destination.c_str(), nullptr, IID_PPV_ARGS(&dest_item));
        if (FAILED(hr) || !dest_item)
        {
            file_op->Release();
            if (need_uninit) CoUninitialize();
            if (out_error) *out_error = "Destination is unavailable";
            return false;
        }
    }

    size_t queued_operations = 0;
    for (const auto& src : sources)
    {
        IShellItem* src_item = nullptr;
        hr = SHCreateItemFromParsingName(src.c_str(), nullptr, IID_PPV_ARGS(&src_item));
        if (FAILED(hr) || !src_item)
        {
            if (dest_item) dest_item->Release();
            file_op->Release();
            if (need_uninit) CoUninitialize();
            if (out_error) *out_error = "Source is unavailable";
            return false;
        }

        HRESULT queue_hr = E_INVALIDARG;
        if (operation_type == 1 && dest_item) // Copy
        {
            queue_hr = file_op->CopyItem(src_item, dest_item, nullptr, nullptr);
        }
        else if (operation_type == 2 && dest_item) // Move
        {
            queue_hr = file_op->MoveItem(src_item, dest_item, nullptr, nullptr);
        }
        else if (operation_type == 3) // Delete
        {
            queue_hr = file_op->DeleteItem(src_item, nullptr);
        }
        src_item->Release();

        if (FAILED(queue_hr))
        {
            if (dest_item) dest_item->Release();
            file_op->Release();
            if (need_uninit) CoUninitialize();
            if (out_error) *out_error = "Unable to queue file operation";
            return false;
        }
        ++queued_operations;
    }

    if (dest_item) dest_item->Release();

    if (queued_operations != sources.size() || queued_operations == 0)
    {
        file_op->Release();
        if (need_uninit) CoUninitialize();
        if (out_error) *out_error = "No file operations were queued";
        return false;
    }

    hr = file_op->PerformOperations();
    BOOL aborted = FALSE;
    file_op->GetAnyOperationsAborted(&aborted);
    file_op->Release();

    if (need_uninit) CoUninitialize();

    if (FAILED(hr) || aborted)
    {
        if (out_error) *out_error = "PerformOperations failed (HRESULT: 0x" + std::to_string(hr) + ")";
        return false;
    }

    return true;
}

JsonObject FileServiceV22::DeleteItems(const std::vector<std::string>& paths, bool permanent)
{
    if (paths.empty())
    {
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue("empty_paths");
        return err;
    }

    std::vector<std::wstring> ws_paths;
    for (const auto& p : paths)
    {
        std::wstring canon = CanonicalizePath(ResolveVirtualTarget(p));
        if (GetFileAttributesW(canon.c_str()) != INVALID_FILE_ATTRIBUTES)
        {
            ws_paths.push_back(canon);
        }
    }

    if (ws_paths.empty())
    {
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue("items_not_found");
        return err;
    }

    std::string err_msg;
    bool ok = ExecuteIFileOperation(3, ws_paths, L"", !permanent, &err_msg);

    // A recycle request must never silently degrade into permanent deletion.
    // The direct Win32 fallback is allowed only when permanent deletion was
    // explicitly requested by the caller.
    if (!ok && permanent)
    {
        bool all_deleted = true;
        for (const auto& p : ws_paths)
        {
            DWORD attr = GetFileAttributesW(p.c_str());
            if (attr == INVALID_FILE_ATTRIBUTES) continue;
            if (attr & FILE_ATTRIBUTE_DIRECTORY)
            {
                if (!RemoveDirectoryW(p.c_str())) all_deleted = false;
            }
            else
            {
                if (!DeleteFileW(p.c_str())) all_deleted = false;
            }
        }
        ok = all_deleted;
    }

    if (!ok)
    {
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue(permanent ? "delete_failed" : "recycle_failed");
        err["message"] = JsonValue(err_msg.empty() ? "The requested delete operation failed" : err_msg);
        err["permanent"] = JsonValue(permanent);
        err["deletedCount"] = JsonValue(0);
        return err;
    }

    operations_generation_++;

    JsonObject ev_payload;
    ev_payload["action"] = JsonValue(permanent ? "permanently_deleted" : "recycled");
    JsonArray deleted_arr;
    for (const auto& p : ws_paths) deleted_arr.push_back(JsonValue(Utf16ToUtf8(p)));
    ev_payload["paths"] = JsonValue(deleted_arr);
    EventBusV21::Instance().Publish("files.changed", ev_payload);

    JsonObject res;
    res["ok"] = JsonValue(ok);
    res["permanent"] = JsonValue(permanent);
    res["deletedCount"] = JsonValue(static_cast<double>(ws_paths.size()));
    return res;
}

std::string FileServiceV22::StartCopyJob(
    const std::vector<std::string>& sources,
    const std::string& destination,
    const std::string& overwrite_policy)
{
    std::wstring dest_resolved = CanonicalizePath(ResolveVirtualTarget(destination));
    std::vector<std::wstring> src_resolved;
    for (const auto& s : sources)
    {
        src_resolved.push_back(CanonicalizePath(ResolveVirtualTarget(s)));
    }

    std::string job_id = JobManagerV21::Instance().SubmitJob(
        "files.copy",
        [this, src_resolved, dest_resolved, overwrite_policy](std::atomic_bool& cancel_flag, std::function<void(double)> progress_cb, std::string& err) -> bool {
            if (src_resolved.empty())
            {
                err = "empty_sources";
                return false;
            }
            if (overwrite_policy != "ask" && overwrite_policy != "skip" && overwrite_policy != "replace")
            {
                err = "invalid_overwrite_policy";
                return false;
            }
            const DWORD destination_attributes = GetFileAttributesW(dest_resolved.c_str());
            if (destination_attributes == INVALID_FILE_ATTRIBUTES ||
                (destination_attributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
            {
                err = "destination_not_directory";
                return false;
            }

            size_t total_files = src_resolved.size();

            for (size_t i = 0; i < src_resolved.size(); ++i)
            {
                if (cancel_flag.load())
                {
                    return false;
                }

                const auto& src = src_resolved[i];
                const wchar_t* filename = wcsrchr(src.c_str(), L'\\');
                std::wstring dest_file = dest_resolved;
                if (dest_file.back() != L'\\') dest_file += L'\\';
                dest_file += (filename ? filename + 1 : L"file");

                if (_wcsicmp(src.c_str(), dest_file.c_str()) == 0)
                {
                    err = "source_equals_destination";
                    return false;
                }
                const DWORD source_attributes = GetFileAttributesW(src.c_str());
                if (source_attributes == INVALID_FILE_ATTRIBUTES)
                {
                    err = "source_not_found";
                    return false;
                }
                if ((source_attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 && IsSameOrDescendantPath(dest_file, src))
                {
                    err = "destination_inside_source";
                    return false;
                }

                if (progress_cb)
                {
                    progress_cb((static_cast<double>(i) / total_files) * 100.0);
                }

                if (!CopyPathRecursive(src, dest_file, overwrite_policy, cancel_flag, &err))
                {
                    return false;
                }
            }

            if (cancel_flag.load())
            {
                err = "cancelled";
                return false;
            }
            if (progress_cb) progress_cb(100.0);

            operations_generation_++;

            JsonObject ev_payload;
            ev_payload["action"] = JsonValue("copied");
            ev_payload["destination"] = JsonValue(Utf16ToUtf8(dest_resolved));
            EventBusV21::Instance().Publish("files.changed", ev_payload);
            return true;
        });

    return job_id;
}

std::string FileServiceV22::StartMoveJob(
    const std::vector<std::string>& sources,
    const std::string& destination,
    const std::string& overwrite_policy)
{
    std::wstring dest_resolved = CanonicalizePath(ResolveVirtualTarget(destination));
    std::vector<std::wstring> src_resolved;
    for (const auto& s : sources)
    {
        src_resolved.push_back(CanonicalizePath(ResolveVirtualTarget(s)));
    }

    std::string job_id = JobManagerV21::Instance().SubmitJob(
        "files.move",
        [this, src_resolved, dest_resolved, overwrite_policy](std::atomic_bool& cancel_flag, std::function<void(double)> progress_cb, std::string& err) -> bool {
            if (src_resolved.empty())
            {
                err = "empty_sources";
                return false;
            }
            if (overwrite_policy != "ask" && overwrite_policy != "skip" && overwrite_policy != "replace")
            {
                err = "invalid_overwrite_policy";
                return false;
            }
            const DWORD destination_attributes = GetFileAttributesW(dest_resolved.c_str());
            if (destination_attributes == INVALID_FILE_ATTRIBUTES ||
                (destination_attributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
            {
                err = "destination_not_directory";
                return false;
            }

            size_t total_files = src_resolved.size();

            for (size_t i = 0; i < src_resolved.size(); ++i)
            {
                if (cancel_flag.load()) return false;

                const auto& src = src_resolved[i];
                const wchar_t* filename = wcsrchr(src.c_str(), L'\\');
                std::wstring dest_file = dest_resolved;
                if (dest_file.back() != L'\\') dest_file += L'\\';
                dest_file += (filename ? filename + 1 : L"file");

                if (_wcsicmp(src.c_str(), dest_file.c_str()) == 0)
                {
                    err = "source_equals_destination";
                    return false;
                }
                const DWORD source_attributes = GetFileAttributesW(src.c_str());
                if (source_attributes == INVALID_FILE_ATTRIBUTES)
                {
                    err = "source_not_found";
                    return false;
                }
                if ((source_attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 && IsSameOrDescendantPath(dest_file, src))
                {
                    err = "destination_inside_source";
                    return false;
                }

                const DWORD existing_attributes = GetFileAttributesW(dest_file.c_str());
                if (existing_attributes != INVALID_FILE_ATTRIBUTES)
                {
                    if (overwrite_policy == "skip") continue;
                    if (overwrite_policy == "ask")
                    {
                        err = "destination_exists";
                        return false;
                    }
                }

                if (progress_cb)
                {
                    progress_cb((static_cast<double>(i) / total_files) * 100.0);
                }

                DWORD flags = MOVEFILE_COPY_ALLOWED;
                if (overwrite_policy == "replace") flags |= MOVEFILE_REPLACE_EXISTING;
                if (!MoveFileExW(src.c_str(), dest_file.c_str(), flags))
                {
                    std::string operation_error;
                    if (!ExecuteIFileOperation(2, {src}, dest_resolved, false, &operation_error))
                    {
                        err = operation_error.empty()
                            ? "move_failed:" + std::to_string(GetLastError())
                            : operation_error;
                        return false;
                    }
                }
            }

            if (cancel_flag.load())
            {
                err = "cancelled";
                return false;
            }
            if (progress_cb) progress_cb(100.0);

            operations_generation_++;

            JsonObject ev_payload;
            ev_payload["action"] = JsonValue("moved");
            ev_payload["destination"] = JsonValue(Utf16ToUtf8(dest_resolved));
            EventBusV21::Instance().Publish("files.changed", ev_payload);
            return true;
        });

    return job_id;
}

std::string FileServiceV22::StartSearchJob(
    const std::string& root_path,
    const std::string& query,
    bool recursive,
    size_t max_results)
{
    std::wstring resolved_root = CanonicalizePath(ResolveVirtualTarget(root_path));
    std::wstring search_query = Utf8ToUtf16(query);
    std::transform(search_query.begin(), search_query.end(), search_query.begin(), ::towlower);

    LocationKind root_location = LocationKind::Windows;
    std::string root_distro;
    if (StartsWithInsensitive(resolved_root, L"\\\\wsl.localhost\\") ||
        StartsWithInsensitive(resolved_root, L"\\\\wsl$\\"))
    {
        root_location = LocationKind::Wsl;
        const size_t prefix_length = StartsWithInsensitive(resolved_root, L"\\\\wsl.localhost\\") ? 16 : 7;
        const size_t slash = resolved_root.find(L'\\', prefix_length);
        root_distro = Utf16ToUtf8(resolved_root.substr(
            prefix_length,
            slash == std::wstring::npos ? std::wstring::npos : slash - prefix_length));
    }
    else if (StartsWithInsensitive(resolved_root, L"\\\\"))
    {
        root_location = LocationKind::Network;
    }

    std::string job_id = JobManagerV21::Instance().SubmitJob(
        "files.search",
        [this, resolved_root, search_query, recursive, max_results, root_location, root_distro](std::atomic_bool& cancel_flag, std::function<void(double)> progress_cb, std::string& err) -> bool {
            (void)err;
            std::vector<std::wstring> dirs_to_search = {resolved_root};
            std::vector<CloudFileItemMetadata> matches;

            size_t scanned_dirs = 0;
            while (!dirs_to_search.empty() && matches.size() < max_results)
            {
                if (cancel_flag.load()) break;

                std::wstring current_dir = dirs_to_search.back();
                dirs_to_search.pop_back();
                scanned_dirs++;

                if (progress_cb)
                {
                    progress_cb(std::min(99.0, static_cast<double>(scanned_dirs * 2)));
                }

                std::wstring pattern = current_dir;
                if (pattern.back() != L'\\') pattern += L'\\';
                pattern += L"*";

                WIN32_FIND_DATAW fd{};
                HANDLE hFind = FindFirstFileExW(pattern.c_str(), FindExInfoBasic, &fd, FindExSearchNameMatch, nullptr, FIND_FIRST_EX_LARGE_FETCH);
                if (hFind == INVALID_HANDLE_VALUE) continue;

                do
                {
                    if (wcscmp(fd.cFileName, L".") == 0 || wcscmp(fd.cFileName, L"..") == 0) continue;

                    std::wstring name_lower = fd.cFileName;
                    std::transform(name_lower.begin(), name_lower.end(), name_lower.begin(), ::towlower);

                    if (name_lower.find(search_query) != std::wstring::npos)
                    {
                        matches.push_back(BuildMetadataFromFindData(current_dir, fd, root_location, root_distro));
                        if (matches.size() >= max_results) break;
                    }

                    if (recursive && (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && !(fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT))
                    {
                        std::wstring sub_dir = current_dir;
                        if (sub_dir.back() != L'\\') sub_dir += L'\\';
                        sub_dir += fd.cFileName;
                        dirs_to_search.push_back(sub_dir);
                    }
                } while (FindNextFileW(hFind, &fd));

                FindClose(hFind);
            }

            JsonArray matches_arr;
            for (const auto& m : matches)
            {
                JsonObject obj;
                obj["id"] = JsonValue(m.id);
                obj["name"] = JsonValue(m.name);
                obj["path"] = JsonValue(m.path);
                obj["isDirectory"] = JsonValue(m.is_directory);
                obj["size"] = JsonValue(static_cast<double>(m.size));
                obj["modifiedTime"] = JsonValue(m.modified_time);
                obj["iconKey"] = JsonValue(m.icon_key);
                matches_arr.push_back(JsonValue(obj));
            }

            JsonObject ev_payload;
            ev_payload["totalMatches"] = JsonValue(static_cast<double>(matches.size()));
            ev_payload["results"] = JsonValue(matches_arr);
            EventBusV21::Instance().Publish("files.searchCompleted", ev_payload);
            return true;
        });

    return job_id;
}

bool FileServiceV22::TryMapWindowsPathToLinux(
    const std::string& distro,
    const std::wstring& windows_path,
    std::wstring* out_linux_path)
{
    if (!out_linux_path || windows_path.empty() || distro.empty()) return false;
    out_linux_path->clear();

    constexpr std::wstring_view local_prefix = L"\\\\wsl.localhost\\";
    constexpr std::wstring_view legacy_prefix = L"\\\\wsl$\\";

    std::size_t prefix_len = 0;
    if (StartsWithInsensitive(windows_path, local_prefix)) prefix_len = local_prefix.size();
    else if (StartsWithInsensitive(windows_path, legacy_prefix)) prefix_len = legacy_prefix.size();

    if (prefix_len > 0)
    {
        size_t slash = windows_path.find_first_of(L"\\/", prefix_len);
        std::wstring path_distro = windows_path.substr(prefix_len, slash == std::wstring::npos ? std::wstring::npos : slash - prefix_len);
        std::wstring wdistro = Utf8ToUtf16(distro);
        if (_wcsicmp(path_distro.c_str(), wdistro.c_str()) != 0)
        {
            return false; // Cross-distro mapping is forbidden
        }

        if (slash == std::wstring::npos)
        {
            *out_linux_path = L"/";
            return true;
        }

        std::wstring mapped = windows_path.substr(slash);
        std::replace(mapped.begin(), mapped.end(), L'\\', L'/');
        *out_linux_path = mapped;
        return true;
    }

    // Windows path (e.g. C:\Users\...) -> execute wslpath with an argv-safe
    // command line. No shell parses the user-controlled path.
    std::string out_str;
    if (!RunProcessCapture(
            L"wsl.exe",
            {L"-d", Utf8ToUtf16(distro), L"--", L"wslpath", L"-a", L"-u", windows_path},
            5000,
            &out_str))
    {
        return false;
    }

    // Clean output
    while (!out_str.empty() && (out_str.back() == '\r' || out_str.back() == '\n' || out_str.back() == ' '))
    {
        out_str.pop_back();
    }

    if (out_str.empty() || out_str[0] != '/') return false;
    *out_linux_path = Utf8ToUtf16(out_str);
    return true;
}

JsonObject FileServiceV22::OpenDefault(const std::string& path_or_id)
{
    std::wstring resolved = CanonicalizePath(ResolveVirtualTarget(path_or_id));
    DWORD attr = GetFileAttributesW(resolved.c_str());
    if (attr == INVALID_FILE_ATTRIBUTES)
    {
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue("not_found");
        return err;
    }

    if (attr & FILE_ATTRIBUTE_DIRECTORY)
    {
        JsonObject res;
        res["ok"] = JsonValue(true);
        res["navigate"] = JsonValue(true);
        res["path"] = JsonValue(Utf16ToUtf8(resolved));
        return res;
    }

    HINSTANCE hInst = ShellExecuteW(nullptr, L"open", resolved.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    bool ok = reinterpret_cast<intptr_t>(hInst) > 32;

    JsonObject res;
    res["ok"] = JsonValue(ok);
    res["navigate"] = JsonValue(false);
    res["path"] = JsonValue(Utf16ToUtf8(resolved));
    return res;
}

JsonObject FileServiceV22::GetOpenWithList(const std::string& path_or_id)
{
    std::wstring resolved = CanonicalizePath(ResolveVirtualTarget(path_or_id));
    const DWORD attributes = GetFileAttributesW(resolved.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
    {
        JsonObject err;
        err["path"] = JsonValue(Utf16ToUtf8(resolved));
        err["apps"] = JsonValue(JsonArray{});
        err["error"] = JsonValue(attributes == INVALID_FILE_ATTRIBUTES ? "not_found" : "not_a_file");
        return err;
    }

    const wchar_t* dot = wcsrchr(resolved.c_str(), L'.');
    std::wstring ext = dot ? dot : L"";

    JsonArray apps_arr;

    // 1. Query Windows Shell Associations
    if (!ext.empty())
    {
        wchar_t default_app[MAX_PATH] = {0};
        DWORD cch = MAX_PATH;
        if (SUCCEEDED(AssocQueryStringW(ASSOCF_INIT_DEFAULTTOSTAR, ASSOCSTR_FRIENDLYAPPNAME, ext.c_str(), nullptr, default_app, &cch)) && default_app[0])
        {
            wchar_t exe_path[MAX_PATH] = {0};
            DWORD cch_exe = MAX_PATH;
            AssocQueryStringW(ASSOCF_INIT_DEFAULTTOSTAR, ASSOCSTR_EXECUTABLE, ext.c_str(), nullptr, exe_path, &cch_exe);

            JsonObject app;
            app["appId"] = JsonValue("windows:default");
            app["name"] = JsonValue(Utf16ToUtf8(default_app));
            app["platform"] = JsonValue("windows");
            app["distro"] = JsonValue("");
            app["iconKey"] = JsonValue("window");
            app["isDefault"] = JsonValue(true);
            app["isRecommended"] = JsonValue(true);
            apps_arr.push_back(JsonValue(app));
        }

        // Add installed Windows apps only. SearchPathW also covers Windows app
        // execution aliases exposed to the current user.
        std::wstring ext_lower = ext;
        std::transform(ext_lower.begin(), ext_lower.end(), ext_lower.begin(), ::towlower);

        if (ext_lower == L".txt" || ext_lower == L".log" || ext_lower == L".ini" || ext_lower == L".md" || ext_lower == L".json" || ext_lower == L".dart")
        {
            std::wstring executable;
            if (FindExecutable(L"notepad.exe", &executable))
            {
                JsonObject notepad;
                notepad["appId"] = JsonValue("windows:notepad");
                notepad["name"] = JsonValue("Bloco de Notas (Windows)");
                notepad["platform"] = JsonValue("windows");
                notepad["distro"] = JsonValue("");
                notepad["iconKey"] = JsonValue("file_text");
                notepad["isDefault"] = JsonValue(false);
                notepad["isRecommended"] = JsonValue(true);
                apps_arr.push_back(JsonValue(notepad));
            }

            if (FindExecutable(L"code.exe", &executable))
            {
                JsonObject vscode;
                vscode["appId"] = JsonValue("windows:vscode");
                vscode["name"] = JsonValue("Visual Studio Code");
                vscode["platform"] = JsonValue("windows");
                vscode["distro"] = JsonValue("");
                vscode["iconKey"] = JsonValue("code");
                vscode["isDefault"] = JsonValue(false);
                vscode["isRecommended"] = JsonValue(true);
                apps_arr.push_back(JsonValue(vscode));
            }
        }
    }

    JsonObject chooser;
    chooser["appId"] = JsonValue("windows:choose");
    chooser["name"] = JsonValue("Escolher outro aplicativo...");
    chooser["platform"] = JsonValue("windows");
    chooser["distro"] = JsonValue("");
    chooser["iconKey"] = JsonValue("window");
    chooser["isDefault"] = JsonValue(false);
    chooser["isRecommended"] = JsonValue(false);
    apps_arr.push_back(JsonValue(chooser));

    // 2. Query real Linux / WSLg executables. Absence is represented by
    // absence from the result; CloudOS never advertises guessed packages.
    std::vector<std::string> distros = WslServiceV21::Instance().GetDistributions();
    static const std::array<std::pair<const char*, const char*>, 7> linux_candidates = {{
        {"gedit", "Editor de Texto (gedit)"},
        {"kate", "Editor de Texto (Kate)"},
        {"xed", "Editor de Texto (Xed)"},
        {"mousepad", "Editor de Texto (Mousepad)"},
        {"vim", "Vim"},
        {"code", "Visual Studio Code"},
        {"gimp", "GIMP Image Editor"},
    }};
    for (const auto& d : distros)
    {
        for (const auto& [command, display_name] : linux_candidates)
        {
            if (!IsWslCommandAvailable(d, command)) continue;
            const bool image_editor = std::string(command) == "gimp";
            JsonObject app;
            app["appId"] = JsonValue("wsl:" + d + ":" + command);
            app["name"] = JsonValue(std::string(display_name) + " (" + d + ")");
            app["platform"] = JsonValue("linux");
            app["distro"] = JsonValue(d);
            app["iconKey"] = JsonValue(image_editor ? "brush" : "file_text");
            app["isDefault"] = JsonValue(false);
            app["isRecommended"] = JsonValue(image_editor
                ? (ext == L".png" || ext == L".jpg" || ext == L".jpeg" || ext == L".webp")
                : (ext == L".txt" || ext == L".md" || ext == L".sh" || ext == L".json"));
            apps_arr.push_back(JsonValue(app));
        }
    }

    JsonObject res;
    res["path"] = JsonValue(Utf16ToUtf8(resolved));
    res["apps"] = JsonValue(apps_arr);
    return res;
}

JsonObject FileServiceV22::LaunchOpenWith(
    const std::string& path_or_id,
    const std::string& app_id,
    const std::string& platform,
    const std::string& distro)
{
    std::wstring resolved = CanonicalizePath(ResolveVirtualTarget(path_or_id));
    const DWORD attributes = GetFileAttributesW(resolved.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
    {
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue(attributes == INVALID_FILE_ATTRIBUTES ? "not_found" : "not_a_file");
        return err;
    }

    if (platform == "linux" || app_id.rfind("wsl:", 0) == 0)
    {
        std::string target_distro = distro;
        if (target_distro.empty())
        {
            size_t first_colon = app_id.find(':');
            size_t second_colon = app_id.find(':', first_colon + 1);
            if (first_colon != std::string::npos && second_colon != std::string::npos)
            {
                target_distro = app_id.substr(first_colon + 1, second_colon - first_colon - 1);
            }
        }

        const size_t final_colon = app_id.rfind(':');
        if (target_distro.empty() || final_colon == std::string::npos || final_colon + 1 >= app_id.size())
        {
            JsonObject err;
            err["ok"] = JsonValue(false);
            err["error"] = JsonValue("invalid_app_id");
            return err;
        }
        const size_t first_colon = app_id.find(':');
        const std::string app_distro = app_id.substr(first_colon + 1, final_colon - first_colon - 1);
        if (app_distro != target_distro)
        {
            JsonObject err;
            err["ok"] = JsonValue(false);
            err["error"] = JsonValue("distro_mismatch");
            return err;
        }
        const std::string command = app_id.substr(final_colon + 1);
        if (!IsAllowedWslOpenWithCommand(command) || !IsWslCommandAvailable(target_distro, command))
        {
            JsonObject err;
            err["ok"] = JsonValue(false);
            err["error"] = JsonValue("app_not_found");
            err["message"] = JsonValue("The selected Linux application is not installed in distro " + target_distro);
            return err;
        }

        std::wstring linux_path;
        if (!TryMapWindowsPathToLinux(target_distro, resolved, &linux_path))
        {
            JsonObject err;
            err["ok"] = JsonValue(false);
            err["error"] = JsonValue("wsl_mapping_failed");
            err["message"] = JsonValue("Could not map path to Linux inside distro " + target_distro);
            return err;
        }

        const std::wstring wsl_exe = L"wsl.exe";
        std::wstring params = L"-d " + QuoteWindowsArgument(Utf8ToUtf16(target_distro)) +
            L" -- " + QuoteWindowsArgument(Utf8ToUtf16(command)) + L" " + QuoteWindowsArgument(linux_path);

        HINSTANCE hInst = ShellExecuteW(nullptr, L"open", wsl_exe.c_str(), params.c_str(), nullptr, SW_HIDE);
        bool ok = reinterpret_cast<intptr_t>(hInst) > 32;

        JsonObject res;
        res["ok"] = JsonValue(ok);
        res["platform"] = JsonValue("linux");
        res["distro"] = JsonValue(target_distro);
        res["linuxPath"] = JsonValue(Utf16ToUtf8(linux_path));
        return res;
    }

    // Windows launch
    if (app_id == "windows:notepad")
    {
        std::wstring executable;
        if (!FindExecutable(L"notepad.exe", &executable))
        {
            JsonObject err;
            err["ok"] = JsonValue(false);
            err["error"] = JsonValue("app_not_found");
            return err;
        }
        const std::wstring quoted_path = QuoteWindowsArgument(resolved);
        HINSTANCE hInst = ShellExecuteW(nullptr, L"open", executable.c_str(), quoted_path.c_str(), nullptr, SW_SHOWNORMAL);
        JsonObject res;
        res["ok"] = JsonValue(reinterpret_cast<intptr_t>(hInst) > 32);
        res["platform"] = JsonValue("windows");
        return res;
    }

    if (app_id == "windows:vscode")
    {
        std::wstring executable;
        if (!FindExecutable(L"code.exe", &executable))
        {
            JsonObject err;
            err["ok"] = JsonValue(false);
            err["error"] = JsonValue("app_not_found");
            return err;
        }
        const std::wstring quoted_path = QuoteWindowsArgument(resolved);
        HINSTANCE hInst = ShellExecuteW(nullptr, L"open", executable.c_str(), quoted_path.c_str(), nullptr, SW_SHOWNORMAL);
        JsonObject res;
        res["ok"] = JsonValue(reinterpret_cast<intptr_t>(hInst) > 32);
        res["platform"] = JsonValue("windows");
        return res;
    }

    if (app_id == "windows:choose")
    {
        const std::wstring parameters = L"shell32.dll,OpenAs_RunDLL " + QuoteWindowsArgument(resolved);
        HINSTANCE hInst = ShellExecuteW(nullptr, L"open", L"rundll32.exe", parameters.c_str(), nullptr, SW_SHOWNORMAL);
        JsonObject res;
        res["ok"] = JsonValue(reinterpret_cast<intptr_t>(hInst) > 32);
        res["platform"] = JsonValue("windows");
        return res;
    }

    if (app_id != "windows:default")
    {
        JsonObject err;
        err["ok"] = JsonValue(false);
        err["error"] = JsonValue("invalid_app_id");
        return err;
    }

    HINSTANCE hInst = ShellExecuteW(nullptr, L"open", resolved.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    JsonObject res;
    res["ok"] = JsonValue(reinterpret_cast<intptr_t>(hInst) > 32);
    res["platform"] = JsonValue("windows");
    return res;
}

} // namespace CloudOS
