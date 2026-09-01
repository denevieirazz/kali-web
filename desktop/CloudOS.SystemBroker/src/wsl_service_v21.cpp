#include "wsl_service_v21.h"

#include <Windows.h>

#include <algorithm>
#include <cwctype>
#include <string>
#include <utility>
#include <vector>

namespace CloudOS
{

namespace
{
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

    std::string result(size_needed, '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            wstr.data(),
            static_cast<int>(wstr.size()),
            result.data(),
            size_needed,
            nullptr,
            nullptr) <= 0)
    {
        return {};
    }
    return result;
}

bool ReadRegString(HKEY key, const wchar_t* value_name, std::wstring& value)
{
    value.clear();

    DWORD type = 0;
    DWORD bytes = 0;
    LONG result = RegQueryValueExW(
        key,
        value_name,
        nullptr,
        &type,
        nullptr,
        &bytes);
    if (result != ERROR_SUCCESS || bytes < sizeof(wchar_t) ||
        (type != REG_SZ && type != REG_EXPAND_SZ))
    {
        return false;
    }

    std::vector<wchar_t> buffer((bytes / sizeof(wchar_t)) + 1, L'\0');
    result = RegQueryValueExW(
        key,
        value_name,
        nullptr,
        &type,
        reinterpret_cast<LPBYTE>(buffer.data()),
        &bytes);
    if (result != ERROR_SUCCESS)
    {
        return false;
    }

    buffer.back() = L'\0';
    value.assign(buffer.data());
    return !value.empty();
}

std::wstring LowerWide(std::wstring value)
{
    std::transform(
        value.begin(),
        value.end(),
        value.begin(),
        [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
    return value;
}

bool IsSafeDistroName(const std::wstring& name)
{
    if (name.empty() || name.size() > 128) return false;

    // WSL distribution names become both command arguments and UNC path
    // components. Reject path/quote/control characters instead of trying to
    // reinterpret a malformed registry value.
    for (const wchar_t c : name)
    {
        if (c < 0x20 || c == L'\\' || c == L'/' || c == L':' || c == L'*' ||
            c == L'?' || c == L'"' || c == L'<' || c == L'>' || c == L'|')
        {
            return false;
        }
    }
    return true;
}

struct DistroRecord final
{
    std::wstring registration_id;
    std::wstring display_name;
};
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
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Lxss",
            0,
            KEY_READ,
            &key) == ERROR_SUCCESS)
    {
        std::wstring default_registration;
        ReadRegString(key, L"DefaultDistribution", default_registration);
        default_registration = LowerWide(std::move(default_registration));

        DWORD subkey_count = 0;
        DWORD max_subkey_len = 0;
        if (RegQueryInfoKeyW(
                key,
                nullptr,
                nullptr,
                nullptr,
                &subkey_count,
                &max_subkey_len,
                nullptr,
                nullptr,
                nullptr,
                nullptr,
                nullptr,
                nullptr) == ERROR_SUCCESS)
        {
            std::vector<DistroRecord> records;
            records.reserve(subkey_count);

            std::vector<wchar_t> subkey_name(
                static_cast<size_t>(max_subkey_len) + 2,
                L'\0');

            for (DWORD index = 0; index < subkey_count; ++index)
            {
                DWORD name_len = static_cast<DWORD>(subkey_name.size());
                const LONG enum_result = RegEnumKeyExW(
                    key,
                    index,
                    subkey_name.data(),
                    &name_len,
                    nullptr,
                    nullptr,
                    nullptr,
                    nullptr);
                if (enum_result != ERROR_SUCCESS)
                {
                    continue;
                }

                const std::wstring registration_id(
                    subkey_name.data(),
                    name_len);

                HKEY distro_key = nullptr;
                if (RegOpenKeyExW(
                        key,
                        registration_id.c_str(),
                        0,
                        KEY_READ,
                        &distro_key) != ERROR_SUCCESS)
                {
                    continue;
                }

                std::wstring display_name;
                const bool name_ok = ReadRegString(
                    distro_key,
                    L"DistributionName",
                    display_name);
                RegCloseKey(distro_key);

                if (!name_ok || !IsSafeDistroName(display_name))
                {
                    continue;
                }

                const auto duplicate = std::find_if(
                    records.begin(),
                    records.end(),
                    [&](const DistroRecord& item) {
                        return LowerWide(item.display_name) ==
                            LowerWide(display_name);
                    });
                if (duplicate == records.end())
                {
                    records.push_back({registration_id, display_name});
                }
            }

            std::stable_sort(
                records.begin(),
                records.end(),
                [&](const DistroRecord& a, const DistroRecord& b) {
                    const bool a_default =
                        !default_registration.empty() &&
                        LowerWide(a.registration_id) == default_registration;
                    const bool b_default =
                        !default_registration.empty() &&
                        LowerWide(b.registration_id) == default_registration;
                    if (a_default != b_default) return a_default;
                    return LowerWide(a.display_name) < LowerWide(b.display_name);
                });

            for (const auto& record : records)
            {
                std::string name = WideToUtf8(record.display_name);
                if (!name.empty())
                {
                    distros_.push_back(std::move(name));
                }
            }
        }

        RegCloseKey(key);
    }

    WCHAR sys_dir[MAX_PATH]{};
    if (GetSystemDirectoryW(sys_dir, ARRAYSIZE(sys_dir)) > 0)
    {
        const std::wstring wsl_exe = std::wstring(sys_dir) + L"\\wsl.exe";
        const DWORD attr = GetFileAttributesW(wsl_exe.c_str());
        wsl_available_ =
            attr != INVALID_FILE_ATTRIBUTES &&
            (attr & FILE_ATTRIBUTE_DIRECTORY) == 0;
    }

    // Registered distributions are authoritative evidence that WSL is usable
    // even if the executable probe is blocked by an unusual system layout.
    if (!distros_.empty())
    {
        wsl_available_ = true;
    }

    initialized_.store(true);
}

} // namespace CloudOS
