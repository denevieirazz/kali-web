#pragma once

#include <Windows.h>

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "cloudos_native_runtime.h"
#include "../../CloudOS.NativeCommon/native_window_registry_v23.h"

constexpr UINT CLOUDOS_WM_MODEL_CHANGED_V12 = WM_APP + 0x615;
constexpr UINT CLOUDOS_WM_NATIVE_WINDOW_EVENT = WM_APP + 0x220;

struct CloudOSManagedWindow final
{
    HWND hwnd{};
    DWORD process_id{};
    int workspace{};
    bool floating{};
    bool hidden_by_workspace{};
    std::wstring title;
    HMONITOR monitor{};
    bool minimized{};
    RECT bounds{};
    bool maximized{false};
    bool fullscreen{false};
    std::string platform{"windows"};
    std::string app_id;
    HWND owner{nullptr};
    std::vector<std::string> capabilities;
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
    CloudOSNativeWindowManager();
    ~CloudOSNativeWindowManager();

    CloudOSNativeWindowManager(const CloudOSNativeWindowManager&) = delete;
    CloudOSNativeWindowManager& operator=(const CloudOSNativeWindowManager&) = delete;

    bool Initialize(HWND event_sink);
    void Shutdown() noexcept;
    void SetReservedBottomPixels(int pixels) noexcept;

    void HandleRuntimeEvent(cloudos_native_window_event_kind kind, HWND window);
    void Reconcile();
    void HandleDisplayTopologyChanged();
    std::uint64_t RevisionV12() const noexcept {return revision_v12_;}

    [[nodiscard]] std::vector<CloudOSManagedWindow> CurrentWorkspaceWindows() const;
    [[nodiscard]] std::vector<CloudOSManagedWindow> AllManagedWindows() const;
    [[nodiscard]] std::size_t ManagedWindowCount() const noexcept;
    [[nodiscard]] int CurrentWorkspace() const noexcept;
    [[nodiscard]] bool TilingEnabled() const noexcept;
    [[nodiscard]] HWND ActiveManagedWindow() const noexcept;
    [[nodiscard]] int WorkspaceFor(HWND window) const noexcept;

    void FocusWindow(HWND window);
    void FocusNext(bool reverse);
    void CloseActive();
    void MinimizeActive();
    void ToggleMaximizeActive();
    void SnapActive(CloudOSSnapDirection direction);

    void ToggleTiling();
    void SetTilingEnabled(bool enabled);
    void TileCurrentWorkspace();
    void ToggleFloatingActive();
    void SetWindowFloating(HWND window, bool floating);

    void SwitchWorkspace(int workspace);
    void MoveActiveToWorkspace(int workspace);
    void MoveWindowToWorkspace(HWND window, int workspace);
    bool RestoreWindowState(
        HWND window,
        int workspace,
        bool floating,
        const RECT& bounds,
        UINT show_command);

    // Operations V23
    void MinimizeWindow(HWND window);
    void MaximizeWindow(HWND window);
    void RestoreWindow(HWND window);
    void CloseWindow(HWND window);
    bool SetWindowBounds(HWND window, int x, int y, int width, int height);
    bool SnapWindow(HWND window, CloudOS::WindowRegistryV23::SnapTarget snap);
    void SetWindowFullscreen(HWND window, bool fullscreen);
    bool ExecuteWindowCommand(const CloudOS::WindowRegistryV23::WindowCommandPayload& command);

    // Registry Snapshot V23
    [[nodiscard]] CloudOS::WindowRegistryV23::CloudWindowSnapshotV23 GetRegistrySnapshot() const;
    [[nodiscard]] std::string GetRegistrySnapshotJson() const;
    bool WriteRegistrySnapshotToMapping(const wchar_t* mapping_name) const;
    [[nodiscard]] std::uint64_t SequenceV23() const noexcept { return sequence_.load(); }

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
    void NotifyChanged() { ++revision_v12_; ++sequence_; if (event_sink_) PostMessageW(event_sink_, CLOUDOS_WM_MODEL_CHANGED_V12, 0, 0); }
    void RecoverTaggedWindow(HWND window);
    void MarkWorkspaceHidden(HWND window, bool hidden) noexcept;
    RECT WorkAreaFor(HWND reference) const noexcept;
    static std::wstring ReadWindowTitle(HWND window);
    static bool IsExcludedClass(HWND window);

    std::uint64_t revision_v12_{};
    std::atomic_uint64_t sequence_{1};
    HWND event_sink_{};
    void* watcher_{};
    HWND active_window_{};
    int current_workspace_{};
    int reserved_bottom_pixels_{58};
    bool tiling_enabled_{false};
    std::vector<CloudOSManagedWindow> windows_;
};
