#pragma once

#include <windows.h>
#include <dwmapi.h>

#include <vector>

#include "native_window_manager.h"

namespace CloudOS
{
class CloudOSNativeTaskSwitcherWindow final
{
public:
    CloudOSNativeTaskSwitcherWindow() = default;
    ~CloudOSNativeTaskSwitcherWindow();

    bool Create(HINSTANCE instance, CloudOSNativeWindowManager* window_manager);
    void Destroy();
    void ShowCycle(bool reverse = false);
    void Hide();
    void Commit();

private:
    void Rebuild();
    void LayoutThumbnails();
    void Paint();
    void Cycle(int delta);
    void ClearThumbnails() noexcept;
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    CloudOSNativeWindowManager* window_manager_{};
    HWND window_{};
    std::vector<CloudOSManagedWindow> windows_;
    std::vector<HTHUMBNAIL> thumbnails_;
    std::vector<RECT> cells_;
    int selected_{};
};
} // namespace CloudOS
