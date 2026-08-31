#include "wsl_service_v21.h"

#include <Windows.h>

namespace CloudOS
{

namespace
{
std::string WideToUtf8(const std::wstring& wstr)
{
    if (wstr.empty()) return {};
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), nullptr, 0, nullptr, nullptr);
    if (size_needed <= 0) return {};
    std::string result(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), result.data(), size_needed, nullptr, nullptr);
    return result;
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
    if (!initialized_.load())
    {
        Refresh();
    }
    return wsl_available_;
}

std::vector<std::string> WslServiceV21::GetDistributions()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!initialized_.load())
    {
        Refresh();
    }
    return distros_;
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
    wsl_available_ = false;

    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Lxss", 0, KEY_READ, &key) == ERROR_SUCCESS)
    {
        DWORD index = 0;
        WCHAR subkey_name[256];
        DWORD name_len = ARRAYSIZE(subkey_name);

        while (RegEnumKeyExW(key, index++, subkey_name, &name_len, nullptr, nullptr, nullptr, nullptr) == ERROR_SUCCESS)
        {
            HKEY distro_key = nullptr;
            if (RegOpenKeyExW(key, subkey_name, 0, KEY_READ, &distro_key) == ERROR_SUCCESS)
            {
                WCHAR distro_name[256];
                DWORD distro_name_size = sizeof(distro_name);
                DWORD type = 0;
                if (RegQueryValueExW(distro_key, L"DistributionName", nullptr, &type, reinterpret_cast<LPBYTE>(distro_name), &distro_name_size) == ERROR_SUCCESS)
                {
                    distros_.push_back(WideToUtf8(distro_name));
                }
                RegCloseKey(distro_key);
            }
            name_len = ARRAYSIZE(subkey_name);
        }
        RegCloseKey(key);
    }

    WCHAR sys_dir[MAX_PATH];
    if (GetSystemDirectoryW(sys_dir, MAX_PATH) > 0)
    {
        std::wstring wsl_exe = std::wstring(sys_dir) + L"\\wsl.exe";
        DWORD attr = GetFileAttributesW(wsl_exe.c_str());
        if (attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY))
        {
            wsl_available_ = true;
            if (distros_.empty())
            {
                distros_.push_back("Ubuntu");
            }
        }
    }

    if (!distros_.empty())
    {
        wsl_available_ = true;
    }

    initialized_.store(true);
}

} // namespace CloudOS
