#include "native_shell_bridge.h"

#include "../../CloudOS.NativeCommon/native_shell_dispatch_v21.h"
#include "native_app_launcher.h"

#include <mutex>
#include <utility>

namespace CloudOS
{
namespace
{
std::mutex g_bridge_mutex;
NativeShellBridge::Callback g_workspace_overview_callback;
NativeShellBridge::Callback g_show_desktop_callback;
HWND g_external_dispatch_window{};

const wchar_t* AppIdForDispatchCommand(
    NativeShellDispatchCommandV21 command) noexcept
{
    switch (command)
    {
    case NativeShellDispatchCommandV21::Browser: return L"browser";
    case NativeShellDispatchCommandV21::Files: return L"files";
    case NativeShellDispatchCommandV21::Terminal: return L"terminal";
    case NativeShellDispatchCommandV21::Calculator: return L"calc";
    case NativeShellDispatchCommandV21::Settings: return L"settings";
    case NativeShellDispatchCommandV21::Drive: return L"drive";
    default: return nullptr;
    }
}

LRESULT CALLBACK ExternalDispatchWindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    if (message == kNativeShellDispatchMessageV21)
    {
        const auto command = static_cast<NativeShellDispatchCommandV21>(
            static_cast<std::uint32_t>(w_param));
        if (!IsValidNativeShellDispatchCommandV21(command))
        {
            return 0;
        }

        const wchar_t* app_id = AppIdForDispatchCommand(command);
        if (app_id == nullptr)
        {
            return 0;
        }

        NativeAppLauncher::LaunchById(
            GetModuleHandleW(nullptr),
            nullptr,
            app_id);
        return 1;
    }

    if (message == WM_NCDESTROY && window == g_external_dispatch_window)
    {
        g_external_dispatch_window = nullptr;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

bool EnsureExternalDispatchWindow()
{
    if (g_external_dispatch_window != nullptr &&
        IsWindow(g_external_dispatch_window))
    {
        return true;
    }

    HINSTANCE instance = GetModuleHandleW(nullptr);
    if (instance == nullptr)
    {
        return false;
    }

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &ExternalDispatchWindowProcedure;
    window_class.hInstance = instance;
    window_class.lpszClassName = kNativeShellDispatchWindowClassV21;

    if (RegisterClassExW(&window_class) == 0 &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    g_external_dispatch_window = CreateWindowExW(
        0,
        kNativeShellDispatchWindowClassV21,
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
    return g_external_dispatch_window != nullptr;
}

bool Invoke(const NativeShellBridge::Callback& callback)
{
    if (!callback)
    {
        return false;
    }
    callback();
    return true;
}
}

void NativeShellBridge::SetWorkspaceOverviewCallback(Callback callback)
{
    {
        std::scoped_lock lock(g_bridge_mutex);
        g_workspace_overview_callback = std::move(callback);
    }
    (void)EnsureExternalDispatchWindow();
}

void NativeShellBridge::SetShowDesktopCallback(Callback callback)
{
    std::scoped_lock lock(g_bridge_mutex);
    g_show_desktop_callback = std::move(callback);
}

bool NativeShellBridge::OpenWorkspaceOverview()
{
    Callback callback;
    {
        std::scoped_lock lock(g_bridge_mutex);
        callback = g_workspace_overview_callback;
    }
    return Invoke(callback);
}

bool NativeShellBridge::ToggleShowDesktop()
{
    Callback callback;
    {
        std::scoped_lock lock(g_bridge_mutex);
        callback = g_show_desktop_callback;
    }
    return Invoke(callback);
}

void NativeShellBridge::Clear() noexcept
{
    {
        std::scoped_lock lock(g_bridge_mutex);
        g_workspace_overview_callback = {};
        g_show_desktop_callback = {};
    }

    if (g_external_dispatch_window != nullptr &&
        IsWindow(g_external_dispatch_window))
    {
        DestroyWindow(g_external_dispatch_window);
    }
    g_external_dispatch_window = nullptr;
}
} // namespace CloudOS
