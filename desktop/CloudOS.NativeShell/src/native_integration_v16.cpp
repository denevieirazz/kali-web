#include "native_integration_v16.h"

#include <ShlObj.h>
#include <shellapi.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <set>
#include <string_view>
#include <vector>

#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "shell32.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kUninstallKey[] = L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall";
constexpr std::size_t kMaximumDesktopFileBytes = 1024u * 1024u;

std::wstring Trim(std::wstring value)
{
    const auto whitespace = [](wchar_t ch)
    {
        return ch == L' ' || ch == L'\t' || ch == L'\r' || ch == L'\n' || ch == L'\0';
    };
    while (!value.empty() && whitespace(value.front())) value.erase(value.begin());
    while (!value.empty() && whitespace(value.back())) value.pop_back();
    return value;
}

std::wstring KnownFolder(REFKNOWNFOLDERID id)
{
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(id, KF_FLAG_DEFAULT, nullptr, &raw)) || raw == nullptr)
        return {};
    std::wstring result(raw);
    CoTaskMemFree(raw);
    return result;
}

std::wstring SearchExecutable(const wchar_t* name)
{
    std::array<wchar_t, 32768> path{};
    const DWORD length = SearchPathW(
        nullptr,
        name,
        nullptr,
        static_cast<DWORD>(path.size()),
        path.data(),
        nullptr);
    return length > 0 && length < path.size() ? std::wstring(path.data(), length) : std::wstring{};
}

std::wstring ReadRegistryString(HKEY key, const wchar_t* name)
{
    DWORD type = 0;
    DWORD bytes = 0;
    if (RegQueryValueExW(key, name, nullptr, &type, nullptr, &bytes) != ERROR_SUCCESS ||
        (type != REG_SZ && type != REG_EXPAND_SZ) || bytes < sizeof(wchar_t))
        return {};

    std::wstring value(bytes / sizeof(wchar_t), L'\0');
    if (RegQueryValueExW(
            key,
            name,
            nullptr,
            &type,
            reinterpret_cast<BYTE*>(value.data()),
            &bytes) != ERROR_SUCCESS)
        return {};
    if (!value.empty() && value.back() == L'\0') value.pop_back();
    return Trim(std::move(value));
}

DWORD ReadRegistryDword(HKEY key, const wchar_t* name, DWORD fallback = 0)
{
    DWORD type = 0;
    DWORD value = fallback;
    DWORD bytes = sizeof(value);
    if (RegQueryValueExW(
            key,
            name,
            nullptr,
            &type,
            reinterpret_cast<BYTE*>(&value),
            &bytes) != ERROR_SUCCESS || type != REG_DWORD)
        return fallback;
    return value;
}

std::wstring UnquoteDisplayIcon(std::wstring value)
{
    value = Trim(std::move(value));
    if (value.empty()) return {};
    if (value.front() == L'\"')
    {
        const std::size_t closing = value.find(L'\"', 1);
        if (closing != std::wstring::npos) return value.substr(1, closing - 1);
    }
    const std::size_t comma = value.rfind(L',');
    if (comma != std::wstring::npos) value.resize(comma);
    return Trim(std::move(value));
}

void EnumerateUninstallKey(
    HKEY root,
    REGSAM view,
    const wchar_t* source_label,
    std::vector<UnifiedAppV16>* apps)
{
    if (apps == nullptr) return;
    HKEY parent = nullptr;
    if (RegOpenKeyExW(root, kUninstallKey, 0, KEY_READ | view, &parent) != ERROR_SUCCESS)
        return;

    DWORD subkey_count = 0;
    DWORD maximum_name = 0;
    if (RegQueryInfoKeyW(
            parent,
            nullptr,
            nullptr,
            nullptr,
            &subkey_count,
            &maximum_name,
            nullptr,
            nullptr,
            nullptr,
            nullptr,
            nullptr,
            nullptr) != ERROR_SUCCESS)
    {
        RegCloseKey(parent);
        return;
    }

    std::vector<wchar_t> name(static_cast<std::size_t>(maximum_name) + 2u, L'\0');
    for (DWORD index = 0; index < subkey_count; ++index)
    {
        DWORD length = static_cast<DWORD>(name.size());
        FILETIME modified{};
        if (RegEnumKeyExW(
                parent,
                index,
                name.data(),
                &length,
                nullptr,
                nullptr,
                nullptr,
                &modified) != ERROR_SUCCESS)
            continue;

        HKEY app_key = nullptr;
        if (RegOpenKeyExW(parent, name.data(), 0, KEY_READ | view, &app_key) != ERROR_SUCCESS)
            continue;

        const std::wstring display_name = ReadRegistryString(app_key, L"DisplayName");
        const DWORD system_component = ReadRegistryDword(app_key, L"SystemComponent", 0);
        if (!display_name.empty() && system_component == 0)
        {
            std::wstring uninstall = ReadRegistryString(app_key, L"UninstallString");
            if (uninstall.empty()) uninstall = ReadRegistryString(app_key, L"QuietUninstallString");
            const std::wstring display_icon = UnquoteDisplayIcon(ReadRegistryString(app_key, L"DisplayIcon"));

            UnifiedAppV16 app{};
            app.name = display_name;
            app.launch_target = display_icon;
            app.source = source_label;
            app.uninstall_command = uninstall;
            app.platform = UnifiedAppPlatformV16::Windows;
            app.can_launch = !display_icon.empty() &&
                GetFileAttributesW(display_icon.c_str()) != INVALID_FILE_ATTRIBUTES;
            app.can_uninstall = !uninstall.empty();
            apps->push_back(std::move(app));
        }
        RegCloseKey(app_key);
    }
    RegCloseKey(parent);
}

std::wstring QuoteWindowsArgument(const std::wstring& value)
{
    if (value.empty()) return L"\"\"";
    if (value.find_first_of(L" \t\n\v\"") == std::wstring::npos) return value;

    std::wstring result = L"\"";
    std::size_t backslashes = 0;
    for (wchar_t ch : value)
    {
        if (ch == L'\\')
        {
            ++backslashes;
            continue;
        }
        if (ch == L'\"')
        {
            result.append(backslashes * 2u + 1u, L'\\');
            result.push_back(L'\"');
            backslashes = 0;
            continue;
        }
        result.append(backslashes, L'\\');
        backslashes = 0;
        result.push_back(ch);
    }
    result.append(backslashes * 2u, L'\\');
    result.push_back(L'\"');
    return result;
}

bool RunAndCapture(std::wstring command_line, std::vector<std::uint8_t>* bytes)
{
    if (command_line.empty() || bytes == nullptr) return false;
    bytes->clear();

    SECURITY_ATTRIBUTES security{};
    security.nLength = sizeof(security);
    security.bInheritHandle = TRUE;
    HANDLE read_pipe = nullptr;
    HANDLE write_pipe = nullptr;
    if (!CreatePipe(&read_pipe, &write_pipe, &security, 0)) return false;
    (void)SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startup.hStdOutput = write_pipe;
    startup.hStdError = write_pipe;
    PROCESS_INFORMATION process{};

    std::vector<wchar_t> mutable_command(command_line.begin(), command_line.end());
    mutable_command.push_back(L'\0');
    const BOOL created = CreateProcessW(
        nullptr,
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

    std::array<std::uint8_t, 4096> buffer{};
    for (;;)
    {
        DWORD read = 0;
        if (!ReadFile(read_pipe, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr) || read == 0)
            break;
        bytes->insert(bytes->end(), buffer.begin(), buffer.begin() + read);
        if (bytes->size() > 4u * 1024u * 1024u) break;
    }

    (void)WaitForSingleObject(process.hProcess, 10000);
    DWORD exit_code = 1;
    (void)GetExitCodeProcess(process.hProcess, &exit_code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    CloseHandle(read_pipe);
    return exit_code == 0;
}

std::wstring DecodeCapturedText(const std::vector<std::uint8_t>& bytes)
{
    if (bytes.empty()) return {};

    std::size_t zero_odd = 0;
    for (std::size_t index = 1; index < bytes.size(); index += 2)
        if (bytes[index] == 0) ++zero_odd;
    const bool utf16 =
        (bytes.size() >= 2u && bytes[0] == 0xFFu && bytes[1] == 0xFEu) ||
        (bytes.size() >= 8u && zero_odd * 3u > bytes.size() / 2u);
    if (utf16)
    {
        const std::size_t start = bytes.size() >= 2u && bytes[0] == 0xFFu && bytes[1] == 0xFEu ? 2u : 0u;
        std::wstring result;
        result.reserve((bytes.size() - start) / 2u);
        for (std::size_t index = start; index + 1u < bytes.size(); index += 2u)
        {
            const wchar_t ch = static_cast<wchar_t>(
                static_cast<unsigned int>(bytes[index]) |
                (static_cast<unsigned int>(bytes[index + 1u]) << 8u));
            if (ch != L'\0') result.push_back(ch);
        }
        return result;
    }

    const auto convert = [&](UINT code_page) -> std::wstring
    {
        const int count = MultiByteToWideChar(
            code_page,
            code_page == CP_UTF8 ? MB_ERR_INVALID_CHARS : 0,
            reinterpret_cast<const char*>(bytes.data()),
            static_cast<int>(bytes.size()),
            nullptr,
            0);
        if (count <= 0) return {};
        std::wstring result(static_cast<std::size_t>(count), L'\0');
        if (MultiByteToWideChar(
                code_page,
                code_page == CP_UTF8 ? MB_ERR_INVALID_CHARS : 0,
                reinterpret_cast<const char*>(bytes.data()),
                static_cast<int>(bytes.size()),
                result.data(),
                count) <= 0)
            return {};
        return result;
    };
    std::wstring result = convert(CP_UTF8);
    if (result.empty()) result = convert(CP_ACP);
    return result;
}

std::wstring Utf8ToWide(std::string_view value)
{
    if (value.empty()) return {};
    const int count = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (count <= 0) return {};
    std::wstring result(static_cast<std::size_t>(count), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            count) <= 0)
        return {};
    return result;
}

struct DesktopEntryV16 final
{
    std::wstring name;
    std::wstring flatpak;
    std::wstring snap;
    bool hidden{};
    bool no_display{};
    bool application{true};
};

bool ParseDesktopEntry(const std::filesystem::path& path, DesktopEntryV16* entry)
{
    if (entry == nullptr) return false;
    std::error_code error;
    const auto size = std::filesystem::file_size(path, error);
    if (error || size == 0 || size > kMaximumDesktopFileBytes) return false;

    std::ifstream input(path, std::ios::binary);
    if (!input) return false;
    std::string line;
    bool in_desktop_entry = false;
    while (std::getline(input, line))
    {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (!line.empty() && line.front() == '[')
        {
            in_desktop_entry = line == "[Desktop Entry]";
            continue;
        }
        if (!in_desktop_entry) continue;

        const std::size_t equals = line.find('=');
        if (equals == std::string::npos) continue;
        const std::string_view key(line.data(), equals);
        const std::string_view raw_value(line.data() + equals + 1u, line.size() - equals - 1u);
        if (key == "Name" && entry->name.empty()) entry->name = Utf8ToWide(raw_value);
        else if (key == "Type") entry->application = raw_value == "Application";
        else if (key == "Hidden") entry->hidden = raw_value == "true" || raw_value == "1";
        else if (key == "NoDisplay") entry->no_display = raw_value == "true" || raw_value == "1";
        else if (key == "X-Flatpak") entry->flatpak = Utf8ToWide(raw_value);
        else if (key == "X-SnapInstanceName") entry->snap = Utf8ToWide(raw_value);
    }
    return entry->application && !entry->hidden && !entry->no_display && !entry->name.empty();
}

bool SafeLinuxPackageToken(std::wstring_view value)
{
    if (value.empty() || value.size() > 256u) return false;
    for (wchar_t ch : value)
    {
        const bool allowed =
            (ch >= L'a' && ch <= L'z') ||
            (ch >= L'A' && ch <= L'Z') ||
            (ch >= L'0' && ch <= L'9') ||
            ch == L'.' || ch == L'+' || ch == L'-' || ch == L'_' || ch == L':' || ch == L'@';
        if (!allowed) return false;
    }
    return true;
}

std::wstring DesktopFileUnixPath(const UnifiedAppV16& app)
{
    if (app.desktop_id.empty()) return {};
    return L"/usr/share/applications/" + app.desktop_id + L".desktop";
}

std::wstring FirstOutputLine(std::wstring value)
{
    value = Trim(std::move(value));
    const std::size_t line = value.find_first_of(L"\r\n");
    if (line != std::wstring::npos) value.resize(line);
    return Trim(std::move(value));
}
} // namespace

std::vector<UnifiedAppV16> NativeIntegrationV16::EnumerateWindowsInstalledApps()
{
    std::vector<UnifiedAppV16> apps;
    EnumerateUninstallKey(HKEY_CURRENT_USER, 0, L"Windows · usuario", &apps);
    EnumerateUninstallKey(HKEY_LOCAL_MACHINE, KEY_WOW64_64KEY, L"Windows · sistema x64", &apps);
    EnumerateUninstallKey(HKEY_LOCAL_MACHINE, KEY_WOW64_32KEY, L"Windows · sistema x86", &apps);

    std::sort(apps.begin(), apps.end(), [](const UnifiedAppV16& left, const UnifiedAppV16& right)
    {
        const int name = _wcsicmp(left.name.c_str(), right.name.c_str());
        if (name != 0) return name < 0;
        return _wcsicmp(left.uninstall_command.c_str(), right.uninstall_command.c_str()) < 0;
    });
    apps.erase(std::unique(apps.begin(), apps.end(), [](const UnifiedAppV16& left, const UnifiedAppV16& right)
    {
        return _wcsicmp(left.name.c_str(), right.name.c_str()) == 0 &&
            _wcsicmp(left.uninstall_command.c_str(), right.uninstall_command.c_str()) == 0;
    }), apps.end());
    return apps;
}

std::vector<std::wstring> NativeIntegrationV16::EnumerateWslDistributions()
{
    const std::wstring wsl = WslExecutable();
    if (wsl.empty()) return {};
    std::vector<std::uint8_t> bytes;
    if (!RunAndCapture(QuoteWindowsArgument(wsl) + L" --list --quiet", &bytes)) return {};

    const std::wstring output = DecodeCapturedText(bytes);
    std::vector<std::wstring> distros;
    std::size_t begin = 0;
    while (begin <= output.size())
    {
        const std::size_t end = output.find_first_of(L"\r\n", begin);
        std::wstring name = Trim(output.substr(begin, end == std::wstring::npos ? std::wstring::npos : end - begin));
        if (!name.empty() && std::find_if(distros.begin(), distros.end(), [&](const std::wstring& existing)
            { return _wcsicmp(existing.c_str(), name.c_str()) == 0; }) == distros.end())
            distros.push_back(std::move(name));
        if (end == std::wstring::npos) break;
        begin = end + 1u;
        while (begin < output.size() && (output[begin] == L'\r' || output[begin] == L'\n')) ++begin;
    }
    return distros;
}

std::vector<UnifiedAppV16> NativeIntegrationV16::EnumerateLinuxGuiApps()
{
    std::vector<UnifiedAppV16> apps;
    for (const std::wstring& distro : EnumerateWslDistributions())
    {
        const std::wstring directory = WslRoot() + L"\\" + distro + L"\\usr\\share\\applications";
        const std::wstring pattern = directory + L"\\*.desktop";
        WIN32_FIND_DATAW data{};
        HANDLE find = FindFirstFileW(pattern.c_str(), &data);
        if (find == INVALID_HANDLE_VALUE) continue;
        do
        {
            if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) continue;
            std::filesystem::path path = std::filesystem::path(directory) / data.cFileName;
            DesktopEntryV16 entry{};
            if (!ParseDesktopEntry(path, &entry)) continue;

            std::wstring desktop_id = data.cFileName;
            constexpr std::wstring_view extension = L".desktop";
            if (desktop_id.size() > extension.size() &&
                _wcsicmp(desktop_id.c_str() + desktop_id.size() - extension.size(), extension.data()) == 0)
                desktop_id.resize(desktop_id.size() - extension.size());

            UnifiedAppV16 app{};
            app.name = entry.name;
            app.launch_target = path.wstring();
            app.source = L"Linux · " + distro;
            app.distro = distro;
            app.desktop_id = desktop_id;
            app.platform = UnifiedAppPlatformV16::Linux;
            app.can_launch = true;
            app.can_uninstall = true;
            if (!entry.flatpak.empty())
            {
                app.package_manager = L"flatpak";
                app.package_id = entry.flatpak;
            }
            else if (!entry.snap.empty())
            {
                app.package_manager = L"snap";
                app.package_id = entry.snap;
            }
            apps.push_back(std::move(app));
        }
        while (FindNextFileW(find, &data));
        FindClose(find);
    }

    std::sort(apps.begin(), apps.end(), [](const UnifiedAppV16& left, const UnifiedAppV16& right)
    {
        const int name = _wcsicmp(left.name.c_str(), right.name.c_str());
        if (name != 0) return name < 0;
        return _wcsicmp(left.distro.c_str(), right.distro.c_str()) < 0;
    });
    apps.erase(std::unique(apps.begin(), apps.end(), [](const UnifiedAppV16& left, const UnifiedAppV16& right)
    {
        return _wcsicmp(left.distro.c_str(), right.distro.c_str()) == 0 &&
            _wcsicmp(left.desktop_id.c_str(), right.desktop_id.c_str()) == 0;
    }), apps.end());
    return apps;
}

bool NativeIntegrationV16::LaunchLinuxApp(HWND owner, const UnifiedAppV16& app)
{
    if (app.platform != UnifiedAppPlatformV16::Linux || app.distro.empty() || app.desktop_id.empty())
        return false;
    const std::wstring wsl = WslExecutable();
    if (wsl.empty()) return false;
    const std::wstring parameters =
        L"-d " + QuoteWindowsArgument(app.distro) +
        L" -- gtk-launch " + QuoteWindowsArgument(app.desktop_id);

    SHELLEXECUTEINFOW execution{};
    execution.cbSize = sizeof(execution);
    execution.fMask = SEE_MASK_FLAG_NO_UI | SEE_MASK_ASYNCOK;
    execution.hwnd = owner;
    execution.lpVerb = L"open";
    execution.lpFile = wsl.c_str();
    execution.lpParameters = parameters.c_str();
    execution.nShow = SW_SHOWNORMAL;
    return ShellExecuteExW(&execution) != FALSE;
}

bool NativeIntegrationV16::LaunchWindowsUninstaller(HWND owner, const UnifiedAppV16& app)
{
    if (app.platform != UnifiedAppPlatformV16::Windows || app.uninstall_command.empty()) return false;
    std::vector<wchar_t> command(app.uninstall_command.begin(), app.uninstall_command.end());
    command.push_back(L'\0');
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(
            nullptr,
            command.data(),
            nullptr,
            nullptr,
            FALSE,
            CREATE_NEW_PROCESS_GROUP,
            nullptr,
            nullptr,
            &startup,
            &process))
    {
        const HINSTANCE result = ShellExecuteW(owner, L"open", L"ms-settings:appsfeatures", nullptr, nullptr, SW_SHOWNORMAL);
        return reinterpret_cast<INT_PTR>(result) > 32;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return true;
}

bool NativeIntegrationV16::ResolveLinuxRemovalCommand(
    const UnifiedAppV16& app,
    std::wstring* command_line,
    std::wstring* package_label)
{
    if (command_line == nullptr || package_label == nullptr ||
        app.platform != UnifiedAppPlatformV16::Linux || app.distro.empty())
        return false;

    std::wstring manager = app.package_manager;
    std::wstring package = app.package_id;
    if (manager.empty() || package.empty())
    {
        const std::wstring wsl = WslExecutable();
        const std::wstring unix_path = DesktopFileUnixPath(app);
        if (wsl.empty() || unix_path.empty()) return false;
        std::vector<std::uint8_t> bytes;
        const std::wstring query =
            QuoteWindowsArgument(wsl) + L" -d " + QuoteWindowsArgument(app.distro) +
            L" -- dpkg-query -S " + QuoteWindowsArgument(unix_path);
        if (!RunAndCapture(query, &bytes)) return false;
        std::wstring first = FirstOutputLine(DecodeCapturedText(bytes));
        const std::size_t colon = first.find(L": ");
        if (colon == std::wstring::npos) return false;
        package = Trim(first.substr(0, colon));
        manager = L"apt";
    }
    if (!SafeLinuxPackageToken(package)) return false;

    const std::wstring wsl = WslExecutable();
    if (wsl.empty()) return false;
    if (_wcsicmp(manager.c_str(), L"flatpak") == 0)
    {
        *command_line = QuoteWindowsArgument(wsl) + L" -d " + QuoteWindowsArgument(app.distro) +
            L" -- flatpak uninstall " + QuoteWindowsArgument(package);
    }
    else if (_wcsicmp(manager.c_str(), L"snap") == 0)
    {
        *command_line = QuoteWindowsArgument(wsl) + L" -d " + QuoteWindowsArgument(app.distro) +
            L" -- sudo snap remove " + QuoteWindowsArgument(package);
    }
    else
    {
        *command_line = QuoteWindowsArgument(wsl) + L" -d " + QuoteWindowsArgument(app.distro) +
            L" -- sudo apt remove " + QuoteWindowsArgument(package);
    }
    *package_label = manager + L":" + package;
    return true;
}

bool NativeIntegrationV16::IsWinGetAvailable()
{
    return !SearchExecutable(L"winget.exe").empty();
}

std::wstring NativeIntegrationV16::BuildWingetInstallCommand(const std::wstring& exact_name)
{
    const std::wstring winget = SearchExecutable(L"winget.exe");
    if (winget.empty() || exact_name.empty()) return {};
    return QuoteWindowsArgument(winget) + L" install --name " + QuoteWindowsArgument(exact_name) +
        L" --exact --accept-package-agreements --accept-source-agreements";
}

std::wstring NativeIntegrationV16::BuildWingetUninstallCommand(const std::wstring& exact_name)
{
    const std::wstring winget = SearchExecutable(L"winget.exe");
    if (winget.empty() || exact_name.empty()) return {};
    return QuoteWindowsArgument(winget) + L" uninstall --name " + QuoteWindowsArgument(exact_name) + L" --exact";
}

std::wstring NativeIntegrationV16::BuildLinuxInstallCommand(
    const std::wstring& distro,
    const std::wstring& package_name)
{
    const std::wstring wsl = WslExecutable();
    if (wsl.empty() || distro.empty() || !SafeLinuxPackageToken(package_name)) return {};
    return QuoteWindowsArgument(wsl) + L" -d " + QuoteWindowsArgument(distro) +
        L" -- sudo apt install " + QuoteWindowsArgument(package_name);
}

std::wstring NativeIntegrationV16::DownloadsFolder() { return KnownFolder(FOLDERID_Downloads); }
std::wstring NativeIntegrationV16::DesktopFolder() { return KnownFolder(FOLDERID_Desktop); }
std::wstring NativeIntegrationV16::PublicDesktopFolder() { return KnownFolder(FOLDERID_PublicDesktop); }
std::wstring NativeIntegrationV16::DocumentsFolder() { return KnownFolder(FOLDERID_Documents); }
std::wstring NativeIntegrationV16::WslRoot() { return L"\\\\wsl.localhost"; }
std::wstring NativeIntegrationV16::WslExecutable() { return SearchExecutable(L"wsl.exe"); }
} // namespace CloudOS
