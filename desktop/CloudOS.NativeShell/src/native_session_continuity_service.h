#pragma once

#include <windows.h>

#include <array>
#include <cstdint>
#include <memory>
#include <string>

#include "native_session_continuity_model.h"

class CloudOSNativeWindowManager;

namespace CloudOS
{
class NativeSessionContinuityWindow;

class NativeSessionContinuityService final
{
public:
    static NativeSessionContinuityService& Instance();
    static void RegisterManager(CloudOSNativeWindowManager* manager);
    static void Open(HINSTANCE instance = nullptr, HWND owner = nullptr);

    NativeSessionContinuityService(const NativeSessionContinuityService&) = delete;
    NativeSessionContinuityService& operator=(const NativeSessionContinuityService&) = delete;

    [[nodiscard]] NativeSessionContinuityStore& Store() noexcept { return store_; }
    [[nodiscard]] const NativeSessionContinuityStore& Store() const noexcept { return store_; }
    [[nodiscard]] CloudOSNativeWindowManager* Manager() const noexcept { return manager_; }
    [[nodiscard]] HWND EngineWindow() const noexcept { return engine_window_; }
    [[nodiscard]] bool PreviousSessionUnclean() const noexcept { return previous_unclean_; }
    [[nodiscard]] bool Initialized() const noexcept { return initialized_; }

    bool SaveNow(const std::wstring& reason = L"manual");
    std::uint32_t CaptureCheckpoint(int workspace, const std::wstring& reason);
    bool RestoreCheckpoint(std::uint32_t checkpoint_id);
    bool RestoreLatest(int workspace);
    void ClearJournal();
    void ClearCheckpoints();
    void PreferencesChanged();
    void RefreshWindow();

private:
    NativeSessionContinuityService();
    ~NativeSessionContinuityService();

    bool EnsureInitialized(HINSTANCE instance);
    bool EnsureEngineWindow(HINSTANCE instance);
    void Tick();
    void RegisterHotKeys();
    void UnregisterHotKeys();
    void MarkLiveSession();
    void MarkCleanSession();
    void HandleInitialResume();
    void HandleWorkspaceChange(int current_workspace);
    void HandleFocusChange(int current_workspace);
    void HandleAutoCheckpoint(int current_workspace);
    std::uint64_t WorkspaceSignature(int workspace) const;
    std::wstring LiveMarkerPath() const;

    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    CloudOSNativeWindowManager* manager_{};
    NativeSessionContinuityStore store_;
    std::unique_ptr<NativeSessionContinuityWindow> window_;
    HWND engine_window_{};
    HINSTANCE instance_{};
    HWND owner_{};
    bool initialized_{};
    bool previous_unclean_{};
    bool initial_resume_done_{};
    int observed_workspace_{-1};
    HWND observed_foreground_{};
    std::array<std::uint64_t, 4> last_workspace_signature_{};
    std::array<ULONGLONG, 4> last_checkpoint_tick_{};
};
} // namespace CloudOS
