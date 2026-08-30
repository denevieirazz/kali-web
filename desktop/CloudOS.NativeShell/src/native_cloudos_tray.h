#pragma once

#include <windows.h>

namespace CloudOS
{
class NativeCloudOSTrayService final
{
public:
    static NativeCloudOSTrayService& Instance();

    bool Start(HINSTANCE instance);
    void Stop() noexcept;
    void Refresh();

private:
    NativeCloudOSTrayService() = default;
    ~NativeCloudOSTrayService() = default;
    NativeCloudOSTrayService(const NativeCloudOSTrayService&) = delete;
    NativeCloudOSTrayService& operator=(const NativeCloudOSTrayService&) = delete;

    void AttachExistingTaskbars();
    static BOOL CALLBACK EnumerateWindow(HWND window, LPARAM parameter);
    static LRESULT CALLBACK TaskbarSubclass(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param,
        UINT_PTR subclass_id,
        DWORD_PTR reference_data);
    LRESULT HandleTaskbar(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param,
        UINT_PTR subclass_id);
    static LRESULT CALLBACK EngineProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND engine_window_{};
};
} // namespace CloudOS
