#pragma once

#include <Windows.h>

#include <cstddef>
#include <string>
#include <vector>

#include "cloudos_native_runtime.h"

constexpr UINT CLOUDOS_WM_NATIVE_WINDOW_EVENT = WM_APP + 0x220;

struct CloudOSManagedWindow final
{
    HWND hwnd{};
    DWORD process_id{};
    int workspace{};
    bool floating{};
    bool hidden_by_workspace{};
    std::wstring title;
};

enum class CloudOSSnapDirection
{
    Left,
    Right,
    Up,
    Down,
};

class CloudOSNativeWindowManager final
{
public:
    CloudOSNativeWindowManager() = default;
    ~CloudOSNativeWindowManager();

    CloudOSNativeWindowManager(const CloudOSNativeWindowManager&) = delete;
    CloudOSNativeWindowManager& operator=(const CloudOSNativeWindowManager&) = delete;

    bool Initialize(HWND event_sink);
    void Shutdown() noexcept;
    void SetReservedBottomPixels(int pixels) noexcept;

    void HandleRuntimeEvent(cloudos_native_window_event_kind kind, HWND window);
    void Reconcile();

    [[nodiscard]] std::vector<CloudOSManagedWindow> CurrentWorkspaceWindows() const;
    [[nodiscard]] std::size_t ManagedWindowCount() const noexcept;
    [[nodiscard]] int CurrentWorkspace() const noexcept;
    [[nodiscard]] bool TilingEnabled() const noexcept;
    [[nodiscard]] HWND ActiveManagedWindow() const noexcept;

    void FocusWindow(HWND window);
    void FocusNext(bool reverse);
    void CloseActive();
    void MinimizeActive();
    void ToggleMaximizeActive();
    void SnapActive(CloudOSSnapDirection direction);

    void ToggleTiling();
    void TileCurrentWorkspace();
    void ToggleFloatingActive();

    void SwitchWorkspace(int workspace);
    void MoveActiveToWorkspace(int workspace);

private:
    static void CALLBACK RuntimeWindowEvent(
        cloudos_native_window_event_kind kind,
        HWND window,
        DWORD process_id,
        void* context);

    static BOOL CALLBACK RuntimeWindowEnumeration(
        HWND window,
        DWORD process_id,
        BOOL visible,
        void* context);

    static BOOL CALLBACK LocalWindowEnumeration(
        HWND window,
        LPARAM context);

    bool IsManageable(HWND window, DWORD process_id, bool require_visible) const;
    void AddOrRefresh(HWND window, DWORD process_id);
    void Remove(HWND window);
    CloudOSManagedWindow* Find(HWND window) noexcept;
    const CloudOSManagedWindow* Find(HWND window) const noexcept;
    void UpdateForeground(HWND window);
    void UpdateBorders();
    void RecoverTaggedWindow(HWND window);
    void MarkWorkspaceHidden(HWND window, bool hidden) noexcept;
    RECT WorkAreaFor(HWND reference) const noexcept;
    static std::wstring ReadWindowTitle(HWND window);
    static bool IsExcludedClass(HWND window);

    HWND event_sink_{};
    void* watcher_{};
    HWND active_window_{};
    int current_workspace_{};
    int reserved_bottom_pixels_{58};
    bool tiling_enabled_{false};
    std::vector<CloudOSManagedWindow> windows_;
};
