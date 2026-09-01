#pragma once

#include "native_app_launcher.h"
#include "../../CloudOS.NativeCommon/native_shell_activation_v21.h"

#include <windows.h>

namespace CloudOS
{
class NativeShellActivationServerV21 final
{
public:
    static bool Start(HINSTANCE instance) noexcept
    {
        if (window_ != nullptr && IsWindow(window_))
        {
            return true;
        }

        WNDCLASSEXW window_class{};
        window_class.cbSize = sizeof(window_class);
        window_class.lpfnWndProc = &NativeShellActivationServerV21::WindowProcedure;
        window_class.hInstance = instance;
        window_class.lpszClassName = ShellActivationV21::kWindowClass;

        if (RegisterClassExW(&window_class) == 0 &&
            GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        {
            return false;
        }

        window_ = CreateWindowExW(
            0,
            ShellActivationV21::kWindowClass,
            L"",
            0,
            0,
            0,
            0,
            0,
            HWND_MESSAGE,
            nullptr,
            instance,
            nullptr);
        return window_ != nullptr;
    }

    [[nodiscard]] static HWND Window() noexcept
    {
        return window_;
    }

private:
    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param) noexcept
    {
        if (message != WM_COPYDATA)
        {
            return DefWindowProcW(window, message, w_param, l_param);
        }

        const auto* copy_data = reinterpret_cast<const COPYDATASTRUCT*>(l_param);
        if (copy_data == nullptr ||
            copy_data->dwData != static_cast<ULONG_PTR>(ShellActivationV21::kCopyDataTag) ||
            copy_data->cbData != sizeof(ShellActivationV21::Request) ||
            copy_data->lpData == nullptr)
        {
            return FALSE;
        }

        const auto* request =
            static_cast<const ShellActivationV21::Request*>(copy_data->lpData);
        if (request->schema != ShellActivationV21::kSchema ||
            !ShellActivationV21::IsSupported(request->app))
        {
            return FALSE;
        }

        // Activation is accepted only after the authoritative desktop exists.
        // This prevents an early cross-process request from racing shell startup.
        if (FindWindowW(L"CloudOS.NativeShell.Desktop.v2", L"CloudOS Desktop") == nullptr)
        {
            return FALSE;
        }

        const HINSTANCE instance = GetModuleHandleW(nullptr);
        switch (request->app)
        {
        case ShellActivationV21::App::Browser:
            NativeAppLauncher::LaunchById(instance, nullptr, L"browser");
            return TRUE;
        case ShellActivationV21::App::Terminal:
            NativeAppLauncher::LaunchById(instance, nullptr, L"terminal");
            return TRUE;
        default:
            return FALSE;
        }
    }

    inline static HWND window_{};
};
} // namespace CloudOS
