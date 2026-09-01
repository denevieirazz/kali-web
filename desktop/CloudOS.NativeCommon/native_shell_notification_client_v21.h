#pragma once

#include "native_shell_notification_v21.h"

#include <Windows.h>

#include <atomic>
#include <cstring>
#include <string>

namespace CloudOS
{
class NativeShellNotificationClientV21 final
{
public:
    static bool Query(
        ShellNotificationV21::Snapshot* snapshot,
        std::string* error = nullptr) noexcept
    {
        if (snapshot == nullptr)
        {
            SetError(error, "Notification snapshot output is required");
            return false;
        }
        *snapshot = ShellNotificationV21::Snapshot{};
        snapshot->schema = 0;

        const std::wstring mapping_name = CreateMappingName();
        HANDLE mapping = CreateFileMappingW(
            INVALID_HANDLE_VALUE,
            nullptr,
            PAGE_READWRITE,
            0,
            static_cast<DWORD>(sizeof(ShellNotificationV21::Snapshot)),
            mapping_name.c_str());
        if (mapping == nullptr)
        {
            SetError(error, "Failed to create notification snapshot mapping");
            return false;
        }

        void* view = MapViewOfFile(
            mapping,
            FILE_MAP_READ | FILE_MAP_WRITE,
            0,
            0,
            sizeof(ShellNotificationV21::Snapshot));
        if (view == nullptr)
        {
            CloseHandle(mapping);
            SetError(error, "Failed to map notification snapshot memory");
            return false;
        }
        std::memset(view, 0, sizeof(ShellNotificationV21::Snapshot));

        ShellNotificationV21::Request request;
        request.action = ShellNotificationV21::Action::Query;
        if (wcsncpy_s(
                request.mapping_name,
                ShellNotificationV21::kMappingNameChars,
                mapping_name.c_str(),
                _TRUNCATE) != 0)
        {
            UnmapViewOfFile(view);
            CloseHandle(mapping);
            SetError(error, "Notification mapping name is too long");
            return false;
        }

        bool valid = false;
        if (SendRequest(request, error))
        {
            const auto* mapped = static_cast<const ShellNotificationV21::Snapshot*>(view);
            valid = mapped->schema == ShellNotificationV21::kSchema &&
                mapped->count <= ShellNotificationV21::kMaxItems &&
                mapped->unread_count <= mapped->count;
            if (valid)
            {
                *snapshot = *mapped;
            }
            else
            {
                SetError(error, "NativeShell returned an invalid notification snapshot");
            }
        }

        UnmapViewOfFile(view);
        CloseHandle(mapping);
        return valid;
    }

    static bool MarkAllRead(std::string* error = nullptr) noexcept
    {
        ShellNotificationV21::Request request;
        request.action = ShellNotificationV21::Action::MarkAllRead;
        return SendRequest(request, error);
    }

    static bool Dismiss(
        std::uint64_t notification_id,
        std::string* error = nullptr) noexcept
    {
        if (notification_id == 0)
        {
            SetError(error, "Notification id must be non-zero");
            return false;
        }
        ShellNotificationV21::Request request;
        request.action = ShellNotificationV21::Action::Dismiss;
        request.notification_id = notification_id;
        return SendRequest(request, error);
    }

    static bool Clear(std::string* error = nullptr) noexcept
    {
        ShellNotificationV21::Request request;
        request.action = ShellNotificationV21::Action::Clear;
        return SendRequest(request, error);
    }

private:
    static std::wstring CreateMappingName()
    {
        const auto sequence = ++sequence_;
        return std::wstring(ShellNotificationV21::kMappingPrefix) +
            std::to_wstring(GetCurrentProcessId()) + L"." +
            std::to_wstring(GetTickCount64()) + L"." +
            std::to_wstring(sequence);
    }

    [[nodiscard]] static HWND FindEndpoint() noexcept
    {
        return FindWindowExW(
            HWND_MESSAGE,
            nullptr,
            ShellNotificationV21::kWindowClass,
            nullptr);
    }

    static bool SendRequest(
        ShellNotificationV21::Request& request,
        std::string* error) noexcept
    {
        if (request.schema != ShellNotificationV21::kSchema ||
            !ShellNotificationV21::IsSupported(request.action))
        {
            SetError(error, "Unsupported NativeShell notification request");
            return false;
        }

        const HWND endpoint = FindEndpoint();
        if (endpoint == nullptr)
        {
            SetError(error, "CloudOS NativeShell notification endpoint is unavailable");
            return false;
        }

        COPYDATASTRUCT copy_data{};
        copy_data.dwData = static_cast<ULONG_PTR>(ShellNotificationV21::kCopyDataTag);
        copy_data.cbData = static_cast<DWORD>(sizeof(request));
        copy_data.lpData = &request;

        DWORD_PTR response = FALSE;
        const LRESULT delivered = SendMessageTimeoutW(
            endpoint,
            WM_COPYDATA,
            0,
            reinterpret_cast<LPARAM>(&copy_data),
            SMTO_ABORTIFHUNG | SMTO_BLOCK,
            1500,
            &response);
        if (delivered == 0 || response == FALSE)
        {
            SetError(error, "CloudOS NativeShell rejected or timed out the notification request");
            return false;
        }
        return true;
    }

    static void SetError(std::string* error, const char* message) noexcept
    {
        if (error != nullptr) *error = message;
    }

    inline static std::atomic_uint64_t sequence_{0};
};
} // namespace CloudOS
