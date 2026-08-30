#pragma once

#include <windows.h>
#include <dwmapi.h>

#include <array>
#include <string>
#include <vector>

class CloudOSNativeWindowManager;

namespace CloudOS
{
class CloudOSNativeWorkspaceOverviewWindow final
{
public:
    CloudOSNativeWorkspaceOverviewWindow() = default;
    ~CloudOSNativeWorkspaceOverviewWindow();

    CloudOSNativeWorkspaceOverviewWindow(const CloudOSNativeWorkspaceOverviewWindow&) = delete;
    CloudOSNativeWorkspaceOverviewWindow& operator=(const CloudOSNativeWorkspaceOverviewWindow&) = delete;

    bool Create(HINSTANCE instance, CloudOSNativeWindowManager* window_manager);
    void Destroy() noexcept;
    void Show(HWND owner = nullptr);
    void Toggle(HWND owner = nullptr);
    void Hide() noexcept;
    void Refresh();

    [[nodiscard]] HWND Hwnd() const noexcept { return window_; }
    [[nodiscard]] bool Visible() const noexcept;

private:
    struct WindowRow final
    {
        HWND hwnd{};
        DWORD process_id{};
        int workspace{};
        bool floating{};
        bool hidden_by_workspace{};
        std::wstring title;
    };

    void Layout();
    void Paint();
    void RefreshRows(bool preserve_selection = true);
    void RefreshStatus();
    void RefreshWorkspaceCards();
    void RebuildPreview();
    void LayoutPreview();
    void ClearPreview() noexcept;
    void SelectWindow(HWND window);
    [[nodiscard]] HWND SelectedWindow() const noexcept;
    [[nodiscard]] int SelectedRowIndex() const noexcept;
    [[nodiscard]] const WindowRow* SelectedRow() const noexcept;
    [[nodiscard]] int HitWorkspaceCard(POINT point) const noexcept;

    void SwitchWorkspace(int workspace, bool hide_after = false);
    void CycleWorkspace(int direction);
    void MoveSelectedToWorkspace(int workspace, bool follow);
    void MoveActiveToWorkspace(int workspace, bool follow);
    void FocusSelected(bool hide_after = true);
    void ToggleFloatingSelected();
    void MinimizeSelected();
    void MaximizeSelected();
    void CloseSelected();
    void ToggleTiling();
    void FocusSearch();
    void FocusList();
    void ShowSelectedContextMenu(POINT screen_point);

    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK SearchSubclass(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param,
        UINT_PTR subclass_id,
        DWORD_PTR reference_data);

    HINSTANCE instance_{};
    CloudOSNativeWindowManager* window_manager_{};
    HWND window_{};
    HWND search_edit_{};
    HWND list_{};
    HWND workspace_combo_{};
    HWND focus_button_{};
    HWND move_button_{};
    HWND floating_button_{};
    HWND minimize_button_{};
    HWND maximize_button_{};
    HWND close_button_{};
    HWND tiling_button_{};
    HWND status_label_{};

    HFONT font_{};
    HFONT small_font_{};
    HFONT title_font_{};
    HBRUSH background_{};
    HBRUSH edit_background_{};

    std::array<RECT, 4> workspace_cards_{};
    std::array<std::size_t, 4> workspace_counts_{};
    int hovered_workspace_{-1};
    bool tracking_mouse_{};
    std::vector<WindowRow> visible_rows_;

    HTHUMBNAIL thumbnail_{};
    HWND preview_source_{};
    RECT preview_rect_{};
};
} // namespace CloudOS
