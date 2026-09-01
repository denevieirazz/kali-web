#pragma once

#include "native_notification_center.h"
#include "../../CloudOS.NativeCommon/native_shell_notification_v21.h"

#include <windows.h>

#include <algorithm>
#include <cwchar>
#include <vector>

namespace CloudOS
{
class NativeShellNotificationServerV21 final
{
public:
    static bool Start(HINSTANCE instance) noexcept
    {
        if (window_ != nullptr && IsWindow(window_)) return true;

        WNDCLASSEXW window_class{};
        window_class.cbSize = sizeof(window_class);
        window_class.lpfnWndProc = &NativeShellNotificationServerV21::WindowProcedure;
        window_class.hInstance = instance;
        window_class.lpszClassName = ShellNotificationV21::kWindowClass;
        if (RegisterClassExW(&window_class) == 0 &&
            GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        {
            return false;
        }

        window_ = CreateWindowExW(
            0,
            ShellNotificationV21::kWindowClass,
            L"",
            0,
            0,
            0,
            0,
            0,
            HWND_MESSAGE,
            nullptr,
            instance,
            nullptr);
        return window_ != nullptr;
    }

    static void Stop() noexcept
    {
        if (window_ != nullptr && IsWindow(window_)) DestroyWindow(window_);
        window_ = nullptr;
    }

private:
    static bool ValidMappingName(const wchar_t* name) noexcept
    {
        if (name == nullptr) return false;
        const std::size_t length = wcsnlen_s(
            name,
            ShellNotificationV21::kMappingNameChars);
        if (length == 0 || length >= ShellNotificationV21::kMappingNameChars)
        {
            return false;
        }
        const std::size_t prefix_length = wcslen(ShellNotificationV21::kMappingPrefix);
        return length > prefix_length &&
            wcsncmp(name, ShellNotificationV21::kMappingPrefix, prefix_length) == 0;
    }

    static bool FillSnapshot(const ShellNotificationV21::Request& request) noexcept
    {
        if (!ValidMappingName(request.mapping_name)) return false;

        HANDLE mapping = OpenFileMappingW(
            FILE_MAP_WRITE,
            FALSE,
            request.mapping_name);
        if (mapping == nullptr) return false;

        void* view = MapViewOfFile(
            mapping,
            FILE_MAP_WRITE,
            0,
            0,
            sizeof(ShellNotificationV21::Snapshot));
        if (view == nullptr)
        {
            CloseHandle(mapping);
            return false;
        }

        auto* snapshot = static_cast<ShellNotificationV21::Snapshot*>(view);
        *snapshot = ShellNotificationV21::Snapshot{};

        std::vector<NativeNotificationItemV12> items;
        std::size_t unread_count = 0;
        std::uint64_t revision = 0;
        CloudOSNativeNotificationCenter::Snapshot(
            &items,
            &unread_count,
            &revision);

        const std::size_t count = std::min(
            items.size(),
            ShellNotificationV21::kMaxItems);
        snapshot->schema = ShellNotificationV21::kSchema;
        snapshot->count = static_cast<std::uint32_t>(count);
        snapshot->unread_count = static_cast<std::uint32_t>(
            std::min(unread_count, count));
        snapshot->revision = revision;

        for (std::size_t index = 0; index < count; ++index)
        {
            const auto& source = items[index];
            auto& target = snapshot->items[index];
            target.id = source.id;
            target.year = source.time.wYear;
            target.month = source.time.wMonth;
            target.day = source.time.wDay;
            target.hour = source.time.wHour;
            target.minute = source.time.wMinute;
            target.second = source.time.wSecond;
            target.severity = source.severity;
            target.read = source.read ? 1u : 0u;
            wcsncpy_s(
                target.title,
                ShellNotificationV21::kTitleChars,
                source.title.c_str(),
                _TRUNCATE);
            wcsncpy_s(
                target.message,
                ShellNotificationV21::kMessageChars,
                source.message.c_str(),
                _TRUNCATE);
        }

        UnmapViewOfFile(view);
        CloseHandle(mapping);
        return true;
    }

    static LRESULT HandleRequest(
        const ShellNotificationV21::Request& request) noexcept
    {
        if (request.schema != ShellNotificationV21::kSchema ||
            !ShellNotificationV21::IsSupported(request.action))
        {
            return FALSE;
        }

        switch (request.action)
        {
        case ShellNotificationV21::Action::Query:
            return FillSnapshot(request) ? TRUE : FALSE;
        case ShellNotificationV21::Action::MarkAllRead:
            CloudOSNativeNotificationCenter::MarkAllRead();
            return TRUE;
        case ShellNotificationV21::Action::Dismiss:
            return CloudOSNativeNotificationCenter::Dismiss(request.notification_id)
                ? TRUE
                : FALSE;
        case ShellNotificationV21::Action::Clear:
            CloudOSNativeNotificationCenter::ClearAll();
            return TRUE;
        default:
            return FALSE;
        }
    }

    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param) noexcept
    {
        if (message == WM_NCDESTROY)
        {
            if (window == window_) window_ = nullptr;
            return DefWindowProcW(window, message, w_param, l_param);
        }
        if (message != WM_COPYDATA)
        {
            return DefWindowProcW(window, message, w_param, l_param);
        }

        const auto* copy_data = reinterpret_cast<const COPYDATASTRUCT*>(l_param);
        if (copy_data == nullptr || copy_data->lpData == nullptr ||
            copy_data->dwData != static_cast<ULONG_PTR>(ShellNotificationV21::kCopyDataTag) ||
            copy_data->cbData != sizeof(ShellNotificationV21::Request))
        {
            return FALSE;
        }
        return HandleRequest(
            *static_cast<const ShellNotificationV21::Request*>(copy_data->lpData));
    }

    inline static HWND window_{};
};
} // namespace CloudOS
