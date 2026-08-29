#pragma once

#include <Windows.h>

#include <string>
#include <vector>

#include "native_cloudos_drive.h"

namespace CloudOS
{
class CloudOSNativeProjectsWindow final
{
public:
    static void Open(HINSTANCE instance);

    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

private:
    explicit CloudOSNativeProjectsWindow(HINSTANCE instance) noexcept;
    ~CloudOSNativeProjectsWindow() = default;

    CloudOSNativeProjectsWindow(const CloudOSNativeProjectsWindow&) = delete;
    CloudOSNativeProjectsWindow& operator=(const CloudOSNativeProjectsWindow&) = delete;

    bool Create();
    void Layout();
    void Refresh();
    void CreateProject();
    void OpenSelectedFiles();
    void OpenSelectedTerminal();
    void OpenSelectedCode();
    void TrashSelected();
    void BeginRename();
    bool CommitRename(int row, const wchar_t* new_name);

    [[nodiscard]] int SelectedIndex() const;
    [[nodiscard]] std::wstring SelectedProjectName() const;
    [[nodiscard]] std::wstring SelectedProjectPath() const;

    LRESULT HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND list_{};
    HWND new_button_{};
    HWND files_button_{};
    HWND terminal_button_{};
    HWND code_button_{};
    HWND trash_button_{};
    HWND refresh_button_{};
    HWND root_label_{};

    std::vector<CloudOSDriveEntry> entries_;
};

} // namespace CloudOS
