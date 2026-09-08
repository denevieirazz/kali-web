#include "cloudos_broker_event_client_v23.h"

#include <sddl.h>

#include <algorithm>
#include <string_view>
#include <vector>

namespace CloudOS
{
namespace
{
constexpr const char* kEventChannelName = "cloudos/native/events/v23";
constexpr uint32_t kMaxPayloadBytes = 1024 * 1024;
constexpr DWORD kPipeWaitMs = 750;
constexpr DWORD kInitialReconnectDelayMs = 250;
constexpr DWORD kMaxReconnectDelayMs = 5000;

std::wstring GetCurrentUserSidString()
{
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return {};
    DWORD length = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &length);
    if (length == 0) { CloseHandle(token); return {}; }
    std::vector<BYTE> buffer(length);
    if (!GetTokenInformation(token, TokenUser, buffer.data(), length, &length))
    { CloseHandle(token); return {}; }
    CloseHandle(token);
    const auto* user = reinterpret_cast<const TOKEN_USER*>(buffer.data());
    if (!user->User.Sid || !IsValidSid(user->User.Sid)) return {};
    LPWSTR raw = nullptr;
    if (!ConvertSidToStringSidW(user->User.Sid, &raw) || !raw) return {};
    std::wstring result(raw);
    LocalFree(raw);
    return result;
}

bool TryGetCurrentSessionId(DWORD* out_session_id)
{
    if (!out_session_id) return false;
    DWORD value = 0;
    if (!ProcessIdToSessionId(GetCurrentProcessId(), &value)) return false;
    *out_session_id = value;
    return true;
}

std::wstring GetCommandPipeName()
{
    const std::wstring sid = GetCurrentUserSidString();
    DWORD session_id = 0;
    if (sid.empty() || !TryGetCurrentSessionId(&session_id)) return {};
    return L"\\\\.\\pipe\\CloudOS.SystemBroker.v21." + sid + L"." +
           std::to_wstring(session_id);
}

void AppendJsonString(std::string_view value, std::string& out)
{
    static constexpr char hex[] = "0123456789abcdef";
    out.push_back('"');
    for (const unsigned char ch : value)
    {
        switch (ch)
        {
        case '"': out.append("\\\""); break;
        case '\\': out.append("\\\\"); break;
        case '\b': out.append("\\b"); break;
        case '\f': out.append("\\f"); break;
        case '\n': out.append("\\n"); break;
        case '\r': out.append("\\r"); break;
        case '\t': out.append("\\t"); break;
        default:
            if (ch < 0x20)
            {
                out.append("\\u00");
                out.push_back(hex[(ch >> 4) & 0x0f]);
                out.push_back(hex[ch & 0x0f]);
            }
            else out.push_back(static_cast<char>(ch));
            break;
        }
    }
    out.push_back('"');
}

std::string BuildRequest(
    std::string_view id,
    std::string_view method,
    std::string_view payload)
{
    std::string request;
    request.reserve(id.size() + method.size() + payload.size() + 96);
    request.append("{\"protocol\":21,\"type\":\"request\",\"id\":");
    AppendJsonString(id, request);
    request.append(",\"method\":");
    AppendJsonString(method, request);
    request.append(",\"payload\":");
    request.append(payload.empty() ? "{}" : payload);
    request.push_back('}');
    return request;
}

bool IsResponseForId(
    const std::string& frame,
    std::string_view id,
    bool require_ok)
{
    if (frame.size() > kMaxPayloadBytes ||
        frame.find("\"type\":\"response\"") == std::string::npos)
    { return false; }
    std::string fragment = "\"id\":";
    AppendJsonString(id, fragment);
    if (frame.find(fragment) == std::string::npos) return false;
    return !require_ok || frame.find("\"ok\":true") != std::string::npos;
}

bool IsBrokerEventFrame(const std::string& frame)
{
    return frame.size() <= kMaxPayloadBytes &&
           frame.find("\"type\":\"event\"") != std::string::npos &&
           frame.find("\"event\":") != std::string::npos;
}
} // namespace

CloudOSBrokerEventClientV23& CloudOSBrokerEventClientV23::Instance()
{
    static CloudOSBrokerEventClientV23 instance;
    return instance;
}

CloudOSBrokerEventClientV23::~CloudOSBrokerEventClientV23()
{
    Shutdown();
}

void CloudOSBrokerEventClientV23::Initialize(
    flutter::BinaryMessenger* messenger,
    HWND platform_window)
{
    Shutdown();
    if (!messenger || !platform_window) return;

    std::lock_guard<std::mutex> lock(lifecycle_mutex_);
    platform_window_ = platform_window;
    event_channel_ =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            messenger,
            kEventChannelName,
            &flutter::StandardMethodCodec::GetInstance());

    event_channel_->SetMethodCallHandler(
        [this](
            const flutter::MethodCall<flutter::EncodableValue>& call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            if (call.method_name() == "start")
            {
                result->Success(flutter::EncodableValue(StartWorker()));
                return;
            }
            if (call.method_name() == "stop")
            {
                StopWorker();
                result->Success(flutter::EncodableValue(true));
                return;
            }
            if (call.method_name() == "status")
            {
                flutter::EncodableMap status;
                status[flutter::EncodableValue("running")] =
                    flutter::EncodableValue(running_.load());
                status[flutter::EncodableValue("connected")] =
                    flutter::EncodableValue(connected_.load());
                status[flutter::EncodableValue("droppedEvents")] =
                    flutter::EncodableValue(
                        static_cast<int64_t>(dropped_events_.load()));
                result->Success(flutter::EncodableValue(std::move(status)));
                return;
            }
            result->NotImplemented();
        });
}

void CloudOSBrokerEventClientV23::Shutdown()
{
    StopWorker();
    {
        std::lock_guard<std::mutex> lock(lifecycle_mutex_);
        if (event_channel_)
        {
            event_channel_->SetMethodCallHandler(nullptr);
            event_channel_.reset();
        }
        platform_window_ = nullptr;
    }
    {
        std::lock_guard<std::mutex> lock(ui_mutex_);
        pending_ui_events_.clear();
        pending_ui_bytes_ = 0;
    }
}

bool CloudOSBrokerEventClientV23::StartWorker()
{
    {
        std::lock_guard<std::mutex> lock(lifecycle_mutex_);
        if (!event_channel_ || !platform_window_) return false;
        if (running_.load()) return true;
        stop_requested_.store(false);
        connected_.store(false);
        dropped_events_.store(0);
        running_.store(true);
        try
        {
            worker_ = std::thread(&CloudOSBrokerEventClientV23::WorkerLoop, this);
        }
        catch (...)
        {
            running_.store(false);
            stop_requested_.store(true);
            return false;
        }
    }

    // Do not call QueueConnectionState while lifecycle_mutex_ is held because
    // PostDrainMessage also reads platform_window_ under that mutex.
    QueueConnectionState("connecting");
    return true;
}

void CloudOSBrokerEventClientV23::StopWorker()
{
    std::thread worker;
    {
        std::lock_guard<std::mutex> lock(lifecycle_mutex_);
        stop_requested_.store(true);
        running_.store(false);
        DisconnectPipe();
        if (worker_.joinable())
        {
            CancelSynchronousIo(
                reinterpret_cast<HANDLE>(worker_.native_handle()));
            worker = std::move(worker_);
        }
    }
    if (worker.joinable()) worker.join();
    connected_.store(false);
}

void CloudOSBrokerEventClientV23::WorkerLoop()
{
    DWORD delay = kInitialReconnectDelayMs;
    while (!stop_requested_.load())
    {
        const bool reached_loop = ConnectAndSubscribe();
        if (reached_loop) delay = kInitialReconnectDelayMs;

        const bool was_connected = connected_.exchange(false);
        if (was_connected && !stop_requested_.load())
        { QueueConnectionState("disconnected"); }
        DisconnectPipe();
        if (stop_requested_.load()) break;

        DWORD slept = 0;
        while (slept < delay && !stop_requested_.load())
        {
            const DWORD slice = (std::min<DWORD>)(100, delay - slept);
            Sleep(slice);
            slept += slice;
        }
        delay = (std::min<DWORD>)(kMaxReconnectDelayMs, delay * 2);
        if (!stop_requested_.load()) QueueConnectionState("connecting");
    }
    connected_.store(false);
    running_.store(false);
}

bool CloudOSBrokerEventClientV23::ConnectAndSubscribe()
{
    const std::wstring name = GetCommandPipeName();
    if (name.empty() || !WaitNamedPipeW(name.c_str(), kPipeWaitMs)) return false;

    HANDLE pipe = CreateFileW(
        name.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
        OPEN_EXISTING, 0, nullptr);
    if (pipe == INVALID_HANDLE_VALUE) return false;
    {
        std::lock_guard<std::mutex> lock(pipe_mutex_);
        if (stop_requested_.load()) { CloseHandle(pipe); return false; }
        pipe_ = pipe;
    }

    const std::string hello_id = "flutter-events-hello";
    if (!SendFrame(
            pipe,
            BuildRequest(
                hello_id,
                "hello",
                "{\"clientName\":\"CloudOS.FlutterEvents\",\"clientVersion\":\"23\"}")))
    { return false; }

    std::string frame;
    for (;;)
    {
        if (stop_requested_.load() || !ReadFrame(pipe, frame)) return false;
        if (IsBrokerEventFrame(frame)) { QueueBrokerEvent(std::move(frame)); continue; }
        if (IsResponseForId(frame, hello_id, true)) break;
        if (IsResponseForId(frame, hello_id, false)) return false;
    }

    const std::string subscribe_id = "flutter-events-subscribe";
    if (!SendFrame(
            pipe,
            BuildRequest(
                subscribe_id,
                "events.subscribe",
                "{\"pattern\":\"*\"}")))
    { return false; }

    for (;;)
    {
        frame.clear();
        if (stop_requested_.load() || !ReadFrame(pipe, frame)) return false;
        if (IsBrokerEventFrame(frame)) { QueueBrokerEvent(std::move(frame)); continue; }
        if (IsResponseForId(frame, subscribe_id, true)) break;
        if (IsResponseForId(frame, subscribe_id, false)) return false;
    }

    connected_.store(true);
    QueueConnectionState("connected");
    while (!stop_requested_.load())
    {
        frame.clear();
        if (!ReadFrame(pipe, frame)) return true;
        if (IsBrokerEventFrame(frame)) QueueBrokerEvent(std::move(frame));
    }
    return true;
}

void CloudOSBrokerEventClientV23::DisconnectPipe()
{
    HANDLE pipe = INVALID_HANDLE_VALUE;
    {
        std::lock_guard<std::mutex> lock(pipe_mutex_);
        pipe = pipe_;
        pipe_ = INVALID_HANDLE_VALUE;
    }
    if (pipe != INVALID_HANDLE_VALUE)
    {
        CancelIoEx(pipe, nullptr);
        CloseHandle(pipe);
    }
}

bool CloudOSBrokerEventClientV23::SendFrame(
    HANDLE pipe,
    const std::string& payload)
{
    if (pipe == INVALID_HANDLE_VALUE || payload.size() > kMaxPayloadBytes) return false;
    const uint32_t length = static_cast<uint32_t>(payload.size());
    DWORD written = 0;
    DWORD total = 0;
    const auto* header = reinterpret_cast<const unsigned char*>(&length);
    while (total < sizeof(length))
    {
        if (!WriteFile(
                pipe,
                header + total,
                static_cast<DWORD>(sizeof(length) - total),
                &written,
                nullptr) || written == 0)
        { return false; }
        total += written;
    }
    total = 0;
    while (total < length)
    {
        if (!WriteFile(
                pipe,
                payload.data() + total,
                length - total,
                &written,
                nullptr) || written == 0)
        { return false; }
        total += written;
    }
    return true;
}

bool CloudOSBrokerEventClientV23::ReadFrame(
    HANDLE pipe,
    std::string& payload)
{
    if (pipe == INVALID_HANDLE_VALUE) return false;
    uint32_t length = 0;
    DWORD read = 0;
    DWORD total = 0;
    auto* header = reinterpret_cast<unsigned char*>(&length);
    while (total < sizeof(length))
    {
        if (!ReadFile(
                pipe,
                header + total,
                static_cast<DWORD>(sizeof(length) - total),
                &read,
                nullptr) || read == 0)
        { return false; }
        total += read;
    }
    if (length > kMaxPayloadBytes) return false;
    payload.assign(length, '\0');
    total = 0;
    while (total < length)
    {
        if (!ReadFile(
                pipe,
                payload.data() + total,
                length - total,
                &read,
                nullptr) || read == 0)
        { return false; }
        total += read;
    }
    return true;
}

void CloudOSBrokerEventClientV23::QueueBrokerEvent(std::string json)
{
    QueueUiEvent({
        UiEventKind::broker_event,
        std::move(json),
        dropped_events_.load()});
}

void CloudOSBrokerEventClientV23::QueueConnectionState(const std::string& state)
{
    QueueUiEvent({
        UiEventKind::connection_state,
        state,
        dropped_events_.load()});
}

void CloudOSBrokerEventClientV23::QueueUiEvent(UiEvent event)
{
    const size_t bytes = event.payload.size();
    if (bytes > kMaxPendingUiBytes) { dropped_events_++; return; }
    {
        std::lock_guard<std::mutex> lock(ui_mutex_);
        while (!pending_ui_events_.empty() &&
               (pending_ui_events_.size() >= kMaxPendingUiEvents ||
                pending_ui_bytes_ + bytes > kMaxPendingUiBytes))
        {
            pending_ui_bytes_ -= pending_ui_events_.front().payload.size();
            pending_ui_events_.pop_front();
            dropped_events_++;
        }
        event.dropped_events = dropped_events_.load();
        pending_ui_bytes_ += bytes;
        pending_ui_events_.push_back(std::move(event));
    }
    PostDrainMessage();
}

void CloudOSBrokerEventClientV23::PostDrainMessage()
{
    HWND window = nullptr;
    {
        std::lock_guard<std::mutex> lock(lifecycle_mutex_);
        window = platform_window_;
    }
    if (window) PostMessageW(window, kDispatchMessage, 0, 0);
}

void CloudOSBrokerEventClientV23::DrainPlatformEvents()
{
    std::deque<UiEvent> events;
    {
        std::lock_guard<std::mutex> lock(ui_mutex_);
        events.swap(pending_ui_events_);
        pending_ui_bytes_ = 0;
    }

    flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
    {
        std::lock_guard<std::mutex> lock(lifecycle_mutex_);
        channel = event_channel_.get();
    }
    if (!channel) return;

    for (auto& event : events)
    {
        flutter::EncodableMap args;
        args[flutter::EncodableValue("droppedEvents")] =
            flutter::EncodableValue(static_cast<int64_t>(event.dropped_events));
        if (event.kind == UiEventKind::broker_event)
        {
            args[flutter::EncodableValue("json")] =
                flutter::EncodableValue(std::move(event.payload));
            channel->InvokeMethod(
                "broker.onEvent",
                std::make_unique<flutter::EncodableValue>(std::move(args)));
        }
        else
        {
            args[flutter::EncodableValue("state")] =
                flutter::EncodableValue(std::move(event.payload));
            channel->InvokeMethod(
                "broker.onConnectionState",
                std::make_unique<flutter::EncodableValue>(std::move(args)));
        }
    }
}

} // namespace CloudOS
