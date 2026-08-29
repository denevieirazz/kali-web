#pragma once

#include <windows.h>

#include <vector>

namespace CloudOS
{
class CloudOSNativeStartMenuWindow final
{
public:
    CloudOSNativeStartMenuWindow() = default;
    ~CloudOSNativeStartMenuWindow();

    bool Create(HINSTANCE instance);
    void Destroy();
    void ToggleNear(const RECT& taskbar_bounds);
    void ShowNear(const RECT& taskbar_bounds);
    void Hide();
    void FocusSearch();

private:
    void Layout();
    void RefreshResults();
    void ExecuteSelection();
    void MoveSelection(int delta);
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK SearchSubclass(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param,
        UINT_PTR subclass_id,
        DWORD_PTR reference_data);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND search_edit_{};
    HWND app_list_{};
    HWND command_button_{};
    HWND power_button_{};
    HWND footer_label_{};
    HFONT font_{};
    HFONT title_font_{};
    HBRUSH background_{};
    HBRUSH edit_background_{};
    std::vector<int> results_;
};
} // namespace CloudOS
