#pragma once

#include <windows.h>
#include <functional>
#include <vector>
#include <array>
#include <string>
#include "native_theme.h"

namespace CloudOS
{
class CloudOSNativeStartMenuWindow final
{
public:
    using AppSelectedCallback = std::function<void(const AppItem&)>;
    using ActionCallback = std::function<void()>;

    CloudOSNativeStartMenuWindow() = default;
    ~CloudOSNativeStartMenuWindow();

    bool Create(HINSTANCE instance, HWND parent_taskbar);
    void Destroy();

    void Show(int x, int y);
    void Hide();
    void Toggle(int x, int y);
    bool IsVisible() const;

    void SetAppCallback(AppSelectedCallback callback) { on_app_selected_ = std::move(callback); }
    void SetSettingsCallback(ActionCallback callback) { on_settings_ = std::move(callback); }
    void SetShutdownCallback(ActionCallback callback) { on_shutdown_ = std::move(callback); }

    HWND Hwnd() const noexcept { return hwnd_; }

private:
    void Paint();
    void OnSearchChanged();
    void SelectActiveCard();
    void MoveFocus(int delta_x, int delta_y);
    std::vector<int> GetFilteredAppIndices() const;

    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK SearchSubclass(HWND window, UINT message, WPARAM w_param, LPARAM l_param, UINT_PTR uIdSubclass, DWORD_PTR dwRefData);

    HWND hwnd_{};
    HWND search_edit_{};
    HFONT edit_font_{nullptr};
    HBRUSH edit_bg_brush_{nullptr};
    HINSTANCE instance_{};
    AppCategory active_category_{AppCategory::All};

    std::wstring search_query_;
    int focused_card_index_{0};
    int hovered_card_index_{-1};
    int hovered_category_index_{-1};
    int hovered_action_btn_{-1}; // 0: Shutdown, 1: Restart, 2: Lock, 3: Settings
    bool tracking_mouse_{false};

    RECT power_btn_rect_{};
    RECT restart_btn_rect_{};
    RECT lock_btn_rect_{};
    RECT settings_btn_rect_{};
    RECT user_profile_rect_{};
    std::array<RECT, 6> category_rects_{};
    std::vector<RECT> app_grid_rects_;
    std::vector<int> current_visible_indices_;

    AppSelectedCallback on_app_selected_;
    ActionCallback on_settings_;
    ActionCallback on_shutdown_;
};
} // namespace CloudOS
