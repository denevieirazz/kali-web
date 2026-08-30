#pragma once

#include <windows.h>

#include <memory>
#include <string>

#include "native_workspace_automation.h"
#include "native_workspace_studio_model.h"

class CloudOSNativeWindowManager;

namespace CloudOS
{
class NativeWorkspaceStudioWindow;

class NativeWorkspaceStudioService final
{
public:
    static NativeWorkspaceStudioService& Instance();
    static void RegisterManager(CloudOSNativeWindowManager* manager);
    static void Open(HINSTANCE instance, HWND owner = nullptr);

    NativeWorkspaceStudioService(const NativeWorkspaceStudioService&) = delete;
    NativeWorkspaceStudioService& operator=(const NativeWorkspaceStudioService&) = delete;

    [[nodiscard]] NativeWorkspaceStudioStore& Store() noexcept;
    [[nodiscard]] NativeWorkspaceAutomationEngine& Automation() noexcept;
    [[nodiscard]] CloudOSNativeWindowManager* Manager() const noexcept;
    [[nodiscard]] HWND EngineWindow() const noexcept;

    bool Save();
    void Reload();
    void ReapplyRules();
    void ApplyCurrentProfile();
    void CaptureQuickSnapshot();
    void RestoreLatestSnapshot();
    void OpenWindow(HINSTANCE instance, HWND owner);

private:
    NativeWorkspaceStudioService();
    ~NativeWorkspaceStudioService();

    bool EnsureEngineWindow(HINSTANCE instance);
    void Tick();
    void RegisterHotKeys();
    void UnregisterHotKeys();
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    CloudOSNativeWindowManager* manager_{};
    NativeWorkspaceStudioStore store_;
    NativeWorkspaceAutomationEngine automation_;
    std::unique_ptr<NativeWorkspaceStudioWindow> studio_window_;
    HWND engine_window_{};
    HWND owner_{};
    HINSTANCE instance_{};
    bool store_loaded_{};
};
} // namespace CloudOS
