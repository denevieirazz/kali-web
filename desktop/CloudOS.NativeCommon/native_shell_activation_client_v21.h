#pragma once

#include "native_shell_activation_v21.h"

#include <Windows.h>

#include <string>

namespace CloudOS
{
class NativeShellActivationClientV21 final
{
public:
    static bool Activate(ShellActivationV21::App app, std::string* error = nullptr) noexcept
    {
        if (!ShellActivationV21::IsSupported(app))
        {
            SetError(error, "Unsupported NativeShell activation target");
            return false;
        }

        const HWND activation_window = FindEndpoint();
        if (activation_window == nullptr)
        {
            SetError(error, "CloudOS NativeShell activation endpoint is unavailable");
            return false;
        }

        ShellActivationV21::Request request;
        request.app = app;
        const DWORD_PTR response = SendTypedRequest(
            activation_window,
            ShellActivationV21::kCopyDataTag,
            request,
            error);
        return response != FALSE;
    }

    static bool QueryRunning(
        ShellActivationV21::App app,
        bool* running,
        std::string* error = nullptr) noexcept
    {
        if (running == nullptr)
        {
            SetError(error, "Surface running output is required");
            return false;
        }
        *running = false;

        const auto result = SendSurfaceRequest(
            app,
            ShellActivationV21::SurfaceAction::Query,
            error);
        if (result == ShellActivationV21::SurfaceResult::Running)
        {
            *running = true;
            return true;
        }
        return result == ShellActivationV21::SurfaceResult::NotRunning;
    }

    static bool Focus(
        ShellActivationV21::App app,
        bool* running,
        std::string* error = nullptr) noexcept
    {
        if (running != nullptr) *running = false;
        const auto result = SendSurfaceRequest(
            app,
            ShellActivationV21::SurfaceAction::Focus,
            error);
        if (result == ShellActivationV21::SurfaceResult::Applied)
        {
            if (running != nullptr) *running = true;
            return true;
        }
        return result == ShellActivationV21::SurfaceResult::NotRunning;
    }

    static bool Close(
        ShellActivationV21::App app,
        bool* was_running,
        std::string* error = nullptr) noexcept
    {
        if (was_running != nullptr) *was_running = false;
        const auto result = SendSurfaceRequest(
            app,
            ShellActivationV21::SurfaceAction::Close,
            error);
        if (result == ShellActivationV21::SurfaceResult::Applied)
        {
            if (was_running != nullptr) *was_running = true;
            return true;
        }
        return result == ShellActivationV21::SurfaceResult::NotRunning;
    }

private:
    [[nodiscard]] static HWND FindEndpoint() noexcept
    {
        return FindWindowExW(
            HWND_MESSAGE,
            nullptr,
            ShellActivationV21::kWindowClass,
            nullptr);
    }

    template <typename RequestType>
    static DWORD_PTR SendTypedRequest(
        HWND activation_window,
        std::uintptr_t tag,
        RequestType& request,
        std::string* error) noexcept
    {
        COPYDATASTRUCT copy_data{};
        copy_data.dwData = static_cast<ULONG_PTR>(tag);
        copy_data.cbData = static_cast<DWORD>(sizeof(request));
        copy_data.lpData = &request;

        DWORD_PTR response = FALSE;
        const LRESULT delivered = SendMessageTimeoutW(
            activation_window,
            WM_COPYDATA,
            0,
            reinterpret_cast<LPARAM>(&copy_data),
            SMTO_ABORTIFHUNG | SMTO_BLOCK,
            1500,
            &response);
        if (delivered == 0)
        {
            SetError(error, "CloudOS NativeShell request timed out or failed");
            return FALSE;
        }
        return response;
    }

    static ShellActivationV21::SurfaceResult SendSurfaceRequest(
        ShellActivationV21::App app,
        ShellActivationV21::SurfaceAction action,
        std::string* error) noexcept
    {
        if (!ShellActivationV21::IsSupported(app) ||
            !ShellActivationV21::IsSupported(action))
        {
            SetError(error, "Unsupported NativeShell surface request");
            return ShellActivationV21::SurfaceResult::Rejected;
        }

        const HWND activation_window = FindEndpoint();
        if (activation_window == nullptr)
        {
            SetError(error, "CloudOS NativeShell activation endpoint is unavailable");
            return ShellActivationV21::SurfaceResult::Rejected;
        }

        ShellActivationV21::SurfaceRequest request;
        request.app = app;
        request.action = action;
        const DWORD_PTR response = SendTypedRequest(
            activation_window,
            ShellActivationV21::kSurfaceCopyDataTag,
            request,
            error);

        const auto result = static_cast<ShellActivationV21::SurfaceResult>(
            static_cast<std::uint32_t>(response));
        if (result == ShellActivationV21::SurfaceResult::Rejected)
        {
            SetError(error, "CloudOS NativeShell rejected the surface request");
        }
        return result;
    }

    static void SetError(std::string* error, const char* message) noexcept
    {
        if (error != nullptr) *error = message;
    }
};
} // namespace CloudOS