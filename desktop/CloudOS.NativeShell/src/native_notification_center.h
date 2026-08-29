#pragma once

#include <windows.h>

#include <cstddef>
#include <string>

namespace CloudOS
{
class CloudOSNativeNotificationCenter final
{
public:
    CloudOSNativeNotificationCenter() = default;
    ~CloudOSNativeNotificationCenter();

    bool Create(HINSTANCE instance);
    void Destroy();
    void ToggleNear(const RECT& anchor);
    void ShowNear(const RECT& anchor);
    void Hide();
    void Refresh();

    static void Post(
        const std::wstring& title,
        const std::wstring& message,
        int severity = 0);
    static std::size_t UnreadCount();

private:
    void Layout();
    void RebuildList();
    void MarkAllRead();
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND list_{};
    HWND clear_button_{};
    HWND status_label_{};
    HFONT font_{};
    HBRUSH background_{};
};
} // namespace CloudOS
