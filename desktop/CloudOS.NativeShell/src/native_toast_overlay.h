#pragma once

#include <windows.h>

#include <string>

namespace CloudOS
{
class NativeToastOverlay final
{
public:
    static bool Initialize(HINSTANCE instance);
    static void Shutdown() noexcept;
    static void Post(
        const std::wstring& title,
        const std::wstring& message,
        int severity = 0,
        unsigned timeout_ms = 5200u);
    static void Dismiss() noexcept;

private:
    NativeToastOverlay() = delete;
};
} // namespace CloudOS
