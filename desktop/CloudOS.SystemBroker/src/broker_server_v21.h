#pragma once

#include "protocol_v21.h"

#include <Windows.h>

#include <algorithm>
#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace CloudOS
{

class BrokerServerV21 final
{
public:
    static BrokerServerV21& Instance();

    BrokerServerV21(const BrokerServerV21&) = delete;
    BrokerServerV21& operator=(const BrokerServerV21&) = delete;

    bool Start();
    void Stop();
    [[nodiscard]] bool IsRunning() const noexcept { return running_.load(); }

    BrokerResponse HandleRequest(const std::string& client_id, const BrokerRequest& req);

private:
    BrokerServerV21() = default;
    ~BrokerServerV21();

    struct ClientThreadEntry final
    {
        std::thread thread;
        std::shared_ptr<std::atomic_bool> finished;
    };

    void ListenerLoop();
    void ClientSessionLoop(
        HANDLE pipe,
        std::string client_id,
        std::shared_ptr<std::atomic_bool> finished);

    bool SendFrame(HANDLE pipe, const std::string& payload);
    bool ReadFrame(HANDLE pipe, std::string& payload);

    std::atomic_bool running_{false};
    HANDLE mutex_handle_{nullptr};
    std::thread listener_thread_;
    std::vector<ClientThreadEntry> client_threads_;
    std::vector<HANDLE> client_pipes_;
    std::mutex client_threads_mutex_;
    std::atomic_uint64_t next_client_id_{1};
};

} // namespace CloudOS
