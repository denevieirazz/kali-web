#pragma once

#include <Windows.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <atomic>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace CloudOS
{

class UniqueWinHandle final
{
public:
    UniqueWinHandle() noexcept = default;
    explicit UniqueWinHandle(HANDLE handle) noexcept : handle_(handle) {}
    ~UniqueWinHandle() { reset(); }

    UniqueWinHandle(const UniqueWinHandle&) = delete;
    UniqueWinHandle& operator=(const UniqueWinHandle&) = delete;

    UniqueWinHandle(UniqueWinHandle&& other) noexcept : handle_(other.release()) {}
    UniqueWinHandle& operator=(UniqueWinHandle&& other) noexcept
    {
        if (this != &other) reset(other.release());
        return *this;
    }

    [[nodiscard]] HANDLE get() const noexcept { return handle_; }
    [[nodiscard]] bool valid() const noexcept
    {
        return handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE;
    }

    HANDLE release() noexcept
    {
        HANDLE result = handle_;
        handle_ = nullptr;
        return result;
    }

    void reset(HANDLE handle = nullptr) noexcept
    {
        if (valid()) CloseHandle(handle_);
        handle_ = handle;
    }

private:
    HANDLE handle_{nullptr};
};

class UniquePseudoConsole final
{
public:
    UniquePseudoConsole() noexcept = default;
    explicit UniquePseudoConsole(HPCON handle) noexcept : handle_(handle) {}
    ~UniquePseudoConsole() { reset(); }

    UniquePseudoConsole(const UniquePseudoConsole&) = delete;
    UniquePseudoConsole& operator=(const UniquePseudoConsole&) = delete;

    UniquePseudoConsole(UniquePseudoConsole&& other) noexcept : handle_(other.release()) {}
    UniquePseudoConsole& operator=(UniquePseudoConsole&& other) noexcept
    {
        if (this != &other) reset(other.release());
        return *this;
    }

    [[nodiscard]] HPCON get() const noexcept { return handle_; }
    [[nodiscard]] bool valid() const noexcept { return handle_ != nullptr; }

    HPCON release() noexcept
    {
        HPCON result = handle_;
        handle_ = nullptr;
        return result;
    }

    void reset(HPCON handle = nullptr) noexcept
    {
        if (valid()) ClosePseudoConsole(handle_);
        handle_ = handle;
    }

private:
    HPCON handle_{nullptr};
};

struct TerminalSessionInfo
{
    std::string session_id;
    std::string shell_kind;
    std::string distro;
    std::string working_directory;
    int cols{80};
    int rows{24};
    bool is_alive{false};
    DWORD process_id{0};
};

class CloudOSConPTYManager final
{
public:
    static constexpr UINT kDispatchMessage = WM_APP + 0x441;

    static CloudOSConPTYManager& Instance();

    CloudOSConPTYManager(const CloudOSConPTYManager&) = delete;
    CloudOSConPTYManager& operator=(const CloudOSConPTYManager&) = delete;

    void SetMethodChannel(flutter::MethodChannel<flutter::EncodableValue>* channel);
    void SetPlatformWindow(HWND window);
    void DrainPlatformEvents();
    void SetEventSinkForTesting(
        std::function<void(const std::string&, const std::string&, int, bool)> sink);

    std::string CreateSession(
        const std::string& shell_kind,
        const std::string& distro,
        int cols,
        int rows,
        std::string& out_error,
        const std::string& working_directory = {});

    bool WriteSession(const std::string& session_id, const std::string& input_data);
    bool ResizeSession(const std::string& session_id, int cols, int rows);
    bool SignalSession(const std::string& session_id, const std::string& signal_type);
    bool CloseSession(const std::string& session_id);
    std::vector<TerminalSessionInfo> ListSessions();
    void ShutdownAll();

private:
    CloudOSConPTYManager() = default;
    ~CloudOSConPTYManager();

    struct ConPTYSession
    {
        std::string session_id;
        std::string shell_kind;
        std::string distro;
        std::string working_directory;
        int cols{80};
        int rows{24};
        UniquePseudoConsole pseudo_console;
        UniqueWinHandle process;
        UniqueWinHandle primary_thread;
        UniqueWinHandle pipe_in_writer;
        UniqueWinHandle pipe_out_reader;
        DWORD process_id{0};
        std::atomic<bool> is_alive{false};
        std::atomic<bool> closing{false};
        std::mutex io_mutex;
        std::thread reader_thread;
    };

    enum class PlatformEventKind { data, exit };

    struct PlatformEvent
    {
        PlatformEventKind kind{PlatformEventKind::data};
        std::string session_id;
        std::string data;
        int exit_code{0};
    };

    void ReaderLoop(const std::shared_ptr<ConPTYSession>& session);
    void NotifyData(const std::string& session_id, std::string data);
    void NotifyExit(const std::string& session_id, int exit_code);
    void QueuePlatformEvent(PlatformEvent event);

    std::mutex mutex_;
    std::unordered_map<std::string, std::shared_ptr<ConPTYSession>> sessions_;
    flutter::MethodChannel<flutter::EncodableValue>* channel_{nullptr};
    HWND platform_window_{nullptr};
    std::function<void(const std::string&, const std::string&, int, bool)>
        test_event_sink_;

    std::mutex event_mutex_;
    std::deque<PlatformEvent> pending_events_;
    std::atomic<uint64_t> session_counter_{0};
};

} // namespace CloudOS
