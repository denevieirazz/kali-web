#include "native_shell_dispatch_v21.h"

namespace CloudOS
{
NativeShellDispatchV21::~NativeShellDispatchV21()
{
    Stop();
}

bool NativeShellDispatchV21::Start(HINSTANCE instance, Callback callback)
{
    if (window_ != nullptr && IsWindow(window_))
    {
        callback_ = std::move(callback);
        return true;
    }
    if (!callback)
    {
        return false;
    }

    instance_ = instance;
    callback_ = std::move(callback);

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &NativeShellDispatchV21::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.lpszClassName = kNativeShellDispatchWindowClassV21;

    if (RegisterClassExW(&window_class) == 0 &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        callback_ = {};
        instance_ = nullptr;
        return false;
    }

    window_ = CreateWindowExW(
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
        instance_,
        this);
    if (window_ == nullptr)
    {
        callback_ = {};
        instance_ = nullptr;
        return false;
    }
    return true;
}

void NativeShellDispatchV21::Stop() noexcept
{
    if (window_ != nullptr && IsWindow(window_))
    {
        DestroyWindow(window_);
    }
    window_ = nullptr;
    callback_ = {};
    instance_ = nullptr;
}

LRESULT CALLBACK NativeShellDispatchV21::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* self = reinterpret_cast<NativeShellDispatchV21*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));

    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<CREATESTRUCTW*>(l_param);
        self = create != nullptr
            ? static_cast<NativeShellDispatchV21*>(create->lpCreateParams)
            : nullptr;
        if (self == nullptr)
        {
            return FALSE;
        }
        SetWindowLongPtrW(
            window,
            GWLP_USERDATA,
            reinterpret_cast<LONG_PTR>(self));
        self->window_ = window;
    }

    if (message == kNativeShellDispatchMessageV21)
    {
        if (self == nullptr || !self->callback_)
        {
            return 0;
        }
        const auto command = static_cast<NativeShellDispatchCommandV21>(
            static_cast<std::uint32_t>(w_param));
        if (!IsValidNativeShellDispatchCommandV21(command))
        {
            return 0;
        }
        self->callback_(command);
        return 1;
    }

    if (message == WM_NCDESTROY && self != nullptr)
    {
        self->window_ = nullptr;
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
    }

    return DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
