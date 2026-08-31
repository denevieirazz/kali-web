#pragma once

#include <Windows.h>

#include <string>
#include <vector>

namespace CloudOS
{
class CloudOSNativeFolderPickerV16 final
{
public:
    static bool Pick(
        HWND owner,
        const std::wstring& initial_directory,
        std::wstring* selected_directory);

    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

private:
    CloudOSNativeFolderPickerV16(HWND owner, std::wstring initial_directory);
    ~CloudOSNativeFolderPickerV16();

    bool Create();
    bool RunModal();
    void Layout();
    void Navigate(const std::wstring& directory);
    void NavigateFromAddress();
    void NavigateSelected();
    void NavigateParent();
    void Accept();
    void Close(bool accepted);
    void Populate();
    void ApplyFonts();

    LRESULT HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);

    HWND owner_{};
    HWND window_{};
    HWND address_edit_{};
    HWND go_button_{};
    HWND up_button_{};
    HWND downloads_button_{};
    HWND desktop_button_{};
    HWND documents_button_{};
    HWND linux_button_{};
    HWND list_{};
    HWND select_button_{};
    HWND cancel_button_{};
    HFONT body_font_{};
    HFONT title_font_{};
    std::wstring current_directory_;
    std::wstring selected_directory_;
    std::vector<std::wstring> visible_directories_;
    bool accepted_{};
};
} // namespace CloudOS
