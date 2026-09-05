#pragma once

#include "protocol_v21.h"

#include <Windows.h>

#include <atomic>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace CloudOS
{

struct ClipboardItemV26 final
{
    uint64_t id{0};
    std::string timestamp;
    std::string type{"text"}; // "text", "image", "files"
    std::string preview;
    std::string full_text;
    std::vector<std::string> files;
    size_t data_bytes{0};
    int image_width{0};
    int image_height{0};

    [[nodiscard]] JsonObject ToJsonObject(bool include_full_text = true) const;
};

class ClipboardServiceV26 final
{
public:
    static ClipboardServiceV26& Instance();

    ClipboardServiceV26(const ClipboardServiceV26&) = delete;
    ClipboardServiceV26& operator=(const ClipboardServiceV26&) = delete;

    bool Start();
    void Stop();

    [[nodiscard]] std::vector<ClipboardItemV26> GetHistory(size_t limit = 20) const;
    [[nodiscard]] std::string GetCurrentText() const;
    bool SetText(const std::string& text, std::string* error = nullptr);
    bool Clear(std::string* error = nullptr);

private:
    ClipboardServiceV26();
    ~ClipboardServiceV26();

    void ListenerThreadProc();
    void CaptureCurrentClipboard();

    static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);

    mutable std::mutex mutex_;
    std::deque<ClipboardItemV26> history_;
    std::atomic<uint64_t> next_id_{1};
    std::atomic_bool running_{false};
    std::thread listener_thread_;
    HWND listener_hwnd_{nullptr};
    DWORD listener_thread_id_{0};

    static constexpr size_t kMaxHistoryItems = 30;
    static constexpr size_t kMaxItemTextLength = 65536; // 64 KiB
};

} // namespace CloudOS
