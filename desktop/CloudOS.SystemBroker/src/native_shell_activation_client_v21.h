#pragma once

#include "../../CloudOS.NativeCommon/native_shell_activation_v21.h"

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

        // The authoritative activation server is a message-only window.
        // FindWindowW searches top-level windows and does not reliably resolve
        // HWND_MESSAGE children, so search the message-only window tree directly.
        const HWND activation_window = FindWindowExW(
            HWND_MESSAGE,
            nullptr,
            ShellActivationV21::kWindowClass,
            nullptr);
        if (activation_window == nullptr)
        {
            SetError(error, "CloudOS NativeShell activation endpoint is unavailable");
            return false;
        }

        ShellActivationV21::Request request;
        request.app = app;

        COPYDATASTRUCT copy_data{};
        copy_data.dwData =
            static_cast<ULONG_PTR>(ShellActivationV21::kCopyDataTag);
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
            SetError(error, "CloudOS NativeShell activation request timed out or failed");
            return false;
        }
        if (response == FALSE)
        {
            SetError(error, "CloudOS NativeShell rejected the activation request");
            return false;
        }
        return true;
    }

private:
    static void SetError(std::string* error, const char* message) noexcept
    {
        if (error != nullptr)
        {
            *error = message;
        }
    }
};
} // namespace CloudOS