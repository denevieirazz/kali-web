#pragma once

#include <Windows.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace CloudOS
{

class EventTransportV23 final
{
public:
    using ClientBindingValidator = std::function<bool(const std::string&, DWORD)>;

    static EventTransportV23& Instance();

    EventTransportV23(const EventTransportV23&) = delete;
    EventTransportV23& operator=(const EventTransportV23&) = delete;

    bool Start(ClientBindingValidator validator);
    void Stop();

    [[nodiscard]] bool IsRunning() const noexcept { return running_.load(); }
    [[nodiscard]] uint64_t GetDroppedEventCount() const noexcept
    {
        return dropped_events_.load();
    }

private:
    EventTransportV23() = default;
    ~EventTransportV23();

    void ListenerLoop();
    void ClientLoop(HANDLE pipe, DWORD process_id);

    static bool SendFrame(HANDLE pipe, const std::string& payload);
    static bool ReadFrame(HANDLE pipe, std::string& payload);

    std::atomic_bool running_{false};
    std::atomic_uint64_t dropped_events_{0};
    ClientBindingValidator validator_;
    mutable std::mutex validator_mutex_;

    std::thread listener_thread_;
    std::vector<std::thread> client_threads_;
    std::mutex client_threads_mutex_;
};

} // namespace CloudOS
