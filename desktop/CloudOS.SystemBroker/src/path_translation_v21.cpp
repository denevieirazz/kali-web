#include "path_translation_v21.h"
#include "wsl_service_v21.h"

#include <Windows.h>
#include <ShlObj.h>

#include <algorithm>
#include <cctype>
#include <filesystem>

namespace fs = std::filesystem;

namespace CloudOS
{

namespace
{
std::wstring Utf8ToWide(std::string_view value)
{
    if (value.empty()) return {};
    const int length = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (length <= 0) return {};

    std::wstring result(static_cast<size_t>(length), L'\0');
    return MultiByteToWideChar(
               CP_UTF8,
               MB_ERR_INVALID_CHARS,
               value.data(),
               static_cast<int>(value.size()),
               result.data(),
               length) == length
        ? result
        : std::wstring{};
}

std::string WideToUtf8(const std::wstring& value)
{
    if (value.empty()) return {};
    const int size_needed = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (size_needed <= 0) return {};

    std::string result(static_cast<size_t>(size_needed), '\0');
    return WideCharToMultiByte(
               CP_UTF8,
               WC_ERR_INVALID_CHARS,
               value.data(),
               static_cast<int>(value.size()),
               result.data(),
               size_needed,
               nullptr,
               nullptr) == size_needed
        ? result
        : std::string{};
}
} // namespace

JsonObject MountPointInfo::ToJsonObject() const
{
    JsonObject obj;
    obj["id"] = JsonValue(id);
    obj["label"] = JsonValue(label);
    obj["path"] = JsonValue(path);
    obj["platform"] = JsonValue(platform);
    obj["isOnline"] = JsonValue(is_online);
    return obj;
}

std::string PathTranslationV21::WindowsToLinux(
    const std::string& win_path,
    const std::string& /*distro*/)
{
    if (win_path.empty()) return "/";

    std::string normalized = win_path;
    std::replace(normalized.begin(), normalized.end(), '\\', '/');

    // Handle UNC: //wsl.localhost/<distro>/... or //wsl$/<distro>/...
    std::string lower = normalized;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });

    const std::string_view wsl_localhost = "//wsl.localhost/";
    const std::string_view wsl_dollar = "//wsl$/";

    if (lower.rfind(wsl_localhost, 0) == 0)
    {
        // skip "//wsl.localhost/<distro>"
        const size_t slash = normalized.find('/', wsl_localhost.size());
        if (slash == std::string::npos) return "/";
        return normalized.substr(slash);
    }

    if (lower.rfind(wsl_dollar, 0) == 0)
    {
        // skip "//wsl$/<distro>"
        const size_t slash = normalized.find('/', wsl_dollar.size());
        if (slash == std::string::npos) return "/";
        return normalized.substr(slash);
    }

    // Handle standard drive letter: "C:/foo/bar"
    if (normalized.size() >= 2 &&
        std::isalpha(static_cast<unsigned char>(normalized[0])) &&
        normalized[1] == ':')
    {
        const char drive = static_cast<char>(std::tolower(static_cast<unsigned char>(normalized[0])));
        if (normalized.size() == 2)
        {
            return std::string("/mnt/") + drive;
        }
        if (normalized[2] == '/')
        {
            return std::string("/mnt/") + drive + normalized.substr(2);
        }
        return std::string("/mnt/") + drive + "/" + normalized.substr(2);
    }

    // If already Linux absolute path
    if (normalized.front() == '/')
    {
        return normalized;
    }

    return "/" + normalized;
}

std::string PathTranslationV21::LinuxToWindows(
    const std::string& linux_path,
    const std::string& distro)
{
    if (linux_path.empty()) return "C:\\";

    std::string normalized = linux_path;
    std::replace(normalized.begin(), normalized.end(), '/', '\\');

    // Check if path is already Windows style: "C:\..." or "\\wsl.localhost\..."
    if (normalized.size() >= 2 &&
        std::isalpha(static_cast<unsigned char>(normalized[0])) &&
        normalized[1] == ':')
    {
        return normalized;
    }
    if (normalized.rfind("\\\\", 0) == 0)
    {
        return normalized;
    }

    // Handle /mnt/<drive>/... -> <Drive>:\...
    std::string lower = normalized;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });

    if (lower.rfind("\\mnt\\", 0) == 0 && lower.size() >= 6)
    {
        const char drive = static_cast<char>(std::toupper(static_cast<unsigned char>(lower[5])));
        if (std::isalpha(static_cast<unsigned char>(drive)))
        {
            if (lower.size() == 6)
            {
                return std::string(1, drive) + ":\\";
            }
            if (lower[6] == '\\')
            {
                return std::string(1, drive) + ":" + normalized.substr(6);
            }
        }
    }

    // Resolve distro
    std::string resolved_distro = distro;
    if (resolved_distro.empty())
    {
        resolved_distro = WslServiceV21::Instance().GetDefaultDistribution();
    }
    if (resolved_distro.empty())
    {
        resolved_distro = "Ubuntu";
    }

    // Linux native path: prefix with \\wsl.localhost\<distro>
    std::string prefix = "\\\\wsl.localhost\\" + resolved_distro;
    if (normalized.empty() || normalized == "\\")
    {
        return prefix + "\\";
    }
    if (normalized.front() == '\\')
    {
        return prefix + normalized;
    }
    return prefix + "\\" + normalized;
}

std::vector<MountPointInfo> PathTranslationV21::GetMountPoints()
{
    std::vector<MountPointInfo> mounts;

    // 1. Windows Volumes
    wchar_t drive_strings[512]{};
    const DWORD length = GetLogicalDriveStringsW(ARRAYSIZE(drive_strings), drive_strings);
    if (length > 0 && length < ARRAYSIZE(drive_strings))
    {
        const wchar_t* ptr = drive_strings;
        while (*ptr != L'\0')
        {
            std::wstring drive(ptr);
            std::string utf8_drive = WideToUtf8(drive);
            std::string id = utf8_drive;
            if (!id.empty() && id.back() == '\\') id.pop_back();
            if (!id.empty() && id.back() == ':') id.pop_back();
            std::transform(id.begin(), id.end(), id.begin(), [](unsigned char c) {
                return static_cast<char>(std::tolower(c));
            });

            MountPointInfo info;
            info.id = id;
            info.label = "Disco Local (" + utf8_drive.substr(0, 2) + ")";
            info.path = utf8_drive;
            info.platform = "windows";
            info.is_online = true;
            mounts.push_back(std::move(info));

            ptr += drive.size() + 1;
        }
    }

    // 2. CloudOS Drive
    PWSTR local_app_data = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &local_app_data)) &&
        local_app_data != nullptr)
    {
        std::wstring cloud_drive = std::wstring(local_app_data) + L"\\CloudOS\\Drive";
        CoTaskMemFree(local_app_data);

        MountPointInfo drive_info;
        drive_info.id = "cloud-drive";
        drive_info.label = "CloudOS Drive";
        drive_info.path = WideToUtf8(cloud_drive);
        drive_info.platform = "cloudDrive";
        drive_info.is_online = true;
        mounts.push_back(std::move(drive_info));
    }

    // 3. WSL Linux Distros
    const auto distros = WslServiceV21::Instance().GetDistroDetails();
    for (const auto& distro : distros)
    {
        MountPointInfo distro_mount;
        distro_mount.id = distro.id;
        std::transform(distro_mount.id.begin(), distro_mount.id.end(), distro_mount.id.begin(), [](unsigned char c) {
            return static_cast<char>(std::tolower(c));
        });
        distro_mount.label = distro.name + " (WSL" + std::to_string(distro.version) + ")";
        distro_mount.path = "\\\\wsl.localhost\\" + distro.name + "\\";
        distro_mount.platform = "linux";
        distro_mount.is_online = (distro.state == "Running");
        mounts.push_back(std::move(distro_mount));
    }

    return mounts;
}

bool PathTranslationV21::PathExists(
    const std::string& path,
    const std::string& distro)
{
    if (path.empty()) return false;

    // Convert to Windows path if not already
    const std::string win_path = LinuxToWindows(path, distro);
    const std::wstring wide_path = Utf8ToWide(win_path);
    if (wide_path.empty()) return false;

    const DWORD attributes = GetFileAttributesW(wide_path.c_str());
    return (attributes != INVALID_FILE_ATTRIBUTES);
}

} // namespace CloudOS
