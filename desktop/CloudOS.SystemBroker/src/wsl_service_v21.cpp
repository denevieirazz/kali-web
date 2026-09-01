#include "wsl_service_v21.h"

#include <Windows.h>

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

            const std::string distro = ReadDistributionName(root, std::wstring(subkey_name, name_len));
            if (!distro.empty() && !Contains(distros_, distro)) distros_.push_back(distro);
        }
        RegCloseKey(root);
    }

    if (default_distro_.empty() && !distros_.empty())
    {
        default_distro_ = distros_.front();
    }

    wchar_t system_directory[MAX_PATH]{};
    if (GetSystemDirectoryW(system_directory, MAX_PATH) > 0)
    {
        const std::wstring wsl_exe = std::wstring(system_directory) + L"\\wsl.exe";
        const DWORD attributes = GetFileAttributesW(wsl_exe.c_str());
        if (attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY))
        {
            wsl_available_ = true;
        }
    }

    if (!distros_.empty()) wsl_available_ = true;
    initialized_.store(true);
}

} // namespace CloudOS
