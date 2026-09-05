#include "wsl_service_v21.h"

#include <Windows.h>
#include <tlhelp32.h>

#include <algorithm>

namespace CloudOS
{

namespace
{
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

bool ReadStringValue(HKEY key, const wchar_t* value_name, std::wstring& out)
{
    DWORD type = 0;
    DWORD size = 0;
    if (RegQueryValueExW(key, value_name, nullptr, &type, nullptr, &size) != ERROR_SUCCESS ||
        (type != REG_SZ && type != REG_EXPAND_SZ) ||
        size < sizeof(wchar_t))
    {
        return false;
    }

    std::vector<wchar_t> buffer((size / sizeof(wchar_t)) + 1, L'\0');
    DWORD read_size = size;
    if (RegQueryValueExW(
            key,
            value_name,
            nullptr,
            &type,
            reinterpret_cast<LPBYTE>(buffer.data()),
            &read_size) != ERROR_SUCCESS)
    {
        return false;
    }

    buffer.back() = L'\0';
    out.assign(buffer.data());
    return !out.empty();
}

bool ReadDwordValue(HKEY key, const wchar_t* value_name, DWORD& out)
{
    DWORD type = 0;
    DWORD size = sizeof(DWORD);
    return RegQueryValueExW(
               key,
               value_name,
               nullptr,
               &type,
               reinterpret_cast<LPBYTE>(&out),
               &size) == ERROR_SUCCESS &&
           type == REG_DWORD;
}

std::string ReadDistributionName(HKEY root, const std::wstring& subkey_name)
{
    HKEY distro_key = nullptr;
    if (RegOpenKeyExW(root, subkey_name.c_str(), 0, KEY_READ, &distro_key) != ERROR_SUCCESS)
    {
        return {};
    }

    std::wstring distribution_name;
    const bool ok = ReadStringValue(distro_key, L"DistributionName", distribution_name);
    RegCloseKey(distro_key);
    return ok ? WideToUtf8(distribution_name) : std::string{};
}

bool Contains(const std::vector<std::string>& values, const std::string& value)
{
    return std::find(values.begin(), values.end(), value) != values.end();
}

bool IsWslVmRunning()
{
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return false;

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);

    bool running = false;
    if (Process32FirstW(snapshot, &entry))
    {
        do
        {
            if (_wcsicmp(entry.szExeFile, L"vmmemWSL.exe") == 0 ||
                _wcsicmp(entry.szExeFile, L"vmmem.exe") == 0 ||
                _wcsicmp(entry.szExeFile, L"wslhost.exe") == 0)
            {
                running = true;
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return running;
}
} // namespace

JsonObject WslDistroInfo::ToJsonObject() const
{
    JsonObject obj;
    obj["id"] = JsonValue(id);
    obj["name"] = JsonValue(name);
    obj["guid"] = JsonValue(guid);
    obj["version"] = JsonValue(static_cast<int64_t>(version));
    obj["state"] = JsonValue(state);
    obj["basePath"] = JsonValue(base_path);
    obj["defaultUid"] = JsonValue(static_cast<int64_t>(default_uid));
    obj["flags"] = JsonValue(static_cast<int64_t>(flags));
    obj["isDefault"] = JsonValue(is_default);
    return obj;
}

WslServiceV21& WslServiceV21::Instance()
{
    static WslServiceV21 instance;
    return instance;
}

bool WslServiceV21::IsWslAvailable()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!initialized_.load()) Refresh();
    return wsl_available_;
}

std::vector<std::string> WslServiceV21::GetDistributions()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!initialized_.load()) Refresh();
    return distros_;
}

std::string WslServiceV21::GetDefaultDistribution()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!initialized_.load()) Refresh();
    return default_distro_;
}

std::vector<WslDistroInfo> WslServiceV21::GetDistroDetails()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!initialized_.load()) Refresh();
    const bool is_running = IsWslVmRunning();
    auto result = distro_details_;
    for (auto& item : result)
    {
        item.state = is_running ? "Running" : "Stopped";
    }
    return result;
}

bool WslServiceV21::IsDistroRunning(const std::string& distro_name)
{
    (void)distro_name;
    return IsWslVmRunning();
}

void WslServiceV21::Invalidate()
{
    std::lock_guard<std::mutex> lock(mutex_);
    Refresh();
    generation_++;
}

void WslServiceV21::Refresh()
{
    distros_.clear();
    distro_details_.clear();
    default_distro_.clear();
    wsl_available_ = false;

    std::wstring default_guid;
    HKEY root = nullptr;
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Lxss",
            0,
            KEY_READ,
            &root) == ERROR_SUCCESS)
    {
        std::wstring default_subkey;
        if (ReadStringValue(root, L"DefaultDistribution", default_subkey))
        {
            default_guid = default_subkey;
            default_distro_ = ReadDistributionName(root, default_subkey);
            if (!default_distro_.empty()) distros_.push_back(default_distro_);
        }

        DWORD index = 0;
        for (;;)
        {
            wchar_t subkey_name[256]{};
            DWORD name_len = ARRAYSIZE(subkey_name);
            const LONG result = RegEnumKeyExW(
                root,
                index++,
                subkey_name,
                &name_len,
                nullptr,
                nullptr,
                nullptr,
                nullptr);
            if (result == ERROR_NO_MORE_ITEMS) break;
            if (result != ERROR_SUCCESS) continue;

            const std::wstring subkey_str(subkey_name, name_len);
            HKEY distro_key = nullptr;
            if (RegOpenKeyExW(root, subkey_str.c_str(), 0, KEY_READ, &distro_key) == ERROR_SUCCESS)
            {
                std::wstring name_wide;
                if (ReadStringValue(distro_key, L"DistributionName", name_wide))
                {
                    const std::string distro = WideToUtf8(name_wide);
                    if (!distro.empty())
                    {
                        if (!Contains(distros_, distro)) distros_.push_back(distro);

                        WslDistroInfo info;
                        info.id = distro;
                        info.name = distro;
                        info.guid = WideToUtf8(subkey_str);
                        info.is_default = (_wcsicmp(subkey_str.c_str(), default_guid.c_str()) == 0);

                        DWORD version = 2;
                        if (ReadDwordValue(distro_key, L"Version", version))
                        {
                            info.version = static_cast<uint32_t>(version);
                        }
                        std::wstring base_path;
                        if (ReadStringValue(distro_key, L"BasePath", base_path))
                        {
                            info.base_path = WideToUtf8(base_path);
                        }
                        DWORD default_uid = 0;
                        if (ReadDwordValue(distro_key, L"DefaultUid", default_uid))
                        {
                            info.default_uid = static_cast<uint32_t>(default_uid);
                        }
                        DWORD flags = 15;
                        if (ReadDwordValue(distro_key, L"Flags", flags))
                        {
                            info.flags = static_cast<uint32_t>(flags);
                        }
                        info.state = "Stopped";
                        distro_details_.push_back(std::move(info));
                    }
                }
                RegCloseKey(distro_key);
            }
        }
        RegCloseKey(root);
    }

    if (default_distro_.empty() && !distros_.empty())
    {
        default_distro_ = distros_.front();
        if (!distro_details_.empty())
        {
            distro_details_.front().is_default = true;
        }
    }

    bool wsl_executable_available = false;
    wchar_t system_directory[MAX_PATH]{};
    if (GetSystemDirectoryW(system_directory, MAX_PATH) > 0)
    {
        const std::wstring wsl_exe = std::wstring(system_directory) + L"\\wsl.exe";
        const DWORD attributes = GetFileAttributesW(wsl_exe.c_str());
        wsl_executable_available =
            attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY);
    }

    // Existing V21 callers interpret wslAvailable as "usable now", not merely
    // "wsl.exe exists". Keep that contract while avoiding any synthetic distro.
    wsl_available_ = wsl_executable_available && !distros_.empty();
    initialized_.store(true);
}

} // namespace CloudOS

