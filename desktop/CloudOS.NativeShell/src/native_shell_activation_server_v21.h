#pragma once

#include "native_app_launcher.h"
#include "native_browser_window.h"
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
    [[nodiscard]] static const wchar_t* SurfaceClass(
        ShellActivationV21::App app) noexcept
    {
        switch (app)
        {
        case ShellActivationV21::App::Browser:
            return L"CloudOS.NativeShell.Browser.v1";
        case ShellActivationV21::App::Terminal:
            return L"CloudOS.Native.Terminal.v2";
        default:
            return nullptr;
        }
    }

    [[nodiscard]] static HWND FindOwnedSurface(
        ShellActivationV21::App app,
        HWND after = nullptr) noexcept
    {
        const wchar_t* class_name = SurfaceClass(app);
        if (class_name == nullptr)
        {
            return nullptr;
        }

        const DWORD current_process_id = GetCurrentProcessId();
        HWND candidate = after;
        while ((candidate = FindWindowExW(
                    nullptr,
                    candidate,
                    class_name,
                    nullptr)) != nullptr)
        {
            DWORD process_id = 0;
            GetWindowThreadProcessId(candidate, &process_id);
            if (process_id == current_process_id)
            {
                return candidate;
            }
        }
        return nullptr;
    }

    [[nodiscard]] static LRESULT HandleSurfaceRequest(
        const ShellActivationV21::SurfaceRequest& request) noexcept
    {
        using ShellActivationV21::SurfaceAction;
        using ShellActivationV21::SurfaceResult;

        if (request.schema != ShellActivationV21::kSchema ||
            !ShellActivationV21::IsSupported(request.app) ||
            !ShellActivationV21::IsSupported(request.action))
        {
            return static_cast<LRESULT>(SurfaceResult::Rejected);
        }

        HWND surface = FindOwnedSurface(request.app);
        if (request.action == SurfaceAction::Query)
        {
            return static_cast<LRESULT>(
                surface == nullptr ? SurfaceResult::NotRunning : SurfaceResult::Running);
        }

        if (surface == nullptr)
        {
            return static_cast<LRESULT>(SurfaceResult::NotRunning);
        }

        if (request.action == SurfaceAction::Focus)
        {
            if (IsIconic(surface))
            {
                ShowWindow(surface, SW_RESTORE);
            }
            else
            {
                ShowWindow(surface, SW_SHOW);
            }
            BringWindowToTop(surface);
            (void)SetForegroundWindow(surface);
            return static_cast<LRESULT>(SurfaceResult::Applied);
        }

        if (request.action == SurfaceAction::Close)
        {
            bool closed_any = false;
            while (surface != nullptr)
            {
                const HWND current = surface;
                surface = FindOwnedSurface(request.app, current);
                if (PostMessageW(current, WM_CLOSE, 0, 0))
                {
                    closed_any = true;
                }
            }
            return static_cast<LRESULT>(
                closed_any ? SurfaceResult::Applied : SurfaceResult::Rejected);
        }

        return static_cast<LRESULT>(SurfaceResult::Rejected);
    }

    [[nodiscard]] static LRESULT HandleActivationRequest(
        const ShellActivationV21::Request& request) noexcept
    {
        if (request.schema != ShellActivationV21::kSchema ||
            !ShellActivationV21::IsSupported(request.app))
        {
            return FALSE;
        }

        const HINSTANCE instance = GetModuleHandleW(nullptr);
        switch (request.app)
        {
        case ShellActivationV21::App::Browser:
            // Browser authority belongs to the NativeShell WebView2 surface.
            // Do not silently dispatch the user's default browser here.
            CloudOSNativeBrowserWindow::Open(instance);
            return TRUE;
        case ShellActivationV21::App::Terminal:
            NativeAppLauncher::LaunchById(instance, nullptr, L"terminal");
            return TRUE;
        default:
            return FALSE;
        }
    }

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
        if (copy_data == nullptr || copy_data->lpData == nullptr)
        {
            return FALSE;
        }

        // Requests are accepted only after the authoritative desktop exists.
        // This prevents cross-process requests from racing shell startup.
        if (FindWindowW(L"CloudOS.NativeShell.Desktop.v2", L"CloudOS Desktop") == nullptr)
        {
            return FALSE;
        }

        if (copy_data->dwData ==
                static_cast<ULONG_PTR>(ShellActivationV21::kCopyDataTag) &&
            copy_data->cbData == sizeof(ShellActivationV21::Request))
        {
            return HandleActivationRequest(
                *static_cast<const ShellActivationV21::Request*>(copy_data->lpData));
        }

        if (copy_data->dwData ==
                static_cast<ULONG_PTR>(ShellActivationV21::kSurfaceCopyDataTag) &&
            copy_data->cbData == sizeof(ShellActivationV21::SurfaceRequest))
        {
            return HandleSurfaceRequest(
                *static_cast<const ShellActivationV21::SurfaceRequest*>(copy_data->lpData));
        }

        return FALSE;
    }

    inline static HWND window_{};
};
} // namespace CloudOS