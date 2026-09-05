#include "window_service_v23.h"
#include "event_bus_v21.h"

#include <Windows.h>

#include <chrono>
#include <cstring>

namespace CloudOS
{

WindowServiceV23& WindowServiceV23::Instance()
{
    static WindowServiceV23 instance;
    return instance;
}

HWND WindowServiceV23::FindEndpoint() noexcept
{
    return FindWindowExW(
        HWND_MESSAGE,
        nullptr,
        WindowRegistryV23::kWindowServerClass,
        nullptr);
}

std::wstring WindowServiceV23::CreateMappingName()
{
    const auto seq = ++mapping_sequence_;
    return L"Local\\CloudOS.WindowSnapshot.v23." +
        std::to_wstring(GetCurrentProcessId()) + L"." +
        std::to_wstring(GetTickCount64()) + L"." +
        std::to_wstring(seq);
}

bool WindowServiceV23::GetSnapshot(std::string& out_json, std::string* error)
{
    const HWND endpoint = FindEndpoint();
    if (endpoint == nullptr)
    {
        WindowRegistryV23::CloudWindowSnapshotV23 degraded;
        degraded.sequence = generation_.load();
        degraded.timestamp_ms = static_cast<uint64_t>(
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count());
        degraded.current_workspace = 1;
        out_json = degraded.ToJson();
        if (error) *error = "NativeShell activation endpoint unavailable";
        return true;
    }

    const std::wstring mapping_name = CreateMappingName();
    constexpr DWORD kMappingSize = 128 * 1024; // 128 KB
    HANDLE mapping = CreateFileMappingW(
        INVALID_HANDLE_VALUE,
        nullptr,
        PAGE_READWRITE,
        0,
        kMappingSize,
        mapping_name.c_str());
    if (mapping == nullptr)
    {
        if (error) *error = "Failed to create snapshot file mapping";
        return false;
    }

    void* view = MapViewOfFile(mapping, FILE_MAP_READ | FILE_MAP_WRITE, 0, 0, kMappingSize);
    if (view == nullptr)
    {
        CloseHandle(mapping);
        if (error) *error = "Failed to map snapshot memory view";
        return false;
    }

    std::memset(view, 0, kMappingSize);

    COPYDATASTRUCT copy_data{};
    copy_data.dwData = static_cast<ULONG_PTR>(WindowRegistryV23::kWindowSnapshotCopyDataTag);
    copy_data.cbData = static_cast<DWORD>((mapping_name.size() + 1) * sizeof(wchar_t));
    copy_data.lpData = const_cast<wchar_t*>(mapping_name.c_str());

    DWORD_PTR response = FALSE;
    const LRESULT delivered = SendMessageTimeoutW(
        endpoint,
        WM_COPYDATA,
        0,
        reinterpret_cast<LPARAM>(&copy_data),
        SMTO_ABORTIFHUNG | SMTO_BLOCK,
        1500,
        &response);

    bool ok = false;
    if (delivered != 0 && response != FALSE)
    {
        const auto* ptr = static_cast<const char*>(view);
        uint32_t length = 0;
        std::memcpy(&length, ptr, sizeof(length));
        if (length > 0 && length < kMappingSize - sizeof(length))
        {
            out_json.assign(ptr + sizeof(length), length);
            ok = true;
        }
        else
        {
            if (error) *error = "Invalid snapshot data length returned from NativeShell";
        }
    }
    else
    {
        if (error) *error = "NativeShell timed out or rejected snapshot request";
    }

    UnmapViewOfFile(view);
    CloseHandle(mapping);

    if (!ok)
    {
        WindowRegistryV23::CloudWindowSnapshotV23 degraded;
        degraded.sequence = generation_.load();
        degraded.timestamp_ms = static_cast<uint64_t>(
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count());
        degraded.current_workspace = 1;
        out_json = degraded.ToJson();
    }
    return true;
}

bool WindowServiceV23::ExecuteCommand(
    const WindowRegistryV23::WindowCommandPayload& command,
    std::string* error)
{
    const HWND endpoint = FindEndpoint();
    if (endpoint == nullptr)
    {
        if (error) *error = "NativeShell activation endpoint unavailable";
        return false;
    }

    COPYDATASTRUCT copy_data{};
    copy_data.dwData = static_cast<ULONG_PTR>(WindowRegistryV23::kWindowCommandCopyDataTag);
    copy_data.cbData = static_cast<DWORD>(sizeof(command));
    copy_data.lpData = const_cast<WindowRegistryV23::WindowCommandPayload*>(&command);

    DWORD_PTR response = FALSE;
    const LRESULT delivered = SendMessageTimeoutW(
        endpoint,
        WM_COPYDATA,
        0,
        reinterpret_cast<LPARAM>(&copy_data),
        SMTO_ABORTIFHUNG | SMTO_BLOCK,
        1500,
        &response);

    if (delivered == 0 || response == FALSE)
    {
        if (error) *error = "NativeShell timed out or rejected window command";
        return false;
    }

    Invalidate();
    return true;
}

bool WindowServiceV23::FocusWindow(uint64_t hwnd, std::string* error)
{
    WindowRegistryV23::WindowCommandPayload cmd;
    cmd.action = WindowRegistryV23::WindowCommandAction::Focus;
    cmd.hwnd = hwnd;
    return ExecuteCommand(cmd, error);
}

bool WindowServiceV23::MinimizeWindow(uint64_t hwnd, std::string* error)
{
    WindowRegistryV23::WindowCommandPayload cmd;
    cmd.action = WindowRegistryV23::WindowCommandAction::Minimize;
    cmd.hwnd = hwnd;
    return ExecuteCommand(cmd, error);
}

bool WindowServiceV23::MaximizeWindow(uint64_t hwnd, std::string* error)
{
    WindowRegistryV23::WindowCommandPayload cmd;
    cmd.action = WindowRegistryV23::WindowCommandAction::Maximize;
    cmd.hwnd = hwnd;
    return ExecuteCommand(cmd, error);
}

bool WindowServiceV23::RestoreWindow(uint64_t hwnd, std::string* error)
{
    WindowRegistryV23::WindowCommandPayload cmd;
    cmd.action = WindowRegistryV23::WindowCommandAction::Restore;
    cmd.hwnd = hwnd;
    return ExecuteCommand(cmd, error);
}

bool WindowServiceV23::CloseWindow(uint64_t hwnd, std::string* error)
{
    WindowRegistryV23::WindowCommandPayload cmd;
    cmd.action = WindowRegistryV23::WindowCommandAction::Close;
    cmd.hwnd = hwnd;
    return ExecuteCommand(cmd, error);
}

bool WindowServiceV23::SetBounds(uint64_t hwnd, int x, int y, int width, int height, std::string* error)
{
    WindowRegistryV23::WindowCommandPayload cmd;
    cmd.action = WindowRegistryV23::WindowCommandAction::SetBounds;
    cmd.hwnd = hwnd;
    cmd.x = x;
    cmd.y = y;
    cmd.width = width;
    cmd.height = height;
    return ExecuteCommand(cmd, error);
}

bool WindowServiceV23::SnapWindow(uint64_t hwnd, WindowRegistryV23::SnapTarget snap, std::string* error)
{
    WindowRegistryV23::WindowCommandPayload cmd;
    cmd.action = WindowRegistryV23::WindowCommandAction::Snap;
    cmd.hwnd = hwnd;
    cmd.snap = snap;
    return ExecuteCommand(cmd, error);
}

bool WindowServiceV23::MoveToWorkspace(uint64_t hwnd, int workspace, std::string* error)
{
    WindowRegistryV23::WindowCommandPayload cmd;
    cmd.action = WindowRegistryV23::WindowCommandAction::MoveToWorkspace;
    cmd.hwnd = hwnd;
    cmd.workspace = workspace;
    return ExecuteCommand(cmd, error);
}

bool WindowServiceV23::SetFullscreen(uint64_t hwnd, bool fullscreen, std::string* error)
{
    WindowRegistryV23::WindowCommandPayload cmd;
    cmd.action = WindowRegistryV23::WindowCommandAction::SetFullscreen;
    cmd.hwnd = hwnd;
    cmd.workspace = fullscreen ? 1 : 0;
    return ExecuteCommand(cmd, error);
}

void WindowServiceV23::Invalidate()
{
    generation_++;
    JsonObject payload;
    payload["generation"] = JsonValue(static_cast<int64_t>(generation_.load()));
    EventBusV21::Instance().Publish("window.snapshotChanged", payload);
}

} // namespace CloudOS
