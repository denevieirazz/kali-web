#pragma once

#include "native_integration_v16.h"

#include <Shellapi.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace CloudOS
{
namespace IntegrationV16FilesDetail
{
inline std::wstring Trim(std::wstring value)
{
    const auto whitespace = [](wchar_t ch)
    {
        return ch == L' ' || ch == L'\t' || ch == L'\r' || ch == L'\n' || ch == L'\0';
    };
    while (!value.empty() && whitespace(value.front())) value.erase(value.begin());
    while (!value.empty() && whitespace(value.back())) value.pop_back();
    return value;
}

inline std::wstring QuoteWindowsArgument(const std::wstring& value)
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

inline bool RunAndCapture(std::wstring command_line, std::vector<std::uint8_t>* bytes)
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
        if (bytes->size() > 1024u * 1024u) break;
    }

    const DWORD wait = WaitForSingleObject(process.hProcess, 10000);
    DWORD exit_code = 1;
    if (wait == WAIT_OBJECT_0) (void)GetExitCodeProcess(process.hProcess, &exit_code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    CloseHandle(read_pipe);
    return wait == WAIT_OBJECT_0 && exit_code == 0;
}

inline std::wstring DecodeOutput(const std::vector<std::uint8_t>& bytes)
{
    if (bytes.empty()) return {};
    const auto convert = [&](UINT code_page, DWORD flags) -> std::wstring
    {
        const int count = MultiByteToWideChar(
            code_page,
            flags,
            reinterpret_cast<const char*>(bytes.data()),
            static_cast<int>(bytes.size()),
            nullptr,
            0);
        if (count <= 0) return {};
        std::wstring value(static_cast<std::size_t>(count), L'\0');
        if (MultiByteToWideChar(
                code_page,
                flags,
                reinterpret_cast<const char*>(bytes.data()),
                static_cast<int>(bytes.size()),
                value.data(),
                count) <= 0)
            return {};
        return value;
    };
    std::wstring value = convert(CP_UTF8, MB_ERR_INVALID_CHARS);
    if (value.empty()) value = convert(CP_ACP, 0);
    return Trim(std::move(value));
}

inline bool StartsWithInsensitive(std::wstring_view value, std::wstring_view prefix)
{
    if (value.size() < prefix.size()) return false;
    return _wcsnicmp(value.data(), prefix.data(), prefix.size()) == 0;
}

inline bool MapWslUnc(
    const std::wstring& distro,
    const std::wstring& windows_path,
    std::wstring* linux_path)
{
    if (linux_path == nullptr) return false;
    constexpr std::wstring_view local_prefix = L"\\\\wsl.localhost\\";
    constexpr std::wstring_view legacy_prefix = L"\\\\wsl$\\";
    std::size_t prefix_size = 0;
    if (StartsWithInsensitive(windows_path, local_prefix)) prefix_size = local_prefix.size();
    else if (StartsWithInsensitive(windows_path, legacy_prefix)) prefix_size = legacy_prefix.size();
    else return false;

    const std::size_t slash = windows_path.find_first_of(L"\\/", prefix_size);
    const std::wstring path_distro = windows_path.substr(
        prefix_size,
        slash == std::wstring::npos ? std::wstring::npos : slash - prefix_size);
    if (path_distro.empty() || _wcsicmp(path_distro.c_str(), distro.c_str()) != 0) return false;

    if (slash == std::wstring::npos)
    {
        *linux_path = L"/";
        return true;
    }
    std::wstring mapped = windows_path.substr(slash);
    std::replace(mapped.begin(), mapped.end(), L'\\', L'/');
    if (mapped.empty() || mapped.front() != L'/') mapped.insert(mapped.begin(), L'/');
    *linux_path = std::move(mapped);
    return true;
}

inline std::string WideToUtf8(std::wstring_view value)
{
    if (value.empty()) return {};
    const int count = WideCharToMultiByte(
        CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (count <= 0) return {};
    std::string bytes(static_cast<std::size_t>(count), '\0');
    if (WideCharToMultiByte(
            CP_UTF8, 0, value.data(), static_cast<int>(value.size()), bytes.data(), count, nullptr, nullptr) <= 0)
        return {};
    return bytes;
}

inline std::wstring FileUri(const std::wstring& linux_path)
{
    const std::string utf8 = WideToUtf8(linux_path);
    if (utf8.empty()) return {};
    static constexpr wchar_t hex[] = L"0123456789ABCDEF";
    std::wstring encoded;
    encoded.reserve(utf8.size() + 16u);
    for (unsigned char byte : utf8)
    {
        const bool safe =
            (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') ||
            (byte >= '0' && byte <= '9') || byte == '-' || byte == '.' ||
            byte == '_' || byte == '~' || byte == '/' || byte == ':';
        if (safe)
        {
            encoded.push_back(static_cast<wchar_t>(byte));
        }
        else
        {
            encoded.push_back(L'%');
            encoded.push_back(hex[(byte >> 4u) & 0x0Fu]);
            encoded.push_back(hex[byte & 0x0Fu]);
        }
    }
    return L"file://" + encoded;
}
} // namespace IntegrationV16FilesDetail

inline bool NativeIntegrationV16::TryMapWindowsPathToLinux(
    const UnifiedAppV16& app,
    const std::wstring& windows_path,
    std::wstring* linux_path)
{
    if (linux_path == nullptr || windows_path.empty() ||
        app.platform != UnifiedAppPlatformV16::Linux || app.distro.empty())
        return false;
    linux_path->clear();

    if (IntegrationV16FilesDetail::MapWslUnc(app.distro, windows_path, linux_path))
        return true;

    if (IntegrationV16FilesDetail::StartsWithInsensitive(windows_path, L"\\\\wsl.localhost\\") ||
        IntegrationV16FilesDetail::StartsWithInsensitive(windows_path, L"\\\\wsl$\\"))
    {
        // Cross-distro UNC paths are deliberately refused. A path inside distro A
        // must not be silently reinterpreted as a local path inside distro B.
        return false;
    }

    const std::wstring wsl = WslExecutable();
    if (wsl.empty()) return false;
    std::vector<std::uint8_t> bytes;
    const std::wstring command =
        IntegrationV16FilesDetail::QuoteWindowsArgument(wsl) +
        L" -d " + IntegrationV16FilesDetail::QuoteWindowsArgument(app.distro) +
        L" -- wslpath -a -u " + IntegrationV16FilesDetail::QuoteWindowsArgument(windows_path);
    if (!IntegrationV16FilesDetail::RunAndCapture(command, &bytes)) return false;

    std::wstring mapped = IntegrationV16FilesDetail::DecodeOutput(bytes);
    const std::size_t line = mapped.find_first_of(L"\r\n");
    if (line != std::wstring::npos) mapped.resize(line);
    mapped = IntegrationV16FilesDetail::Trim(std::move(mapped));
    if (mapped.empty() || mapped.front() != L'/') return false;
    *linux_path = std::move(mapped);
    return true;
}

inline bool NativeIntegrationV16::LaunchLinuxAppWithPath(
    HWND owner,
    const UnifiedAppV16& app,
    const std::wstring& windows_path)
{
    if (app.platform != UnifiedAppPlatformV16::Linux || app.distro.empty() || app.desktop_id.empty())
        return false;

    std::wstring linux_path;
    if (!TryMapWindowsPathToLinux(app, windows_path, &linux_path)) return false;
    const std::wstring uri = IntegrationV16FilesDetail::FileUri(linux_path);
    const std::wstring wsl = WslExecutable();
    if (uri.empty() || wsl.empty()) return false;

    const std::wstring parameters =
        L"-d " + IntegrationV16FilesDetail::QuoteWindowsArgument(app.distro) +
        L" -- gtk-launch " + IntegrationV16FilesDetail::QuoteWindowsArgument(app.desktop_id) +
        L" " + IntegrationV16FilesDetail::QuoteWindowsArgument(uri);

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
} // namespace CloudOS
