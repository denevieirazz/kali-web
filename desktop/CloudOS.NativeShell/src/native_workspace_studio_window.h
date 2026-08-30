#pragma once

#include <windows.h>
#include <commctrl.h>

#include <array>
#include <string>
#include <vector>

namespace CloudOS
{
class NativeWorkspaceStudioService;

class NativeWorkspaceStudioWindow final
{
public:
    explicit NativeWorkspaceStudioWindow(NativeWorkspaceStudioService* service) noexcept;
    ~NativeWorkspaceStudioWindow();

    NativeWorkspaceStudioWindow(const NativeWorkspaceStudioWindow&) = delete;
    NativeWorkspaceStudioWindow& operator=(const NativeWorkspaceStudioWindow&) = delete;

    bool Create(HINSTANCE instance);
    void Show(HWND owner = nullptr);
    void Hide() noexcept;
    void Destroy() noexcept;
    void RefreshAll();
    [[nodiscard]] HWND Hwnd() const noexcept { return window_; }

private:
    enum class Page : int
    {
        Profiles = 0,
        Rules = 1,
        Layouts = 2,
        Startup = 3,
        Activity = 4,
    };

    void CreateControls();
    void Layout();
    void ShowPage(Page page);
    void RefreshWorkspaceCombos();
    void RefreshProfilePage();
    void RefreshRules();
    void RefreshLayouts();
    void RefreshStartup();
    void RefreshActivity();

    void SaveProfile();
    void ApplyProfileNow();
    void ChooseWallpaper();
    void AddRule();
    void DeleteRule();
    void ToggleRule();
    void ReapplyRules();
    void CaptureLayout();
    void RestoreLayout();
    void DeleteLayout();
    void ApplyLayoutPreset();
    void AddStartupEntry();
    void DeleteStartupEntry();
    void RunStartupNow();
    void FocusHistorySelection();
    void ClearHistory();

    [[nodiscard]] int SelectedWorkspace() const noexcept;
    [[nodiscard]] int SelectedListIndex(HWND list) const noexcept;
    [[nodiscard]] std::wstring ControlText(HWND control) const;
    void SetControlText(HWND control, const std::wstring& text);
    void SetStatus(const std::wstring& text);

    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    NativeWorkspaceStudioService* service_{};
    HINSTANCE instance_{};
    HWND window_{};
    HWND tabs_{};
    HWND workspace_combo_{};
    HWND status_{};

    std::array<HWND, 5> page_roots_{};

    HWND profile_name_{};
    HWND profile_wallpaper_{};
    HWND profile_layout_{};
    HWND profile_auto_tile_{};
    HWND profile_auto_launch_{};
    HWND profile_apply_wallpaper_{};

    HWND rules_list_{};
    HWND rule_field_{};
    HWND rule_mode_{};
    HWND rule_pattern_{};
    HWND rule_workspace_{};
    HWND rule_floating_{};
    HWND rule_maximize_{};

    HWND layouts_list_{};
    HWND layout_name_{};
    HWND layout_preset_{};

    HWND startup_list_{};
    HWND startup_type_{};
    HWND startup_target_{};
    HWND startup_arguments_{};
    HWND startup_workspace_{};

    HWND activity_list_{};

    HFONT font_{};
    HFONT title_font_{};
    Page current_page_{Page::Profiles};
};
} // namespace CloudOS
