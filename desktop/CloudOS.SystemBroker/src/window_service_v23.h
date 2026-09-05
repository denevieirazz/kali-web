#pragma once

#include <Windows.h>

#include "protocol_v21.h"
#include "../../CloudOS.NativeCommon/native_window_registry_v23.h"

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

namespace CloudOS
{

class WindowServiceV23 final
{
public:
    static WindowServiceV23& Instance();

    WindowServiceV23(const WindowServiceV23&) = delete;
    WindowServiceV23& operator=(const WindowServiceV23&) = delete;

    bool GetSnapshot(std::string& out_json, std::string* error = nullptr);
    bool ExecuteCommand(const WindowRegistryV23::WindowCommandPayload& command, std::string* error = nullptr);

    bool FocusWindow(uint64_t hwnd, std::string* error = nullptr);
    bool MinimizeWindow(uint64_t hwnd, std::string* error = nullptr);
    bool MaximizeWindow(uint64_t hwnd, std::string* error = nullptr);
    bool RestoreWindow(uint64_t hwnd, std::string* error = nullptr);
    bool CloseWindow(uint64_t hwnd, std::string* error = nullptr);
    bool SetBounds(uint64_t hwnd, int x, int y, int width, int height, std::string* error = nullptr);
    bool SnapWindow(uint64_t hwnd, WindowRegistryV23::SnapTarget snap, std::string* error = nullptr);
    bool MoveToWorkspace(uint64_t hwnd, int workspace, std::string* error = nullptr);
    bool SetFullscreen(uint64_t hwnd, bool fullscreen, std::string* error = nullptr);

    [[nodiscard]] uint64_t GetGeneration() const noexcept { return generation_.load(); }
    void Invalidate();

private:
    WindowServiceV23() = default;
    ~WindowServiceV23() = default;

    static HWND FindEndpoint() noexcept;
    static std::wstring CreateMappingName();

    mutable std::mutex mutex_;
    std::atomic_uint64_t generation_{1};
    inline static std::atomic_uint64_t mapping_sequence_{0};
};

} // namespace CloudOS
