#pragma once

#if __has_include("../../CloudOS.SystemBroker/src/protocol_v21.h")
#include "../../CloudOS.SystemBroker/src/protocol_v21.h"
#else
#include "protocol_v21.h"
#endif

#include <Windows.h>
#include <sddl.h>

#include <algorithm>
#include <atomic>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace CloudOS
{

class CloudOSEventClientV23 final
{
public:
    static CloudOSEventClientV23& Instance()
    {
        static CloudOSEventClientV23 instance;
        return instance;
    }

    CloudOSEventClientV23(const CloudOSEventClientV23&) = delete;
    CloudOSEventClientV23& operator=(const CloudOSEventClientV23&) = delete;

    bool Start(const std::string& client_id)
    {
        if (client_id.empty() || client_id.size() > 256) return false;
        Stop();

        HANDLE stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (stop_event == nullptr) return false;
        {
            std::lock_guard<std::mutex> lock(state_mutex_);
            client_id_ = client_id;
            stop_event_ = stop_event;
        }

        running_.store(true);
        dropped_events_.store(0);
        try
        {
            worker_ = std::thread([this]() { WorkerLoop(); });
        }
        catch (...)
        {
            running_.store(false);
            std::lock_guard<std::mutex> lock(state_mutex_);
            CloseHandle(stop_event_);
            stop_event_ = nullptr;
            client_id_.clear();
            return false;
        }
        return true;
    }

    void Stop()
    {
        running_.store(false);

        HANDLE pipe = INVALID_HANDLE_VALUE;
        HANDLE stop_event = nullptr;
        {
            std::lock_guard<std::mutex> lock(state_mutex_);
            pipe = pipe_;
            stop_event = stop_event_;
        }

        if (stop_event != nullptr) SetEvent(stop_event);
        if (pipe != INVALID_HANDLE_VALUE) (void)CancelIoEx(pipe, nullptr);
        if (worker_.joinable())
        {
            (void)CancelSynchronousIo(
                reinterpret_cast<HANDLE>(worker_.native_handle()));
            worker_.join();
        }

        connected_.store(false);
        {
            std::lock_guard<std::mutex> lock(state_mutex_);
            // WorkerLoop owns/closed every connected pipe. Only close a
            // residual handle here if startup failed before the worker owned it.
            if (pipe_ != INVALID_HANDLE_VALUE)
            {
                CloseHandle(pipe_);
                pipe_ = INVALID_HANDLE_VALUE;
            }
            if (stop_event_ != nullptr)
            {
                CloseHandle(stop_event_);
                stop_event_ = nullptr;
            }
            client_id_.clear();
        }
        {
            std::lock_guard<std::mutex> lock(queue_mutex_);
            queue_.clear();
            queued_bytes_ = 0;
        }
    }

    [[nodiscard]] bool IsConnected() const noexcept
    {
        return connected_.load();
    }

    [[nodiscard]] uint64_t GetDroppedEventCount() const noexcept
    {
        return dropped_events_.load();
    }

    std::vector<BrokerEvent> Drain(size_t max_events = 64)
    {
        max_events = std::clamp<size_t>(max_events, 1, 256);
        std::vector<BrokerEvent> result;
        std::lock_guard<std::mutex> lock(queue_mutex_);
        const size_t count = (std::min)(max_events, queue_.size());
        result.reserve(count);
        for (size_t index = 0; index < count; ++index)
        {
            queued_bytes_ -= queue_.front().encoded_bytes;
            result.push_back(std::move(queue_.front().event));
            queue_.pop_front();
        }
        return result;
    }

private:
    struct QueuedEvent final
    {
        BrokerEvent event;
        size_t encoded_bytes{0};
    };

    static constexpr size_t kMaxQueuedEvents = 256;
    static constexpr size_t kMaxQueuedBytes = 4u * 1024u * 1024u;
    static constexpr uint32_t kInitialReconnectMs = 250;
    static constexpr uint32_t kMaxReconnectMs = 5000;

    CloudOSEventClientV23() = default;
    ~CloudOSEventClientV23() { Stop(); }

    static std::wstring CurrentUserSid()
    {
        HANDLE token = nullptr;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return {};

        DWORD length = 0;
        (void)GetTokenInformation(token, TokenUser, nullptr, 0, &length);
        if (length == 0)
        {
            CloseHandle(token);
            return {};
        }

        std::vector<BYTE> buffer(length);
        if (!GetTokenInformation(token, TokenUser, buffer.data(), length, &length))
        {
            CloseHandle(token);
            return {};
        }
        CloseHandle(token);

        const auto* user = reinterpret_cast<const TOKEN_USER*>(buffer.data());
        LPWSTR raw_sid = nullptr;
        if (user == nullptr || user->User.Sid == nullptr ||
            !IsValidSid(user->User.Sid) ||
            !ConvertSidToStringSidW(user->User.Sid, &raw_sid) || raw_sid == nullptr)
        {
            return {};
        }
        std::wstring sid(raw_sid);
        LocalFree(raw_sid);
        return sid;
    }

    static DWORD CurrentSessionId()
    {
        DWORD session = 0xFFFFFFFFu;
        return ProcessIdToSessionId(GetCurrentProcessId(), &session)
            ? session
            : 0xFFFFFFFFu;
    }

    static std::wstring EventsPipeName()
    {
        const std::wstring sid = CurrentUserSid();
        const DWORD session = CurrentSessionId();
        if (sid.empty() || session == 0xFFFFFFFFu) return {};
        return L"\\\\.\\pipe\\CloudOS.SystemBroker.Events.v21." +
            sid + L"." + std::to_wstring(session);
    }

    static bool WriteFrame(HANDLE pipe, const std::string& payload)
    {
        if (pipe == INVALID_HANDLE_VALUE || payload.size() > kMaxPayloadBytes)
            return false;
        const uint32_t length = static_cast<uint32_t>(payload.size());
        DWORD written = 0;
        if (!WriteFile(pipe, &length, sizeof(length), &written, nullptr) ||
            written != sizeof(length))
            return false;
        return length == 0 ||
            (WriteFile(pipe, payload.data(), length, &written, nullptr) &&
             written == length);
    }

    static bool ReadFrame(HANDLE pipe, std::string& payload)
    {
        payload.clear();
        if (pipe == INVALID_HANDLE_VALUE) return false;
        uint32_t length = 0;
        DWORD read_bytes = 0;
        if (!ReadFile(pipe, &length, sizeof(length), &read_bytes, nullptr) ||
            read_bytes != sizeof(length) || length > kMaxPayloadBytes)
            return false;

        payload.resize(length);
        DWORD total = 0;
        while (total < length)
        {
            if (!ReadFile(
                    pipe,
                    payload.data() + total,
                    length - total,
                    &read_bytes,
                    nullptr) ||
                read_bytes == 0)
                return false;
            total += read_bytes;
        }
        return true;
    }

    bool ConnectOnce(HANDLE& out_pipe)
    {
        out_pipe = INVALID_HANDLE_VALUE;
        const std::wstring name = EventsPipeName();
        if (name.empty() || !running_.load()) return false;

        HANDLE pipe = CreateFileW(
            name.c_str(),
            GENERIC_READ | GENERIC_WRITE,
            0,
            nullptr,
            OPEN_EXISTING,
            0,
            nullptr);
        if (pipe == INVALID_HANDLE_VALUE) return false;

        std::string client_id;
        {
            std::lock_guard<std::mutex> lock(state_mutex_);
            client_id = client_id_;
        }
        JsonObject handshake;
        handshake["schema"] = JsonValue(23);
        handshake["transport"] = JsonValue("CloudOS.EventTransport.V23");
        handshake["clientId"] = JsonValue(client_id);
        if (!WriteFrame(pipe, SerializeJson(JsonValue(std::move(handshake)))))
        {
            CloseHandle(pipe);
            return false;
        }

        out_pipe = pipe;
        return true;
    }

    void Enqueue(BrokerEvent event, size_t encoded_bytes)
    {
        if (encoded_bytes == 0 || encoded_bytes > kMaxQueuedBytes)
        {
            dropped_events_.fetch_add(1);
            return;
        }

        uint64_t dropped = 0;
        {
            std::lock_guard<std::mutex> lock(queue_mutex_);
            while (!queue_.empty() &&
                   (queue_.size() >= kMaxQueuedEvents ||
                    queued_bytes_ + encoded_bytes > kMaxQueuedBytes))
            {
                queued_bytes_ -= queue_.front().encoded_bytes;
                queue_.pop_front();
                ++dropped;
            }
            if (queued_bytes_ + encoded_bytes > kMaxQueuedBytes)
            {
                ++dropped;
            }
            else
            {
                queued_bytes_ += encoded_bytes;
                queue_.push_back({std::move(event), encoded_bytes});
            }
        }
        if (dropped > 0) dropped_events_.fetch_add(dropped);
    }

    bool WaitReconnect(uint32_t milliseconds)
    {
        HANDLE stop_event = nullptr;
        {
            std::lock_guard<std::mutex> lock(state_mutex_);
            stop_event = stop_event_;
        }
        if (stop_event == nullptr) return running_.load();
        return WaitForSingleObject(stop_event, milliseconds) == WAIT_TIMEOUT &&
            running_.load();
    }

    void WorkerLoop()
    {
        uint32_t reconnect_ms = kInitialReconnectMs;
        while (running_.load())
        {
            HANDLE pipe = INVALID_HANDLE_VALUE;
            if (!ConnectOnce(pipe))
            {
                connected_.store(false);
                if (!WaitReconnect(reconnect_ms)) break;
                reconnect_ms = (std::min)(reconnect_ms * 2u, kMaxReconnectMs);
                continue;
            }

            {
                std::lock_guard<std::mutex> lock(state_mutex_);
                pipe_ = pipe;
            }
            connected_.store(true);
            reconnect_ms = kInitialReconnectMs;

            while (running_.load())
            {
                std::string frame;
                if (!ReadFrame(pipe, frame)) break;

                BrokerEvent event;
                std::string error;
                if (!ParseEvent(frame, event, error) ||
                    event.protocol != kProtocolVersion ||
                    event.event.empty() || event.event.size() > 256)
                {
                    dropped_events_.fetch_add(1);
                    continue;
                }
                Enqueue(std::move(event), frame.size());
            }

            connected_.store(false);
            {
                std::lock_guard<std::mutex> lock(state_mutex_);
                if (pipe_ == pipe) pipe_ = INVALID_HANDLE_VALUE;
            }
            CloseHandle(pipe);
            if (running_.load())
            {
                if (!WaitReconnect(reconnect_ms)) break;
                reconnect_ms = (std::min)(reconnect_ms * 2u, kMaxReconnectMs);
            }
        }
    }

    std::atomic_bool running_{false};
    std::atomic_bool connected_{false};
    std::atomic_uint64_t dropped_events_{0};
    std::thread worker_;

    mutable std::mutex state_mutex_;
    HANDLE pipe_{INVALID_HANDLE_VALUE};
    HANDLE stop_event_{nullptr};
    std::string client_id_;

    std::mutex queue_mutex_;
    std::deque<QueuedEvent> queue_;
    size_t queued_bytes_{0};
};

} // namespace CloudOS
