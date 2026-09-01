#pragma once

#include "../../CloudOS.NativeCommon/native_shell_dispatch_v21.h"

#include <Windows.h>

#include <functional>

namespace CloudOS
{
class NativeShellDispatchV21 final
{
public:
    using Callback = std::function<void(NativeShellDispatchCommandV21)>;

    NativeShellDispatchV21() = default;
    ~NativeShellDispatchV21();

    NativeShellDispatchV21(const NativeShellDispatchV21&) = delete;
    NativeShellDispatchV21& operator=(const NativeShellDispatchV21&) = delete;

    bool Start(HINSTANCE instance, Callback callback);
    void Stop() noexcept;

    [[nodiscard]] HWND Hwnd() const noexcept { return window_; }

private:
    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    Callback callback_;
};
} // namespace CloudOS
