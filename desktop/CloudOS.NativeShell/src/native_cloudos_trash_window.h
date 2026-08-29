#pragma once

#include <Windows.h>

#include <vector>

#include "native_cloudos_drive.h"

namespace CloudOS
{
class CloudOSNativeDriveTrashWindow final
{
public:
    static void Open(HINSTANCE instance);

    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

private:
    explicit CloudOSNativeDriveTrashWindow(HINSTANCE instance) noexcept;
    ~CloudOSNativeDriveTrashWindow() = default;

    CloudOSNativeDriveTrashWindow(const CloudOSNativeDriveTrashWindow&) = delete;
    CloudOSNativeDriveTrashWindow& operator=(const CloudOSNativeDriveTrashWindow&) = delete;

    bool Create();
    void Layout();
    void Refresh();
    void RestoreSelected();
    void DeleteSelected();
    void EmptyTrash();

    [[nodiscard]] int SelectedIndex() const;
    LRESULT HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND list_{};
    HWND restore_button_{};
    HWND delete_button_{};
    HWND empty_button_{};
    HWND refresh_button_{};

    std::vector<CloudOSDriveTrashEntry> entries_;
};

} // namespace CloudOS
