#pragma once

#include <Windows.h>

#include <atomic>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

class CloudOSNativeTerminalWindow final
{
public:
    static void Open(
        HINSTANCE instance,
        const std::wstring& command_line,
        const std::wstring& title);

    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

private:
    CloudOSNativeTerminalWindow(
        HINSTANCE instance,
        std::wstring command_line,
        std::wstring title);
    ~CloudOSNativeTerminalWindow();

    CloudOSNativeTerminalWindow(const CloudOSNativeTerminalWindow&) = delete;
    CloudOSNativeTerminalWindow& operator=(const CloudOSNativeTerminalWindow&) = delete;

    bool Create();
    bool StartTerminal();
    void StopTerminal() noexcept;
    void ReaderLoop();
    void ConsumeOutputBytes(const char* bytes, DWORD size);
    void FlushUtf8Pending();
    void AppendText(std::wstring_view text);
    void WriteBytes(const void* bytes, DWORD size);
    void WriteUtf8(std::wstring_view text);
    void PasteClipboard();
    void ResizeTerminal();
    void Paint();
    void UpdateFontMetrics();
    void ScrollBy(int lines);
    std::vector<std::wstring> VisibleLines() const;

    LRESULT HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    std::wstring command_line_;
    std::wstring title_;

    void* terminal_{};
    DWORD process_id_{};

    HFONT font_{};
    int cell_width_{9};
    int cell_height_{18};
    int scroll_offset_lines_{};

    std::wstring output_;
    std::vector<char> pending_utf8_;
    int ansi_state_{};

    std::atomic_bool stopping_{false};
    mutable std::mutex output_mutex_;
    std::thread reader_thread_;
};
