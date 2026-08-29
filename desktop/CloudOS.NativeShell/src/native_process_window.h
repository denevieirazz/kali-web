#pragma once

#include <Windows.h>

#include <string>
#include <vector>

class CloudOSNativeProcessWindow final {
public:
    static void Open(HINSTANCE instance);

    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

private:
    struct ProcessEntry final {
        DWORD process_id{};
        std::wstring name;
        SIZE_T working_set{};
    };

    explicit CloudOSNativeProcessWindow(HINSTANCE instance);
    ~CloudOSNativeProcessWindow() = default;

    CloudOSNativeProcessWindow(const CloudOSNativeProcessWindow&) = delete;
    CloudOSNativeProcessWindow& operator=(const CloudOSNativeProcessWindow&) = delete;

    bool Create();
    void Layout();
    void Refresh();
    void TerminateSelected();
    void FocusSelectedProcess();
    static SIZE_T QueryWorkingSet(DWORD process_id);
    static std::wstring FormatMemory(SIZE_T bytes);

    LRESULT HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND list_{};
    HWND refresh_button_{};
    HWND terminate_button_{};
    HWND focus_button_{};
    std::vector<ProcessEntry> processes_;
};
