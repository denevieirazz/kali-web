#pragma once

#include <windows.h>
#include <commctrl.h>

#include <vector>

#include "native_start_index.h"

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
    enum class ResultKind
    {
        CloudOSApp,
        IndexedWindowsApp,
    };

    struct ResultRow final
    {
        ResultKind kind{ResultKind::CloudOSApp};
        int cloud_app_index{-1};
        NativeStartIndexEntry indexed;
    };

    void Layout();
    void Paint();
    void RefreshResults();
    void ExecuteSelection();
    void MoveSelection(int delta);
    void RefreshIndexer();
    void RebuildRowHeight();
    LRESULT DrawOwnerButton(const DRAWITEMSTRUCT& item);
    LRESULT CustomDrawResults(const NMLVCUSTOMDRAW& draw);
    std::wstring ResultTitle(std::size_t index) const;
    std::wstring ResultSubtitle(std::size_t index) const;
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
    HWND refresh_button_{};
    HWND command_button_{};
    HWND power_button_{};
    HWND footer_label_{};
    HFONT font_{};
    HFONT small_font_{};
    HFONT title_font_{};
    HBRUSH background_{};
    HBRUSH edit_background_{};
    HIMAGELIST row_height_image_list_{};
    std::vector<ResultRow> results_;
    std::size_t last_index_count_{};
    bool search_focused_{};
};
} // namespace CloudOS
