#pragma once

#include <windows.h>
#include <commctrl.h>

#include <string>
#include <string_view>
#include <vector>

#include "native_shell_pins.h"
#include "native_flyout_layout.h"
#include "native_start_index.h"

namespace Gdiplus
{
class Graphics;
}

namespace CloudOS
{
class NativeSurfacePreview;
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
    friend class NativeSurfacePreview;
    enum class ResultKind
    {
        CloudOSApp,
        IndexedWindowsApp,
    };

    enum class ViewMode
    {
        Home,
        AllApps,
        Search,
    };

    struct ResultRow final
    {
        ResultKind kind{ResultKind::CloudOSApp};
        int cloud_app_index{-1};
        NativeStartIndexEntry indexed;
    };

    struct HomeHit final
    {
        RECT rect{};
        ShellPinItem pin;
        bool recommended{};
    };

    NativeScrollState home_scroll_v12_;
    bool HomePointVisibleV12(POINT point) const;
    void Layout();
    void Paint();
    void PaintHome(HDC dc, Gdiplus::Graphics& graphics, UINT dpi, int width, int height);
    void RefreshResults();
    void RefreshHome();
    void UpdateViewVisibility();
    void ExecuteSelection();
    void ExecutePin(const ShellPinItem& pin);
    void MoveSelection(int delta);
    void EnsureHomeSelectionVisibleV12();
    void MoveHomeSelection(int horizontal, int vertical);
    void SelectHomeEdge(bool last);
    void ActivateHomeSelection();
    void ShowHomeSelectionContextMenu();
    void RefreshIndexer();
    void RebuildRowHeight();
    void ToggleAllApps();
    void ShowResultContextMenu(int row, POINT screen_point);
    void ShowPinContextMenu(std::size_t hit_index, POINT screen_point);
    void OpenIndexedLocation(const NativeStartIndexEntry& entry);
    [[nodiscard]] ShellPinItem PinFromResult(const ResultRow& result) const;
    [[nodiscard]] int FindCloudApp(std::wstring_view id) const;
    [[nodiscard]] std::wstring PinTitle(const ShellPinItem& pin) const;
    [[nodiscard]] std::wstring PinSubtitle(const ShellPinItem& pin) const;
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

    std::vector<std::wstring> recommended_ids_v12_;
    HINSTANCE instance_{};
    HWND window_{};
    HWND search_edit_{};
    HWND app_list_{};
    HWND all_apps_button_{};
    HWND command_button_{};
    HWND power_button_{};
    HWND footer_label_{};
    HFONT font_{};
    HFONT small_font_{};
    HFONT title_font_{};
    UINT font_dpi_v12_{};
    HBRUSH background_{};
    HBRUSH edit_background_{};
    HIMAGELIST row_height_image_list_{};
    std::vector<ResultRow> results_;
    std::vector<ShellPinItem> start_pins_;
    std::vector<HomeHit> home_hits_;
    std::size_t last_index_count_{};
    ViewMode view_mode_{ViewMode::Home};
    int hovered_home_index_{-1};
    bool tracking_mouse_{};
    bool search_focused_{};
    bool keyboard_home_navigation_{};
};
} // namespace CloudOS
