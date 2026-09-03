#include "event_transport_v23.h"

#include "event_bus_v21.h"
#include "protocol_v21.h"
#include "security_v21.h"

#include <charconv>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <iostream>
#include <memory>

namespace CloudOS
{
namespace
{
constexpr size_t kMaxQueuedEvents = 256;
constexpr size_t kMaxQueuedBytes = 4u * 1024u * 1024u;
constexpr char kTransportName[] = "CloudOS.EventTransport.V23";

bool SendFramedPayload(HANDLE pipe, const std::string& payload)
{
    if (pipe == nullptr || pipe == INVALID_HANDLE_VALUE ||
        payload.size() > kMaxPayloadBytes)
    {
        return false;
    }

    const uint32_t length = static_cast<uint32_t>(payload.size());
    DWORD written = 0;
    if (!WriteFile(pipe, &length, sizeof(length), &written, nullptr) ||
        written != sizeof(length))
    {
        return false;
    }
    if (length > 0 &&
        (!WriteFile(pipe, payload.data(), length, &written, nullptr) ||
         written != length))
    {
        return false;
    }
    return true;
}

bool ReadFramedPayload(HANDLE pipe, std::string& payload)
{
    payload.clear();
    if (pipe == nullptr || pipe == INVALID_HANDLE_VALUE) return false;

    uint32_t length = 0;
    DWORD read_bytes = 0;
    if (!ReadFile(pipe, &length, sizeof(length), &read_bytes, nullptr) ||
        read_bytes != sizeof(length) || length > kMaxPayloadBytes)
    {
        return false;
    }

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
        {
            return false;
        }
        total += read_bytes;
    }
    return true;
}

struct EventSessionV23 final
{
    HANDLE pipe{INVALID_HANDLE_VALUE};
    std::mutex queue_mutex;
    std::condition_variable queue_changed;
    std::deque<std::string> queue;
    size_t queued_bytes{0};
    std::atomic_bool closing{false};
    std::thread sender_thread;

    uint64_t Enqueue(std::string payload)
    {
        if (payload.empty() || payload.size() > kMaxPayloadBytes) return 1;

        uint64_t dropped = 0;
        {
            std::lock_guard<std::mutex> lock(queue_mutex);
            if (closing.load()) return 1;

            while (!queue.empty() &&
                   (queue.size() >= kMaxQueuedEvents ||
                    queued_bytes + payload.size() > kMaxQueuedBytes))
            {
                queued_bytes -= queue.front().size();
                queue.pop_front();
                ++dropped;
            }

            if (queued_bytes + payload.size() > kMaxQueuedBytes)
            {
                return dropped + 1;
            }

            queued_bytes += payload.size();
            queue.push_back(std::move(payload));
        }
        queue_changed.notify_one();
        return dropped;
    }
};

bool ParseHandshake(
    const std::string& frame,
    std::string& client_id)
{
    JsonValue root;
    if (!ParseJson(frame, root) || !root.IsObject()) return false;
    const JsonObject& object = root.AsObject();

    const auto schema_it = object.find("schema");
    const auto transport_it = object.find("transport");
    const auto client_it = object.find("clientId");
    if (schema_it == object.end() || !schema_it->second.IsInt() ||
        schema_it->second.AsInt() != 23 ||
        transport_it == object.end() || !transport_it->second.IsString() ||
        transport_it->second.AsString() != kTransportName ||
        client_it == object.end() || !client_it->second.IsString())
    {
        return false;
    }

    client_id = client_it->second.AsString();
    return !client_id.empty() && client_id.size() <= 256;
}
} // namespace

EventTransportV23& EventTransportV23::Instance()
{
    static EventTransportV23 instance;
    return instance;
}

EventTransportV23::~EventTransportV23()
{
    Stop();
}

bool EventTransportV23::Start()
{
    if (running_.exchange(true)) return true;
    dropped_events_.store(0);

    try
    {
        listener_thread_ = std::thread(&EventTransportV23::ListenerLoop, this);
    }
    catch (...)
    {
        running_.store(false);
        return false;
    }
    return true;
}

void EventTransportV23::Stop()
{
    if (!running_.exchange(false)) return;

    // Wake a blocking ConnectNamedPipe without introducing a second control
    // protocol. Security still restricts this local self-connect to the same
    // user/session.
    const std::wstring pipe_name = SecurityV21::GetEventsPipeName();
    HANDLE wake = CreateFileW(
        pipe_name.c_str(),
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr);
    if (wake != INVALID_HANDLE_VALUE) CloseHandle(wake);

    if (listener_thread_.joinable()) listener_thread_.join();

    {
        std::lock_guard<std::mutex> lock(client_threads_mutex_);
        for (std::thread& thread : client_threads_)
        {
            if (thread.joinable()) thread.join();
        }
        client_threads_.clear();
    }
}

bool EventTransportV23::SendFrame(HANDLE pipe, const std::string& payload)
{
    return SendFramedPayload(pipe, payload);
}

bool EventTransportV23::ReadFrame(HANDLE pipe, std::string& payload)
{
    return ReadFramedPayload(pipe, payload);
}

bool EventTransportV23::ClientIdMatchesProcess(
    const std::string& client_id,
    DWORD process_id) noexcept
{
    constexpr char marker[] = "-pid-";
    if (client_id.rfind("client-", 0) != 0) return false;
    const size_t marker_pos = client_id.rfind(marker);
    if (marker_pos == std::string::npos) return false;

    const char* first = client_id.data() + marker_pos + sizeof(marker) - 1;
    const char* last = client_id.data() + client_id.size();
    if (first == last) return false;

    uint64_t parsed = 0;
    const auto result = std::from_chars(first, last, parsed);
    return result.ec == std::errc{} &&
        result.ptr == last &&
        parsed == static_cast<uint64_t>(process_id);
}

void EventTransportV23::ListenerLoop()
{
    const std::wstring pipe_name = SecurityV21::GetEventsPipeName();
    while (running_.load())
    {
        SECURITY_ATTRIBUTES attributes{};
        PSECURITY_DESCRIPTOR descriptor = nullptr;
        if (!SecurityV21::CreatePerUserSecurityAttributes(
                &attributes,
                &descriptor))
        {
            Sleep(100);
            continue;
        }

        HANDLE pipe = CreateNamedPipeW(
            pipe_name.c_str(),
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT |
                PIPE_REJECT_REMOTE_CLIENTS,
            PIPE_UNLIMITED_INSTANCES,
            65536,
            65536,
            0,
            &attributes);
        SecurityV21::FreeSecurityDescriptor(descriptor);

        if (pipe == INVALID_HANDLE_VALUE)
        {
            Sleep(100);
            continue;
        }

        const BOOL connected = ConnectNamedPipe(pipe, nullptr)
            ? TRUE
            : (GetLastError() == ERROR_PIPE_CONNECTED);
        if (!running_.load())
        {
            CloseHandle(pipe);
            break;
        }
        if (!connected)
        {
            CloseHandle(pipe);
            continue;
        }

        DWORD client_process_id = 0;
        if (!SecurityV21::ValidateNamedPipeClient(pipe, &client_process_id))
        {
            DisconnectNamedPipe(pipe);
            CloseHandle(pipe);
            continue;
        }

        try
        {
            std::lock_guard<std::mutex> lock(client_threads_mutex_);
            client_threads_.emplace_back(
                &EventTransportV23::ClientLoop,
                this,
                pipe,
                client_process_id);
        }
        catch (...)
        {
            DisconnectNamedPipe(pipe);
            CloseHandle(pipe);
        }
    }
}

void EventTransportV23::ClientLoop(HANDLE pipe, DWORD process_id)
{
    std::string handshake;
    std::string client_id;
    if (!ReadFrame(pipe, handshake) ||
        !ParseHandshake(handshake, client_id) ||
        !ClientIdMatchesProcess(client_id, process_id))
    {
        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
        return;
    }

    auto session = std::make_shared<EventSessionV23>();
    session->pipe = pipe;

    EventBusV21::Instance().RegisterDedicatedClientV23(
        client_id,
        [this, weak = std::weak_ptr<EventSessionV23>(session)](
            const BrokerEvent& event) {
            const auto alive = weak.lock();
            if (!alive) return;
            const uint64_t dropped = alive->Enqueue(SerializeEvent(event));
            if (dropped > 0) dropped_events_.fetch_add(dropped);
        });

    try
    {
        session->sender_thread = std::thread([session]() {
            while (!session->closing.load())
            {
                std::string frame;
                {
                    std::unique_lock<std::mutex> lock(session->queue_mutex);
                    session->queue_changed.wait_for(
                        lock,
                        std::chrono::milliseconds(250),
                        [session]() {
                            return session->closing.load() || !session->queue.empty();
                        });
                    if (session->closing.load() && session->queue.empty()) break;
                    if (session->queue.empty()) continue;

                    frame = std::move(session->queue.front());
                    session->queued_bytes -= frame.size();
                    session->queue.pop_front();
                }

                if (!SendFramedPayload(session->pipe, frame))
                {
                    session->closing.store(true);
                    break;
                }
            }
        });
    }
    catch (...)
    {
        EventBusV21::Instance().UnregisterClient(client_id);
        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
        return;
    }

    // The event pipe is server->client after the handshake. PeekNamedPipe is
    // used only as a bounded disconnect probe, so command RPC and event frames
    // can never interleave on the same byte stream.
    while (running_.load() && !session->closing.load())
    {
        DWORD available = 0;
        if (!PeekNamedPipe(pipe, nullptr, 0, nullptr, &available, nullptr)) break;
        Sleep(250);
    }

    EventBusV21::Instance().UnregisterClient(client_id);
    session->closing.store(true);
    session->queue_changed.notify_all();

    // Break a blocked writer deterministically before joining the sender.
    DisconnectNamedPipe(pipe);
    if (session->sender_thread.joinable())
    {
        CancelSynchronousIo(
            reinterpret_cast<HANDLE>(session->sender_thread.native_handle()));
        session->sender_thread.join();
    }
    CloseHandle(pipe);
}

} // namespace CloudOS
