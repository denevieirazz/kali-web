#pragma once

#include <windows.h>

#include <cstddef>
#include <string>
#include <vector>

#include "native_shell_actions.h"

namespace CloudOS
{
class CloudOSNativeCommandCenterWindow final
{
public:
    static void Open(HINSTANCE instance, HWND owner = nullptr);

private:
    explicit CloudOSNativeCommandCenterWindow(HINSTANCE instance, HWND owner);
    ~CloudOSNativeCommandCenterWindow();

    bool Create();
    void Layout();
    void RefreshResults(bool preserve_selection = false);
    void ExecuteSelection();
    void UpdateStatus();
    std::wstring SearchText() const;
    ShellActionCategory SelectedCategory() const noexcept;
    void SelectFirstResult();

    LRESULT HandleMessage(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

    static LRESULT CALLBACK ChildSubclass(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param,
        UINT_PTR subclass_id,
        DWORD_PTR reference_data);

    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

    HINSTANCE instance_{};
    HWND owner_{};
    HWND window_{};
    HWND search_edit_{};
    HWND category_combo_{};
    HWND result_list_{};
    HWND execute_button_{};
    HWND status_label_{};
    HFONT ui_font_{};
    HBRUSH background_brush_{};
    HBRUSH edit_brush_{};

    std::vector<std::size_t> filtered_;
    bool auto_delete_{};
};
} // namespace CloudOS
