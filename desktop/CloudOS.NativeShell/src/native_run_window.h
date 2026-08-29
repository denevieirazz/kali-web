#pragma once

#include <Windows.h>

class CloudOSNativeRunWindow final {
public:
    static void Open(HINSTANCE instance);

    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

private:
    explicit CloudOSNativeRunWindow(HINSTANCE instance);
    ~CloudOSNativeRunWindow() = default;

    CloudOSNativeRunWindow(const CloudOSNativeRunWindow&) = delete;
    CloudOSNativeRunWindow& operator=(const CloudOSNativeRunWindow&) = delete;

    bool Create();
    void Launch();
    void Layout();
    LRESULT HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND edit_{};
    HWND launch_button_{};
    HWND cancel_button_{};
};
