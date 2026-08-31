#pragma once

#include <windows.h>

#include <cstddef>
#include <string>
#include <vector>
#include <commctrl.h>
#include <cstdint>

namespace CloudOS
{
struct NativeNotificationItemV12 { std::uint64_t id{}; SYSTEMTIME time{}; std::wstring title, message; int severity{}; bool read{}; };
class NativeSurfacePreview;
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
    friend class NativeSurfacePreview;
    std::vector<NativeNotificationItemV12> snapshot_v12_;
    std::uint64_t revision_v12_{~0ull};
    HIMAGELIST row_image_v12_{};
    HWND heading_v12_{};
    HFONT heading_font_v12_{};
    UINT dpi_v12_{};
    void OpenSelection();
    LRESULT DrawCard(NMLVCUSTOMDRAW* draw);
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
