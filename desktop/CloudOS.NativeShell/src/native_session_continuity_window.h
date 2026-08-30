#pragma once

#include <windows.h>

#include <array>

namespace CloudOS
{
class NativeSessionContinuityService;

class NativeSessionContinuityWindow final
{
public:
    NativeSessionContinuityWindow() = default;
    ~NativeSessionContinuityWindow();

    NativeSessionContinuityWindow(const NativeSessionContinuityWindow&) = delete;
    NativeSessionContinuityWindow& operator=(const NativeSessionContinuityWindow&) = delete;

    bool Create(HINSTANCE instance, NativeSessionContinuityService* service);
    void Destroy() noexcept;
    void Show(HWND owner = nullptr);
    void Hide();
    void Toggle(HWND owner = nullptr);
    void Refresh();
    [[nodiscard]] bool Visible() const noexcept;
    [[nodiscard]] HWND Hwnd() const noexcept { return window_; }

private:
    enum class Page
    {
        Session = 0,
        Checkpoints = 1,
        Journal = 2,
        Preferences = 3,
    };

    void CreateControls();
    void Layout();
    void SetPage(Page page);
    void RefreshSession();
    void RefreshCheckpoints();
    void RefreshJournal();
    void RefreshPreferences();
    void RefreshHeader();
    void SavePreferences();
    void RestoreSelectedCheckpoint();
    void CaptureCurrentCheckpoint();
    void ClearCurrentPage();
    void FocusSelectedWindow();
    int SelectedRow() const;
    std::uint32_t SelectedCheckpointId() const;
    void Paint();
    void DrawOwnerButton(const DRAWITEMSTRUCT& item);

    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HWND window_{};
    HINSTANCE instance_{};
    NativeSessionContinuityService* service_{};
    Page page_{Page::Session};

    std::array<HWND, 4> nav_buttons_{};
    HWND title_label_{};
    HWND subtitle_label_{};
    HWND status_label_{};
    HWND list_{};
    HWND primary_button_{};
    HWND secondary_button_{};
    HWND clear_button_{};
    HWND enabled_check_{};
    HWND auto_checkpoint_check_{};
    HWND restore_unclean_check_{};
    HWND restore_workspace_check_{};
    HWND focus_history_check_{};
    HWND interval_edit_{};
    HWND retention_edit_{};
    HWND interval_label_{};
    HWND retention_label_{};

    HFONT font_{};
    HFONT small_font_{};
    HFONT title_font_{};
    HBRUSH background_{};
};
} // namespace CloudOS
