#include "wsl_service_v21.h"

#include <Windows.h>

#include <algorithm>
#include <vector>

namespace CloudOS
{

namespace
{
constexpr DWORD kMaxRegistryStringBytes = 64 * 1024;

std::string WideToUtf8(const std::wstring& wstr)
{
    if (wstr.empty()) return {};
    const int size_needed = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        wstr.data(),
        static_cast<int>(wstr.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (size_needed <= 0) return {};

    std::string result(static_cast<size_t>(size_needed), '\0');
    return WideCharToMultiByte(
               CP_UTF8,
               WC_ERR_INVALID_CHARS,
               wstr.data(),
               static_cast<int>(wstr.size()),
               result.data(),
               size_needed,
               nullptr,
               nullptr) == size_needed
        ? result
        : std::string{};
}

bool ReadRegistryString(HKEY key, const wchar_t* value_name, std::wstring& out)
{
    out.clear();

    DWORD type = 0;
    DWORD byte_count = 0;
    const LONG size_status = RegQueryValueExW(
        key,
        value_name,
        nullptr,
        &type,
        nullptr,
        &byte_count);
    if (size_status != ERROR_SUCCESS ||
        (type != REG_SZ && type != REG_EXPAND_SZ) ||
        byte_count == 0 ||
        byte_count > kMaxRegistryStringBytes)
    {
        return false;
    }

    const size_t wchar_count =
        static_cast<size_t>(byte_count / sizeof(wchar_t)) + 1;
    std::vector<wchar_t> buffer(wchar_count, L'\0');
    DWORD actual_bytes = byte_count;
    const LONG read_status = RegQueryValueExW(
        key,
        value_name,
        nullptr,
        &type,
        reinterpret_cast<LPBYTE>(buffer.data()),
        &actual_bytes);
    if (read_status != ERROR_SUCCESS ||
        (type != REG_SZ && type != REG_EXPAND_SZ))
    {
        return false;
    }

    const size_t actual_chars = std::min<size_t>(
        actual_bytes / sizeof(wchar_t),
        buffer.size() - 1);
    buffer[actual_chars] = L'\0';
    out.assign(buffer.data());
    return !out.empty();
}

bool ContainsDistro(const std::vector<std::string>& distros, const std::string& name)
{
    return std::find(distros.begin(), distros.end(), name) != distros.end();
}
} // namespace

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

void WslServiceV21::Invalidate()
{
    std::lock_guard<std::mutex> lock(mutex_);
    Refresh();
    generation_++;
}

void WslServiceV21::Refresh()
{
    distros_.clear();
    default_distro_.clear();
    wsl_available_ = false;

    HKEY key = nullptr;
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Lxss",
            0,
            KEY_READ,
            &key) == ERROR_SUCCESS)
    {
        std::wstring default_distribution_key;
        ReadRegistryString(key, L"DefaultDistribution", default_distribution_key);

        DWORD subkey_count = 0;
        DWORD max_subkey_name_length = 0;
        if (RegQueryInfoKeyW(
                key,
                nullptr,
                nullptr,
                nullptr,
                &subkey_count,
                &max_subkey_name_length,
                nullptr,
                nullptr,
                nullptr,
                nullptr,
                nullptr,
                nullptr) == ERROR_SUCCESS)
        {
            std::vector<wchar_t> subkey_name(
                static_cast<size_t>(max_subkey_name_length) + 2,
                L'\0');

            for (DWORD index = 0; index < subkey_count; ++index)
            {
                DWORD name_length = static_cast<DWORD>(subkey_name.size() - 1);
                FILETIME last_write{};
                const LONG enum_status = RegEnumKeyExW(
                    key,
                    index,
                    subkey_name.data(),
                    &name_length,
                    nullptr,
                    nullptr,
                    nullptr,
                    &last_write);
                if (enum_status != ERROR_SUCCESS) continue;
                subkey_name[name_length] = L'\0';

                HKEY distro_key = nullptr;
                if (RegOpenKeyExW(
                        key,
                        subkey_name.data(),
                        0,
                        KEY_READ,
                        &distro_key) != ERROR_SUCCESS)
                {
                    continue;
                }

                std::wstring distro_name_wide;
                const bool has_name =
                    ReadRegistryString(distro_key, L"DistributionName", distro_name_wide);
                RegCloseKey(distro_key);
                if (!has_name) continue;

                const std::string distro_name = WideToUtf8(distro_name_wide);
                if (distro_name.empty()) continue;

                if (!ContainsDistro(distros_, distro_name))
                {
                    distros_.push_back(distro_name);
                }

                if (!default_distribution_key.empty() &&
                    _wcsicmp(
                        default_distribution_key.c_str(),
                        subkey_name.data()) == 0)
                {
                    default_distro_ = distro_name;
                }
            }
        }

        RegCloseKey(key);
    }

    WCHAR sys_dir[MAX_PATH]{};
    const UINT sys_dir_length = GetSystemDirectoryW(sys_dir, MAX_PATH);
    if (sys_dir_length > 0 && sys_dir_length < MAX_PATH)
    {
        const std::wstring wsl_exe = std::wstring(sys_dir) + L"\\wsl.exe";
        const DWORD attr = GetFileAttributesW(wsl_exe.c_str());
        if (attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY))
        {
            wsl_available_ = true;
        }
    }

    if (!distros_.empty()) wsl_available_ = true;
    initialized_.store(true);
}

} // namespace CloudOS
