#pragma once

#include <Windows.h>

class CloudOSNativeWindowManager;

namespace CloudOS
{
class NativeTaskbarHoverPreview final
{
public:
    static bool Attach(
        HINSTANCE instance,
        HWND taskbar,
        HMONITOR monitor,
        CloudOSNativeWindowManager* window_manager);

private:
    NativeTaskbarHoverPreview(
        HINSTANCE instance,
        HWND taskbar,
        HMONITOR monitor,
        CloudOSNativeWindowManager* window_manager) noexcept;
    ~NativeTaskbarHoverPreview();

    NativeTaskbarHoverPreview(const NativeTaskbarHoverPreview&) = delete;
    NativeTaskbarHoverPreview& operator=(const NativeTaskbarHoverPreview&) = delete;

    bool Initialize();
    void Detach() noexcept;
    void UpdateHover(POINT client_point);
    HWND HitTaskWindow(POINT client_point, RECT* task_rect) const;
    void ShowPreview(HWND source, const RECT& task_rect);
    void HidePreview() noexcept;
    void LayoutThumbnail();
    void PaintPreview();

    static LRESULT CALLBACK TaskbarSubclass(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param,
        UINT_PTR subclass_id,
        DWORD_PTR reference_data);
    static LRESULT CALLBACK PreviewProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND taskbar_{};
    HMONITOR monitor_{};
    CloudOSNativeWindowManager* window_manager_{};
    HWND preview_{};
    HTHUMBNAIL thumbnail_{};
    HWND source_{};
    RECT source_task_rect_{};
    RECT close_rect_{};
    HWND pending_source_{};
    RECT pending_task_rect_{};
    bool tracking_taskbar_{};
    bool tracking_preview_{};
};
} // namespace CloudOS
