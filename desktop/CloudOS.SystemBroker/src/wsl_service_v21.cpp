#include "wsl_service_v21.h"

#include <Windows.h>

#include <algorithm>
#include <cctype>

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

std::string LowerAscii(std::string value)
{
    std::transform(
        value.begin(),
        value.end(),
        value.begin(),
        [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
    return value;
}

bool IsKaliName(const std::string& name)
{
    return LowerAscii(name).find("kali") != std::string::npos;
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
    DWORD value = 0;
    DWORD size = sizeof(value);
    if (RegQueryValueExW(
            key,
            value_name,
            nullptr,
            &type,
            reinterpret_cast<LPBYTE>(&value),
            &size) != ERROR_SUCCESS ||
        type != REG_DWORD ||
        size != sizeof(value))
    {
        return false;
    }

    out = value;
    return true;
}

bool ExpandRegistryPath(const std::wstring& raw, std::wstring& expanded)
{
    if (raw.empty()) return false;
    const DWORD required = ExpandEnvironmentStringsW(raw.c_str(), nullptr, 0);
    if (required == 0)
    {
        expanded = raw;
        return true;
    }

    std::vector<wchar_t> buffer(static_cast<size_t>(required), L'\0');
    if (ExpandEnvironmentStringsW(raw.c_str(), buffer.data(), required) == 0)
    {
        expanded = raw;
        return true;
    }

    expanded.assign(buffer.data());
    return !expanded.empty();
}

bool DirectoryExists(const std::wstring& path)
{
    if (path.empty()) return false;
    const DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
           (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

bool ReadDistributionInfo(
    HKEY root,
    const std::wstring& subkey_name,
    bool is_default,
    WslDistributionInfoV21& out)
{
    HKEY distro_key = nullptr;
    if (RegOpenKeyExW(root, subkey_name.c_str(), 0, KEY_READ, &distro_key) != ERROR_SUCCESS)
    {
        return false;
    }

    std::wstring distribution_name;
    const bool has_name = ReadStringValue(distro_key, L"DistributionName", distribution_name);

    DWORD registered_version = 0;
    const bool has_version = ReadDwordValue(distro_key, L"Version", registered_version);

    std::wstring raw_base_path;
    const bool has_base_path = ReadStringValue(distro_key, L"BasePath", raw_base_path);
    RegCloseKey(distro_key);

    if (!has_name) return false;

    out.name = WideToUtf8(distribution_name);
    if (out.name.empty()) return false;

    // WSL currently registers versions 1 or 2. Preserve unknown values as 0
    // instead of inventing a generation when the registry does not prove it.
    out.version = has_version && (registered_version == 1 || registered_version == 2)
        ? static_cast<int>(registered_version)
        : 0;
    out.is_default = is_default;

    std::wstring expanded_base_path;
    out.base_path_present = has_base_path &&
        ExpandRegistryPath(raw_base_path, expanded_base_path) &&
        DirectoryExists(expanded_base_path);

    // This remains passive evidence only. First-run provisioning and command
    // execution are intentionally not inferred from registry/storage state.
    out.is_security_candidate =
        IsKaliName(out.name) && out.version == 2 && out.base_path_present;
    return true;
}

bool ContainsName(
    const std::vector<WslDistributionInfoV21>& values,
    const std::string& name)
{
    const std::string wanted = LowerAscii(name);
    return std::any_of(
        values.begin(),
        values.end(),
        [&wanted](const WslDistributionInfoV21& item) {
            return LowerAscii(item.name) == wanted;
        });
}

bool WslExecutableExists()
{
    wchar_t system_directory[MAX_PATH]{};
    if (GetSystemDirectoryW(system_directory, MAX_PATH) == 0) return false;

    const std::wstring wsl_exe = std::wstring(system_directory) + L"\\wsl.exe";
    const DWORD attributes = GetFileAttributesW(wsl_exe.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
           !(attributes & FILE_ATTRIBUTE_DIRECTORY);
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

WslRuntimeSnapshotV21 WslServiceV21::GetRuntimeSnapshot()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!initialized_.load()) Refresh();

    WslRuntimeSnapshotV21 snapshot;
    snapshot.engine_available = wsl_engine_available_;
    snapshot.usable = wsl_available_;
    snapshot.passive_ready = passive_ready_;
    snapshot.distributions = distro_infos_;
    snapshot.default_distribution = default_distro_;
    snapshot.preferred_security_distribution = preferred_security_distro_;
    snapshot.registered_count = static_cast<uint32_t>(distro_infos_.size());
    snapshot.launch_candidate_count = launch_candidate_count_;
    snapshot.wsl1_count = wsl1_count_;
    snapshot.wsl2_count = wsl2_count_;
    return snapshot;
}

void WslServiceV21::Invalidate()
{
    std::lock_guard<std::mutex> lock(mutex_);
    Refresh();
    generation_++;
}

void WslServiceV21::Refresh()
{
    distro_infos_.clear();
    distros_.clear();
    default_distro_.clear();
    preferred_security_distro_.clear();
    launch_candidate_count_ = 0;
    wsl1_count_ = 0;
    wsl2_count_ = 0;
    passive_ready_ = false;
    wsl_engine_available_ = WslExecutableExists();
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
        const bool has_registered_default =
            ReadStringValue(root, L"DefaultDistribution", default_subkey);

        // Preserve the real Windows default first for the legacy string list,
        // but only when that registration can actually be resolved.
        if (has_registered_default)
        {
            WslDistributionInfoV21 info;
            if (ReadDistributionInfo(root, default_subkey, true, info))
            {
                default_distro_ = info.name;
                distro_infos_.push_back(info);
            }
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

            const std::wstring current_subkey(subkey_name, name_len);
            WslDistributionInfoV21 info;
            if (!ReadDistributionInfo(
                    root,
                    current_subkey,
                    has_registered_default && current_subkey == default_subkey,
                    info))
            {
                continue;
            }

            if (!ContainsName(distro_infos_, info.name))
            {
                distro_infos_.push_back(std::move(info));
            }
        }
        RegCloseKey(root);
    }

    distros_.reserve(distro_infos_.size());
    for (const auto& info : distro_infos_)
    {
        distros_.push_back(info.name);
        if (info.base_path_present) ++launch_candidate_count_;
        if (info.version == 1) ++wsl1_count_;
        if (info.version == 2) ++wsl2_count_;
        if (preferred_security_distro_.empty() && info.is_security_candidate)
        {
            preferred_security_distro_ = info.name;
        }
    }

    // Existing V21 callers interpret wslAvailable as "engine + registration".
    // Preserve that contract while publishing stronger passive evidence in the
    // additive runtime snapshot.
    wsl_available_ = wsl_engine_available_ && !distro_infos_.empty();
    passive_ready_ = wsl_engine_available_ && launch_candidate_count_ > 0;
    initialized_.store(true);
}

} // namespace CloudOS
